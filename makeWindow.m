#import "makeWindow.h"

UIWindow* makeWindow(NSString* clazz) {
    UIWindow* w = nil;
    if (@available(iOS 13.0, *)) {
        UIWindowScene* theScene = nil;
        for (UIWindowScene* windowScene in [UIApplication sharedApplication].connectedScenes) {
            NSLog(@"windowScene=%@ %@ state=%ld", windowScene, windowScene.windows, (long)windowScene.activationState);
            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                theScene = windowScene;
                break;
            }
            if(!theScene) theScene = windowScene;
        }
        w = [[NSClassFromString(clazz) alloc] initWithWindowScene:theScene];
    } else {
        CGRect frame = [UIScreen mainScreen].bounds;
        w = [[NSClassFromString(clazz) alloc] initWithFrame:frame];
        NSLog(@"makeWindow=frame=%@", NSStringFromCGRect(w.frame));
    }
    return w;
}

@implementation UIWindow (GVWindow)

- (void)private_updateToInterfaceOrientation:(UIInterfaceOrientation)orientation animated:(BOOL)animated {
    NSLog(@"private_updateToInterfaceOrientation=%ld %d %@", (long)orientation, animated, self);
    SEL mySelector = @selector(_updateToInterfaceOrientation:animated:);
    if([self respondsToSelector:mySelector]) {
        NSMethodSignature *sig = [[self class] instanceMethodSignatureForSelector:mySelector];
        NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:sig];
        [myInvocation setTarget:self];
        [myInvocation setSelector:mySelector];
        [myInvocation setArgument:&orientation atIndex:2];
        [myInvocation setArgument:&animated atIndex:3];
        [myInvocation retainArguments];
        [myInvocation invoke];
    }
}

@end
