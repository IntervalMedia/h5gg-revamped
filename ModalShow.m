#import "ModalShow.h"
#import "Localized.h"
#import <dlfcn.h>

@implementation ModalShow

static dispatch_semaphore_t semaphore;

+ (void)present:(UIViewController*(^)(void))alert InWindow:(UIWindow*)window {
    NSLog(@"ModalShow present[%d] %@", [NSThread isMainThread], [NSThread currentThread].name);

    semaphore = dispatch_semaphore_create(0);

    void(^submit)() = ^{
        NSLog(@"ModalShow running[%d] %@", [NSThread isMainThread], [NSThread currentThread].name);
        [window.rootViewController presentViewController:alert() animated:YES completion:nil];
    };

    if([NSThread isMainThread]) {
        submit();
        while(dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW))
            [[NSRunLoop currentRunLoop] runMode:[[NSRunLoop currentRunLoop] currentMode] beforeDate:[NSDate distantFuture]];
    } else {
        dispatch_async(dispatch_get_main_queue(), submit);

        void (*WebThreadUnlockFromAnyThread)(void) = dlsym(RTLD_DEFAULT, "WebThreadUnlockFromAnyThread");

        if([[NSThread currentThread].name isEqualToString:@"WebThread"])
            if(WebThreadUnlockFromAnyThread) WebThreadUnlockFromAnyThread();

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }

    NSLog(@"ModalShow dismiss!");
}

+ (void)dismiss {
    dispatch_semaphore_signal(semaphore);
}

+ (void)alert:(NSString*)title message:(NSString*)message InWindow:(UIWindow*)window {
    [self present:^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self dismiss];
        }]];
        return alert;
    } InWindow:window];
}

+ (BOOL)confirm:(NSString*)message InWindow:(UIWindow*)window {
    __block BOOL result = NO;

    [self present:^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:Localized(@"提示") message:message preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            result = YES;
            [self dismiss];
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"取消") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            result = NO;
            [self dismiss];
        }]];

        return alert;
    } InWindow:window];

    return result;
}

+ (NSString*)prompt:(NSString*)text defaultText:(NSString*)defaultText InWindow:(UIWindow*)window {
    __block NSString* result;

    [self present:^{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = defaultText;
        }];

        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            result = alert.textFields.lastObject.text;
            [self dismiss];
        }]];

        return alert;
    } InWindow:window];

    return result;
}

// Public API methods (without InWindow) - these need a window
// They rely on being called from a context where the current window is available
+ (void)alert:(NSString*)title message:(NSString*)message {
    UIWindow* keyWindow;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene*>* scenes = [UIApplication sharedApplication].connectedScenes;
        UIWindowScene* activeScene = nil;
        for (UIWindowScene* scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = scene; break;
            }
        }
        keyWindow = activeScene.keyWindow;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    if(keyWindow) [self alert:title message:message InWindow:keyWindow];
}

+ (BOOL)confirm:(NSString*)message {
    UIWindow* keyWindow;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene*>* scenes = [UIApplication sharedApplication].connectedScenes;
        UIWindowScene* activeScene = nil;
        for (UIWindowScene* scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = scene; break;
            }
        }
        keyWindow = activeScene.keyWindow;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    if(keyWindow) return [self confirm:message InWindow:keyWindow];
    return NO;
}

+ (NSString*)prompt:(NSString*)text defaultText:(NSString*)defaultText {
    UIWindow* keyWindow;
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene*>* scenes = [UIApplication sharedApplication].connectedScenes;
        UIWindowScene* activeScene = nil;
        for (UIWindowScene* scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = scene; break;
            }
        }
        keyWindow = activeScene.keyWindow;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    }
    if(keyWindow) return [self prompt:text defaultText:defaultText InWindow:keyWindow];
    return nil;
}

@end
