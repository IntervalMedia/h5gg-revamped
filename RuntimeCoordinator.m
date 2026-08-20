#import "RuntimeCoordinator.h"

@interface H5GGRuntimeCoordinator ()
@property (nonatomic) H5GGRuntimeMode modes;
@property (nonatomic, strong, nullable) UIWindow* floatingWindow;
@property (nonatomic, strong, nullable) FloatButton* floatingButton;
@property (nonatomic, strong, nullable) FloatMenu* floatingMenu;
@property (nonatomic, strong, nullable) h5ggEngine* engine;
@property (nonatomic, strong, nullable) UIWindow* applicationWindow;
@property (nonatomic, getter=isInitialized) BOOL initialized;
@property (nonatomic, strong, nullable) NSTimer* readinessTimer;
@property (nonatomic, strong, nullable) NSTimer* globalViewTimer;
@end

@implementation H5GGRuntimeCoordinator

+ (instancetype)sharedCoordinator {
    static H5GGRuntimeCoordinator* coordinator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[self alloc] init];
    });
    return coordinator;
}

- (void)configureModes:(H5GGRuntimeMode)modes {
    if(self.initialized || self.readinessTimer) return;
    self.modes = modes;
}

- (BOOL)hasMode:(H5GGRuntimeMode)mode {
    return (self.modes & mode) == mode;
}

- (void)retainFloatingButton:(FloatButton*)button {
    self.floatingButton = button;
}

- (void)retainFloatingWindow:(UIWindow*)window
                        menu:(FloatMenu*)menu
                      engine:(h5ggEngine*)engine {
    self.floatingWindow = window;
    self.floatingMenu = menu;
    self.engine = engine;
}

- (void)retainApplicationWindow:(UIWindow*)window {
    self.applicationWindow = window;
}

- (void)startWhenReady:(BOOL (^)(void))readiness
               interval:(NSTimeInterval)interval
             initialize:(dispatch_block_t)initialize {
    NSParameterAssert(NSThread.isMainThread);
    if(self.initialized || self.readinessTimer || !readiness || !initialize) return;

    NSTimeInterval pollingInterval = MAX(0.01, interval);
    __weak typeof(self) weakSelf = self;
    void (^poll)(void) = ^{
        H5GGRuntimeCoordinator* strongSelf = weakSelf;
        if(!strongSelf || strongSelf.initialized || !readiness()) return;

        [strongSelf.readinessTimer invalidate];
        strongSelf.readinessTimer = nil;
        strongSelf.initialized = YES;
        initialize();
    };

    poll();
    if(self.initialized) return;
    self.readinessTimer = [NSTimer scheduledTimerWithTimeInterval:pollingInterval
                                                         repeats:YES
                                                           block:^(__unused NSTimer* timer) {
        poll();
    }];
}

- (void)startGlobalViewMonitorWithInterval:(NSTimeInterval)interval
                                      tick:(dispatch_block_t)tick {
    NSParameterAssert(NSThread.isMainThread);
    if(self.globalViewTimer || !tick) return;

    NSTimeInterval pollingInterval = MAX(0.01, interval);
    tick();
    self.globalViewTimer = [NSTimer scheduledTimerWithTimeInterval:pollingInterval
                                                           repeats:YES
                                                             block:^(__unused NSTimer* timer) {
        tick();
    }];
}

- (void)stopGlobalViewMonitor {
    [self.globalViewTimer invalidate];
    self.globalViewTimer = nil;
}

- (void)stop {
    [self.readinessTimer invalidate];
    self.readinessTimer = nil;
    [self stopGlobalViewMonitor];
    self.floatingWindow = nil;
    self.floatingButton = nil;
    self.floatingMenu = nil;
    self.engine = nil;
    self.applicationWindow = nil;
}

- (void)dealloc {
    [self stop];
}

@end

BOOL H5GGRuntimeHasMode(H5GGRuntimeMode mode) {
    return [H5GGRuntimeCoordinator.sharedCoordinator hasMode:mode];
}

FloatMenu* H5GGCurrentMenu(void) {
    return H5GGRuntimeCoordinator.sharedCoordinator.floatingMenu;
}
