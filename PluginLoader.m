#import "PluginLoaderInternal.h"

#import "H5GGPluginRPC.h"

#include <dlfcn.h>

@interface H5GGPluginLoader ()
@property (nonatomic, copy) NSString* bundlePath;
@property (nonatomic, copy) H5GGLibraryLoader libraryLoader;
@property (nonatomic, copy) H5GGLibraryCloser libraryCloser;
@property (nonatomic, copy) H5GGPluginClassResolver classResolver;
@property (nonatomic, strong) NSMutableDictionary<NSString*,NSValue*>* libraryHandles;
@property (nonatomic, strong) NSMutableDictionary<NSString*,id<H5GGPluginRPC>>* pluginObjects;
@end

@implementation H5GGPluginLoader

-(instancetype)initWithBundlePath:(NSString*)bundlePath {
    return [self initWithBundlePath:bundlePath
                      libraryLoader:^void*(NSString* path, NSString** error) {
        dlerror();
        const char* filePath = path.fileSystemRepresentation;
        if(!filePath) {
            if(error) *error = @"Plugin path cannot be represented by the file system";
            return NULL;
        }
        void* handle = dlopen(filePath, RTLD_NOW);
        if(handle) return handle;
        const char* loaderError = dlerror();
        if(error) {
            NSString* message = loaderError
                ? [NSString stringWithUTF8String:loaderError]
                : @"Unable to load plugin";
            *error = message ?: @"Unable to load plugin";
        }
        return NULL;
    }
                      libraryCloser:^(void* handle) {
        // Objective-C classes cannot be safely unloaded. Retain the image for
        // process lifetime even if the engine façade is released.
        (void)handle;
    }
                       classResolver:^Class(NSString* className) {
        return NSClassFromString(className);
    }];
}

-(instancetype)initWithBundlePath:(NSString*)bundlePath
                    libraryLoader:(H5GGLibraryLoader)libraryLoader
                    libraryCloser:(H5GGLibraryCloser)libraryCloser
                     classResolver:(H5GGPluginClassResolver)classResolver {
    self = [super init];
    if(self) {
        _bundlePath = [bundlePath copy] ?: @"";
        _libraryLoader = [libraryLoader copy];
        _libraryCloser = [libraryCloser copy];
        _classResolver = [classResolver copy];
        if(!_libraryLoader || !_libraryCloser || !_classResolver) return nil;
        _libraryHandles = [NSMutableDictionary dictionary];
        _pluginObjects = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)dealloc {
    [_pluginObjects removeAllObjects];
    for(NSValue* handle in _libraryHandles.allValues) {
        _libraryCloser(handle.pointerValue);
    }
}

-(nullable id)loadPluginClass:(NSString*)className
                         path:(NSString*)path
                         mode:(H5GGPluginLoadMode)mode {
    if(className.length == 0 || path.length == 0) {
        return @{@"loaded": @NO, @"error": @"Class name and dylib path are required"};
    }
    if(mode != H5GGPluginLoadModeLegacyObject &&
       mode != H5GGPluginLoadModeJSONRPC) {
        return @{@"loaded": @NO, @"error": @"Unknown plugin load mode"};
    }

    NSString* resolvedPath = path;
    if(!resolvedPath.isAbsolutePath) {
        resolvedPath = [_bundlePath stringByAppendingPathComponent:resolvedPath];
    }
    resolvedPath = resolvedPath.stringByStandardizingPath;

    NSString* loadError = nil;
    @synchronized(self) {
        if(!_libraryHandles[resolvedPath]) {
            void* handle = _libraryLoader(resolvedPath, &loadError);
            if(handle) {
                _libraryHandles[resolvedPath] = [NSValue valueWithPointer:handle];
            }
        }
    }
    if(loadError) return @{@"loaded": @NO, @"error": loadError};
    @synchronized(self) {
        if(!_libraryHandles[resolvedPath]) {
            return @{@"loaded": @NO, @"error": @"Unable to load plugin"};
        }
    }

    Class pluginClass = _classResolver(className);
    if(!pluginClass) {
        return @{@"loaded": @NO, @"error": @"Plugin class was not found"};
    }

    id pluginObject = nil;
    @try {
        pluginObject = [pluginClass new];
    } @catch(NSException* exception) {
        return @{
            @"loaded": @NO,
            @"error": exception.reason ?: exception.name,
        };
    }
    if(!pluginObject) {
        return @{@"loaded": @NO, @"error": @"Plugin class could not be initialized"};
    }
    if(mode == H5GGPluginLoadModeLegacyObject) return pluginObject;

    if(![pluginObject conformsToProtocol:@protocol(H5GGPluginRPC)]) {
        return @{
            @"loaded": @NO,
            @"error": @"WK plugins must implement the H5GGPluginRPC protocol",
        };
    }

    NSString* pluginId = NSUUID.UUID.UUIDString;
    @synchronized(self) {
        _pluginObjects[pluginId] = pluginObject;
    }
    return @{
        @"loaded": @YES,
        @"id": pluginId,
        @"className": className,
        @"rpc": @YES,
    };
}

-(NSDictionary<NSString*,id>*)callPlugin:(NSString*)pluginId
                                  method:(NSString*)method
                               arguments:(NSArray*)arguments {
    if(pluginId.length == 0) {
        return @{@"ok": @NO, @"error": @"Unknown plugin handle"};
    }
    id<H5GGPluginRPC> plugin = nil;
    @synchronized(self) {
        plugin = _pluginObjects[pluginId];
    }
    if(!plugin) return @{@"ok": @NO, @"error": @"Unknown plugin handle"};
    if(method.length == 0 || ![arguments isKindOfClass:NSArray.class]) {
        return @{@"ok": @NO, @"error": @"A method name and argument array are required"};
    }
    if(![NSJSONSerialization isValidJSONObject:@[arguments]]) {
        return @{@"ok": @NO, @"error": @"Plugin arguments are not JSON serializable"};
    }

    NSError* error = nil;
    id result = nil;
    @try {
        result = [plugin h5ggInvoke:method arguments:arguments error:&error];
    } @catch(NSException* exception) {
        return @{
            @"ok": @NO,
            @"error": exception.reason ?: exception.name,
        };
    }

    if(error) return @{@"ok": @NO, @"error": error.localizedDescription};
    id jsonResult = result ?: NSNull.null;
    if(![NSJSONSerialization isValidJSONObject:@[jsonResult]]) {
        return @{@"ok": @NO, @"error": @"Plugin result is not JSON serializable"};
    }
    return @{@"ok": @YES, @"result": jsonResult};
}

-(NSDictionary<NSString*,id>*)capabilities {
    return @{
        @"transport": @"rpc",
        @"protocol": @"H5GGPluginRPC",
        @"legacyJavaScriptCoreObjects": @YES,
        @"wkNativeObjects": @NO,
        @"jsonArgumentsAndResultsOnly": @YES,
    };
}

@end
