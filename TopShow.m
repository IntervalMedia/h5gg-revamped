#import "TopShow.h"
#import "Localized.h"
#import "globalview/globalview.h"

extern GVData* PGVSharedData;

@implementation TopShow

- (BOOL)shouldAutorotate {
    BOOL should = YES;
    return should;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIInterfaceOrientationMask mask = (UIInterfaceOrientationMask)(1 << UIApplication.sharedApplication.statusBarOrientation);
    uint64_t mask2 = 1 << UIApplication.sharedApplication.statusBarOrientation;
    mask = self.followOrientationMask | mask2;
    return mask;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    UIInterfaceOrientation preferred = UIApplication.sharedApplication.statusBarOrientation;
    return preferred;
}

+ (void)present:(UIViewController* (^)(TopShow* controller))alert {
    void (^submit)() = ^() {
        TopShow* rootVC = [TopShow new];
        rootVC.followOrientationMask = UIApplication.sharedApplication.keyWindow.rootViewController.supportedInterfaceOrientations;

        rootVC.alertWindow = makeWindow(NSStringFromClass(UIWindow.class));
        rootVC.alertWindow.rootViewController = rootVC;
        rootVC.alertWindow.windowLevel = UIWindowLevelAlert + 1;
        [rootVC.alertWindow setHidden:NO];

        dispatch_async(dispatch_get_main_queue(), ^{
            [rootVC presentViewController:alert(rootVC) animated:YES completion:nil];
        });
    };

    if([NSThread isMainThread])
        submit();
    else
        dispatch_async(dispatch_get_main_queue(), submit);
}

- (void)dismiss {
    NSLog(@"TopShow dismiss on %d", [NSThread isMainThread]);
    [self.alertWindow setHidden:YES];
    self.alertWindow = nil;
}

+ (void)alert:(NSString*)title message:(NSString*)message {
    [self present:^(TopShow* controller) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:Localized(@"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [controller dismiss];
        }]];
        return alert;
    }];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"documentPickerWasCancelled=%@", controller);
    self.pickedfile = nil;
    if(self.pickedfile_notify) self.pickedfile_notify();
    [self dismiss];
}

- (void)_documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    NSLog(@"didPickDocumentAtURL %@", url);
    if(!url) {
        self.pickedfile = nil;
        if(self.pickedfile_notify) self.pickedfile_notify();
        [self dismiss];
        return;
    }
    BOOL canAccessingResource = [url startAccessingSecurityScopedResource];
    NSLog(@"canAccessingResource=%d", canAccessingResource);
    [self dismiss];
    self.pickedfile = [url path];
    self.pickedfile_notify();
    if(canAccessingResource) [url stopAccessingSecurityScopedResource];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *>*)urls {
    NSLog(@"didPickDocumentAtURLs %@", urls);
    [self _documentPicker:controller didPickDocumentAtURL:urls.firstObject];
}

+ (void)filePicker:(NSArray<NSString*>*)types callback:(void(^)(NSString*))callback {
    [self present:^(TopShow* controller) {
        __weak TopShow* weakPicker = controller;
        __block BOOL settled = NO;

        controller.pickedfile_notify = ^{
            if(settled) return;
            settled = YES;
            __strong TopShow* strongPicker = weakPicker;
            if(strongPicker) callback(strongPicker.pickedfile);
        };

        UIDocumentPickerViewController* documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
        NSLog(@"modalPresentationStyle=%ld", (long)documentPicker.modalPresentationStyle);
        documentPicker.delegate = weakPicker;
        return documentPicker;
    }];
}

@end
