#import "FloatWindow.h"
#import "TopShow.h"
#import "globalview/globalview.h"

extern GVData* PGVSharedData;

@implementation AppWinController

- (instancetype)initWithBind:(UIViewController*)vc {
    self = [super init];
    if(self) {
        self.bindVC = vc;
    }
    return self;
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    NSLog(@"FloatWindow %@ %@", NSStringFromSelector(_cmd), NSStringFromSelector(aSelector));
    return self.bindVC;
}

- (BOOL)shouldAutorotate {
    if(!PGVSharedData->followCurrentOrientation)
        return self.bindVC.shouldAutorotate;
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if(!PGVSharedData->followCurrentOrientation)
        return self.bindVC.supportedInterfaceOrientations;
    return (UIInterfaceOrientationMask)(1 << PGVSharedData->curOrientation);
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if(!PGVSharedData->followCurrentOrientation)
        return self.bindVC.preferredInterfaceOrientationForPresentation;
    return (UIInterfaceOrientation)PGVSharedData->curOrientation;
}

@end

@implementation FloatController

- (instancetype)init {
    self = [super init];
    if(self) {
        self.followOrientationMask = UIApplication.sharedApplication.keyWindow.rootViewController.supportedInterfaceOrientations;
    }
    return self;
}

- (BOOL)shouldAutorotate {
    BOOL should;
    if(PGVSharedData->enable && PGVSharedData->viewHosted && PGVSharedData->followCurrentOrientation)
        should = YES;
    else
        should = YES;
    return should;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIInterfaceOrientationMask mask;
    if(PGVSharedData->enable && PGVSharedData->viewHosted && PGVSharedData->followCurrentOrientation)
        mask = (UIInterfaceOrientationMask)(1 << PGVSharedData->curOrientation);
    else {
        uint64_t mask2 = 1 << UIApplication.sharedApplication.statusBarOrientation;
        mask = self.followOrientationMask | mask2;
    }
    return mask;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    UIInterfaceOrientation preferred;
    if(PGVSharedData->enable && PGVSharedData->viewHosted && PGVSharedData->followCurrentOrientation)
        preferred = (UIInterfaceOrientation)PGVSharedData->curOrientation;
    else
        preferred = UIApplication.sharedApplication.statusBarOrientation;
    return preferred;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    NSLog(@"FloatWindow=resize=%f,%f : %@", size.width, size.height, self.view);
    if(self.onResizeCallback) self.onResizeCallback(size);
}

@end

@implementation FloatWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView* v = [super hitTest:point withEvent:event];
    return v;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    int count = (int)self.subviews.count;
    for (int i = count - 1; i >= 0; i--) {
        UIView *childV = self.subviews[i];
        CGPoint childP = [self convertPoint:point toView:childV];
        UIView *fitView = [childV hitTest:childP withEvent:event];
        if(fitView) {
            return YES;
        }
    }
    return NO;
}

- (void)setHidden:(BOOL)hidden {
    NSLog(@"FloatWindow setHidden=%d", hidden);
    if(hidden == NO) {
        ((FloatController*)self.rootViewController).followOrientationMask = UIApplication.sharedApplication.keyWindow.rootViewController.supportedInterfaceOrientations;
    }
    [super setHidden:hidden];
    if(hidden == NO) {
        UIView* superview = self.rootViewController.view;
        while(superview && ![superview isKindOfClass:UIWindow.class]) {
            [superview setHidden:YES];
            superview = superview.superview;
        }
    }
}

@end
