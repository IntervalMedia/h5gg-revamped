#ifndef H5GG_PLUGIN_RPC_H
#define H5GG_PLUGIN_RPC_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol H5GGPluginRPC <NSObject>
-(nullable id)h5ggInvoke:(NSString*)method
               arguments:(NSArray*)arguments
                   error:(NSError* _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END

#endif
