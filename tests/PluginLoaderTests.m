#import "../PluginLoaderInternal.h"
#import "../H5GGPluginRPC.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

@interface H5GGTestLegacyPlugin : NSObject
@end

@implementation H5GGTestLegacyPlugin
@end

@interface H5GGTestThrowingPlugin : NSObject
@end

@implementation H5GGTestThrowingPlugin

-(instancetype)init {
    @throw [NSException exceptionWithName:@"PluginInitException"
                                   reason:@"test initializer exception"
                                 userInfo:nil];
}

@end

@interface H5GGTestRPCPlugin : NSObject <H5GGPluginRPC>
@end

@implementation H5GGTestRPCPlugin

-(id)h5ggInvoke:(NSString*)method
      arguments:(NSArray*)arguments
          error:(NSError**)error {
    if([method isEqualToString:@"echo"]) return arguments.firstObject;
    if([method isEqualToString:@"null"]) return nil;
    if([method isEqualToString:@"invalid-result"]) return NSDate.date;
    if([method isEqualToString:@"throw"]) {
        @throw [NSException exceptionWithName:@"PluginException"
                                       reason:@"test plugin exception"
                                     userInfo:nil];
    }
    if(error) {
        *error = [NSError errorWithDomain:@"H5GGPluginLoaderTests"
                                     code:1
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"test plugin error",
        }];
    }
    return nil;
}

@end

int main() {
    __block int loadCount = 0;
    __block int closeCount = 0;
    __block NSString* loadedPath = nil;

    @autoreleasepool {
        H5GGPluginLoader* loader = [[H5GGPluginLoader alloc]
            initWithBundlePath:@"/tmp/H5GG Test.app"
                 libraryLoader:^void*(NSString* path, NSString** error) {
            loadCount++;
            loadedPath = path;
            if([path.lastPathComponent isEqualToString:@"fail.dylib"]) {
                if(error) *error = @"test loader failure";
                return NULL;
            }
            return (void*)(uintptr_t)(0x1000 + loadCount);
        }
                 libraryCloser:^(void* handle) {
            assert(handle != NULL);
            closeCount++;
        }
                  classResolver:^Class(NSString* className) {
            if([className isEqualToString:@"LegacyPlugin"]) {
                return H5GGTestLegacyPlugin.class;
            }
            if([className isEqualToString:@"RPCPlugin"]) {
                return H5GGTestRPCPlugin.class;
            }
            if([className isEqualToString:@"ThrowingPlugin"]) {
                return H5GGTestThrowingPlugin.class;
            }
            return Nil;
        }];
        assert(loader);

        NSDictionary* missingArguments = [loader loadPluginClass:@""
                                                              path:@"plugin.dylib"
                                                              mode:H5GGPluginLoadModeJSONRPC];
        assert(![missingArguments[@"loaded"] boolValue]);
        assert(loadCount == 0);

        NSDictionary* loadFailure = [loader loadPluginClass:@"RPCPlugin"
                                                         path:@"fail.dylib"
                                                         mode:H5GGPluginLoadModeJSONRPC];
        assert(![loadFailure[@"loaded"] boolValue]);
        assert([loadFailure[@"error"] isEqualToString:@"test loader failure"]);
        assert(loadCount == 1);

        NSDictionary* missingClass = [loader loadPluginClass:@"MissingPlugin"
                                                         path:@"plugin.dylib"
                                                         mode:H5GGPluginLoadModeJSONRPC];
        assert(![missingClass[@"loaded"] boolValue]);
        assert([missingClass[@"error"] isEqualToString:@"Plugin class was not found"]);
        assert([loadedPath isEqualToString:@"/tmp/H5GG Test.app/plugin.dylib"]);
        assert(loadCount == 2);

        id legacy = [loader loadPluginClass:@"LegacyPlugin"
                                       path:@"plugin.dylib"
                                       mode:H5GGPluginLoadModeLegacyObject];
        assert([legacy isKindOfClass:H5GGTestLegacyPlugin.class]);
        assert(loadCount == 2);

        NSDictionary* nonRPC = [loader loadPluginClass:@"LegacyPlugin"
                                                    path:@"plugin.dylib"
                                                    mode:H5GGPluginLoadModeJSONRPC];
        assert(![nonRPC[@"loaded"] boolValue]);
        assert([nonRPC[@"error"] containsString:@"H5GGPluginRPC"]);
        assert(loadCount == 2);

        NSDictionary* initFailure = [loader loadPluginClass:@"ThrowingPlugin"
                                                       path:@"plugin.dylib"
                                                       mode:H5GGPluginLoadModeJSONRPC];
        assert(![initFailure[@"loaded"] boolValue]);
        assert([initFailure[@"error"] isEqualToString:@"test initializer exception"]);
        assert(loadCount == 2);

        NSDictionary* descriptor = [loader loadPluginClass:@"RPCPlugin"
                                                       path:@"plugin.dylib"
                                                       mode:H5GGPluginLoadModeJSONRPC];
        assert([descriptor[@"loaded"] boolValue]);
        assert([descriptor[@"rpc"] boolValue]);
        assert([descriptor[@"className"] isEqualToString:@"RPCPlugin"]);
        NSString* pluginId = descriptor[@"id"];
        assert(pluginId.length > 0);
        assert(loadCount == 2);

        NSDictionary* secondDescriptor = [loader loadPluginClass:@"RPCPlugin"
                                                             path:@"plugin.dylib"
                                                             mode:H5GGPluginLoadModeJSONRPC];
        assert(![secondDescriptor[@"id"] isEqualToString:pluginId]);
        assert(loadCount == 2);

        NSDictionary* unknown = [loader callPlugin:@"unknown"
                                             method:@"echo"
                                          arguments:@[@"value"]];
        assert(![unknown[@"ok"] boolValue]);

        NSDictionary* invalidArguments = [loader callPlugin:pluginId
                                                       method:@"echo"
                                                    arguments:@[NSDate.date]];
        assert(![invalidArguments[@"ok"] boolValue]);
        assert([invalidArguments[@"error"] containsString:@"not JSON serializable"]);

        NSDictionary* echoed = [loader callPlugin:pluginId
                                            method:@"echo"
                                         arguments:@[@{@"key": @"value"}]];
        assert([echoed[@"ok"] boolValue]);
        assert([echoed[@"result"] isEqual:@{@"key": @"value"}]);

        NSDictionary* nullResult = [loader callPlugin:pluginId
                                                method:@"null"
                                             arguments:@[]];
        assert([nullResult[@"ok"] boolValue]);
        assert(nullResult[@"result"] == NSNull.null);

        NSDictionary* pluginError = [loader callPlugin:pluginId
                                                  method:@"error"
                                               arguments:@[]];
        assert(![pluginError[@"ok"] boolValue]);
        assert([pluginError[@"error"] isEqualToString:@"test plugin error"]);

        NSDictionary* exception = [loader callPlugin:pluginId
                                                method:@"throw"
                                             arguments:@[]];
        assert(![exception[@"ok"] boolValue]);
        assert([exception[@"error"] isEqualToString:@"test plugin exception"]);

        NSDictionary* invalidResult = [loader callPlugin:pluginId
                                                    method:@"invalid-result"
                                                 arguments:@[]];
        assert(![invalidResult[@"ok"] boolValue]);
        assert([invalidResult[@"error"] containsString:@"not JSON serializable"]);

        NSDictionary* capabilities = loader.capabilities;
        assert([capabilities[@"transport"] isEqualToString:@"rpc"]);
        assert([capabilities[@"protocol"] isEqualToString:@"H5GGPluginRPC"]);

        loader = nil;
    }

    assert(loadCount == 2);
    assert(closeCount == 1);
    puts("PluginLoader contract tests passed");
    return 0;
}
