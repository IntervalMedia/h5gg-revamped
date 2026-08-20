#ifndef H5GG_DUMP_CONTROLLER_H
#define H5GG_DUMP_CONTROLLER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface H5GGDumpController : NSObject

@property (atomic, copy, readonly) NSDictionary<NSString*,id>* status;

-(instancetype)init NS_UNAVAILABLE;
-(BOOL)startFrom:(NSString*)start end:(NSString*)end filename:(NSString*)filename;
-(BOOL)cancel;

@end

NS_ASSUME_NONNULL_END

#endif
