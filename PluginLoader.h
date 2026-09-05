#ifndef H5GG_PLUGIN_LOADER_H
#define H5GG_PLUGIN_LOADER_H

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, H5GGPluginLoadMode) {
    H5GGPluginLoadModeLegacyObject,
    H5GGPluginLoadModeJSONRPC,
};

NS_ASSUME_NONNULL_BEGIN

@interface H5GGPluginLoader : NSObject

-(instancetype)initWithBundlePath:(NSString*)bundlePath;
-(nullable id)loadPluginClass:(NSString*)className
                         path:(NSString*)path
                         mode:(H5GGPluginLoadMode)mode;
-(NSDictionary<NSString*,id>*)callPlugin:(NSString*)pluginId
                                  method:(NSString*)method
                               arguments:(NSArray*)arguments;
-(NSDictionary<NSString*,id>*)capabilities;

@end

NS_ASSUME_NONNULL_END

#endif
