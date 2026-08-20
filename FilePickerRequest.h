#ifndef H5GG_FILE_PICKER_REQUEST_H
#define H5GG_FILE_PICKER_REQUEST_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^H5GGFilePickerResolver)(NSNumber* callId,
                                       NSString* _Nullable path);

@interface H5GGFilePickerRequest : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString*>* documentTypes;

-(instancetype)init NS_UNAVAILABLE;
-(nullable instancetype)initWithCallId:(NSNumber*)callId
                        requestedTypes:(nullable NSArray*)requestedTypes
                              resolver:(H5GGFilePickerResolver)resolver;
-(BOOL)completeWithPath:(nullable NSString*)path;

@end

NS_ASSUME_NONNULL_END

#endif
