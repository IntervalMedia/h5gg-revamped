#ifndef TopShow_h
#define TopShow_h

#import <UIKit/UIKit.h>
#include "makeWindow.h"

NS_ASSUME_NONNULL_BEGIN

@interface TopShow : UIViewController <UIDocumentPickerDelegate>
@property (nonatomic) UIInterfaceOrientationMask followOrientationMask;
@property (nonatomic, strong, nullable) UIWindow* alertWindow;
@property (nonatomic, strong, nullable) NSString* pickedfile;
@property (nonatomic, copy, nullable) void(^pickedfile_notify)(void);

+ (void)present:(UIViewController* _Nonnull (^)(TopShow* controller))alert;
+ (void)alert:(NSString*)title message:(NSString*)message;
+ (void)filePicker:(NSArray*)types callback:(void(^)(NSString*))callback;
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END

#endif /* TopShow_h */
