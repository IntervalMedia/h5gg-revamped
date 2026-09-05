#import "ContextHostManager.h"

SBApplication *applicationForID(NSString *applicationID) {
    id controller = [objc_getClass("SBApplicationController") sharedInstance];

    if ([controller respondsToSelector:@selector(applicationWithDisplayIdentifier:)]) {
        return [controller applicationWithDisplayIdentifier:applicationID];
    } else {
        return [controller applicationWithBundleIdentifier:applicationID];
    }
}

@implementation ContextHostManager

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static ContextHostManager *sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}

- (nullable UIView *)hostViewForBundleID:(NSString *)bundleId {
    return [self hostViewForApplicationWithBundleID:bundleId];
}

- (void)stopHostingView:(UIView *)view forBundleId:(NSString *)bundleId {
    [self stopHostingForBundleID:bundleId];
}

- (BOOL)isHostViewHosting:(nullable UIView *)hostView {
    if (@available(iOS 13, *)) {
        return hostView != nil;
    } else {
        return hostView && hostView.subviews.count >= 1
            && [(FBWindowContextHostView *)hostView.subviews[0] isHosting];
    }
}

#pragma mark - Pre 13 implementation

- (UIView *)hostViewForApplication:(id)sbapplication {
    NSString *bundleID = [(SBApplication *)sbapplication bundleIdentifier];
    [self launchSuspendedApplicationWithBundleID:bundleID];
    [self enableBackgroundingForApplication:sbapplication];

    id contextManager = [self contextManagerForApplication:sbapplication];
    [contextManager enableHostingForRequester:bundleID orderFront:YES];

    return [contextManager hostViewForRequester:bundleID enableAndOrderFront:YES];
}

- (UIView *)hostViewForApplicationWithBundleID:(NSString *)bundleID {
    SBApplication *appToHost = applicationForID(bundleID);
    return [self hostViewForApplication:appToHost];
}

- (void)disableBackgroundingForApplication:(id)sbapplication {
    FBSMutableSceneSettings *sceneSettings = [self sceneSettingsForApplication:sbapplication];
    sceneSettings.backgrounded = YES;

    if (IS_IOS11orHIGHER) {
        [[self FBSceneForApplication:sbapplication] updateSettings:sceneSettings withTransitionContext:nil];
    } else {
        [[self FBSceneForApplication:sbapplication] _applyMutableSettings:sceneSettings withTransitionContext:nil completion:nil];
    }
}

- (void)enableBackgroundingForApplication:(id)sbapplication {
    FBSMutableSceneSettings *sceneSettings = [self sceneSettingsForApplication:sbapplication];
    sceneSettings.backgrounded = NO;

    if (IS_IOS11orHIGHER) {
        [[self FBSceneForApplication:sbapplication] updateSettings:sceneSettings withTransitionContext:nil];
    } else {
        [[self FBSceneForApplication:sbapplication] _applyMutableSettings:sceneSettings withTransitionContext:nil completion:nil];
    }
}

- (FBScene *)FBSceneForApplication:(id)sbapplication {
    return [(SBApplication *)sbapplication mainScene];
}

- (FBWindowContextHostManager *)contextManagerForApplication:(id)sbapplication {
    return [[self FBSceneForApplication:sbapplication] hostManager];
}

- (FBSMutableSceneSettings *)sceneSettingsForApplication:(id)sbapplication {
    return [[[self FBSceneForApplication:sbapplication] mutableSettings] mutableCopy];
}

- (void)stopHostingForBundleID:(NSString *)bundleID {
    SBApplication *appToHost = [[NSClassFromString(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleID];
    [self disableBackgroundingForApplication:appToHost];
    FBWindowContextHostManager *contextManager = [self contextManagerForApplication:appToHost];
    [contextManager disableHostingForRequester:bundleID];
}

- (void)launchSuspendedApplicationWithBundleID:(NSString *)bundleID {
    [UIApplication.sharedApplication launchApplicationWithIdentifier:bundleID suspended:YES];
}

@end

