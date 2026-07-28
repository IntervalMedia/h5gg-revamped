#ifndef makeWindow_h
#define makeWindow_h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif
UIWindow* makeWindow(NSString* clazz);
#ifdef __cplusplus
}
#endif

@interface UIWindow (GVWindow)
- (void)private_updateToInterfaceOrientation:(UIInterfaceOrientation)orientation animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END

#endif /* makeWindow_h */
