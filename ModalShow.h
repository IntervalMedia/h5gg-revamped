#ifndef ModalShow_h
#define ModalShow_h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ModalShow : NSObject
+ (void)alert:(NSString*)title message:(NSString*)message;
+ (BOOL)confirm:(NSString*)message;
+ (NSString*)prompt:(NSString*)text defaultText:(NSString*)defaultText;
+ (void)alert:(NSString*)title message:(NSString*)message InWindow:(UIWindow*)window;
+ (BOOL)confirm:(NSString*)message InWindow:(UIWindow*)window;
+ (NSString*)prompt:(NSString*)text defaultText:(NSString*)defaultText InWindow:(UIWindow*)window;
@end

NS_ASSUME_NONNULL_END

#endif /* ModalShow_h */
