#ifndef FloatWindow_h
#define FloatWindow_h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppWinController : UIViewController
@property (nonatomic, strong, nullable) UIViewController* bindVC;
- (instancetype)initWithBind:(UIViewController*)vc;
@end

@interface FloatController : UIViewController
@property (nonatomic) UIInterfaceOrientationMask followOrientationMask;
@property (nonatomic, copy, nullable) void (^onResizeCallback)(CGSize size);
@end

@interface FloatWindow : UIWindow
@end

NS_ASSUME_NONNULL_END

#endif /* FloatWindow_h */
