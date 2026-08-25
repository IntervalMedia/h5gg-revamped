#import "ModalShow.h"
#import "Localized.h"
#import "makeWindow.h"
#include "ModalRequestQueue.h"
#import <dlfcn.h>

#include <memory>

@interface H5GGModalPresenter : UIViewController
@property (nonatomic) UIInterfaceOrientationMask orientationMask;
@end

@implementation H5GGModalPresenter

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.orientationMask ?: UIInterfaceOrientationMaskAll;
}

@end

@implementation ModalShow

static ModalRequestQueue requestQueue;

+ (void)present:(UIViewController*(^)(dispatch_block_t finish))alert InWindow:(UIWindow*)window {
    NSLog(@"ModalShow present[%d] %@", [NSThread isMainThread], [NSThread currentThread].name);

    auto request = std::make_shared<ModalRequestQueue::Request>(requestQueue.enqueue());
    __block UIWindow* dialogWindow = nil;
    dispatch_block_t finish = ^{
        void (^cleanup)(void) = ^{
            [dialogWindow setHidden:YES];
            dialogWindow.rootViewController = nil;
            dialogWindow = nil;
            request->complete();
        };
        if(NSThread.isMainThread)
            cleanup();
        else
            dispatch_async(dispatch_get_main_queue(), cleanup);
    };

    void(^submit)() = ^{
        NSLog(@"ModalShow running[%d] %@", [NSThread isMainThread], [NSThread currentThread].name);
        UIViewController* controller = alert(finish);
        dialogWindow = makeWindow(NSStringFromClass(UIWindow.class));
        if(!dialogWindow || !controller) {
            finish();
            return;
        }

        H5GGModalPresenter* presenter = [H5GGModalPresenter new];
        presenter.orientationMask = window.rootViewController.supportedInterfaceOrientations;
        dialogWindow.rootViewController = presenter;
        dialogWindow.backgroundColor = UIColor.clearColor;
        dialogWindow.windowLevel = MAX(UIWindowLevelAlert + 1, window.windowLevel + 1);
        [dialogWindow setHidden:NO];

        @try {
            [presenter presentViewController:controller animated:YES completion:nil];
        } @catch(NSException* exception) {
            NSLog(@"ModalShow presentation failed: %@", exception.reason);
            finish();
        }
    };

    if([NSThread isMainThread]) {
        NSRunLoop* runLoop = NSRunLoop.currentRunLoop;
        while(!request->active() && !request->completed()) {
            NSString* mode = runLoop.currentMode ?: NSDefaultRunLoopMode;
            [runLoop runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        if(request->completed()) return;

        submit();
        while(!request->completed()) {
            NSString* mode = runLoop.currentMode ?: NSDefaultRunLoopMode;
            [runLoop runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    } else {
        request->waitUntilActive();
        if(request->completed()) return;
        dispatch_async(dispatch_get_main_queue(), submit);

        auto WebThreadUnlockFromAnyThread = reinterpret_cast<void (*)(void)>(
            dlsym(RTLD_DEFAULT, "WebThreadUnlockFromAnyThread"));

        if([[NSThread currentThread].name isEqualToString:@"WebThread"])
            if(WebThreadUnlockFromAnyThread) WebThreadUnlockFromAnyThread();

        request->waitUntilCompleted();
    }

    NSLog(@"ModalShow dismiss!");
}

static void H5GGDismissAlert(UIAlertController* alert, dispatch_block_t finish) {
    if(!alert.presentingViewController) {
        finish();
        return;
    }
    [alert dismissViewControllerAnimated:YES completion:finish];
}

+ (void)alert:(NSString*)title message:(NSString*)message InWindow:(UIWindow*)window {
    [self present:^UIViewController*(dispatch_block_t finish) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        __weak UIAlertController* weakAlert = alert;
        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            H5GGDismissAlert(weakAlert, finish);
        }]];
        return alert;
    } InWindow:window];
}

+ (BOOL)confirm:(NSString*)message InWindow:(UIWindow*)window {
    __block BOOL result = NO;

    [self present:^UIViewController*(dispatch_block_t finish) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:Localized(@"提示") message:message preferredStyle:UIAlertControllerStyleAlert];
        __weak UIAlertController* weakAlert = alert;

        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            result = YES;
            H5GGDismissAlert(weakAlert, finish);
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"取消") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            result = NO;
            H5GGDismissAlert(weakAlert, finish);
        }]];

        return alert;
    } InWindow:window];

    return result;
}

+ (NSString*)prompt:(NSString*)text defaultText:(NSString*)defaultText InWindow:(UIWindow*)window {
    __block NSString* result;

    [self present:^UIViewController*(dispatch_block_t finish) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil message:text preferredStyle:UIAlertControllerStyleAlert];
        __weak UIAlertController* weakAlert = alert;

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = defaultText;
        }];

        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            result = weakAlert.textFields.lastObject.text;
            H5GGDismissAlert(weakAlert, finish);
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
