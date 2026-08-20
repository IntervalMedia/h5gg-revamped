#import "../RuntimeCoordinator.h"

#import <Foundation/Foundation.h>

static void runLoopFor(NSTimeInterval duration) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:duration]];
}

int main(void) {
    @autoreleasepool {
        H5GGRuntimeCoordinator* coordinator = [[H5GGRuntimeCoordinator alloc] init];
        [coordinator configureModes:H5GGRuntimeModeDylib |
                                    H5GGRuntimeModeStandalone];
        NSCAssert([coordinator hasMode:H5GGRuntimeModeDylib], @"dylib mode missing");
        NSCAssert([coordinator hasMode:H5GGRuntimeModeStandalone], @"standalone mode missing");
        NSCAssert(![coordinator hasMode:H5GGRuntimeModeSystemApp], @"unexpected system mode");

        __block BOOL ready = NO;
        __block NSUInteger initializationCount = 0;
        [coordinator startWhenReady:^BOOL {
            return ready;
        } interval:0.01 initialize:^{
            initializationCount++;
        }];
        runLoopFor(0.03);
        NSCAssert(initializationCount == 0, @"initialized before readiness");
        ready = YES;
        runLoopFor(0.03);
        NSCAssert(initializationCount == 1, @"initializer did not run exactly once");
        NSCAssert(coordinator.isInitialized, @"coordinator did not record initialization");

        [coordinator startWhenReady:^BOOL {
            return YES;
        } interval:0.01 initialize:^{
            initializationCount++;
        }];
        NSCAssert(initializationCount == 1, @"second bootstrap was not rejected");

        __block NSUInteger monitorTicks = 0;
        [coordinator startGlobalViewMonitorWithInterval:0.01 tick:^{
            monitorTicks++;
        }];
        runLoopFor(0.03);
        NSCAssert(monitorTicks >= 2, @"monitor did not tick");
        [coordinator stopGlobalViewMonitor];
        NSUInteger stoppedAt = monitorTicks;
        runLoopFor(0.03);
        NSCAssert(monitorTicks == stoppedAt, @"monitor continued after stop");

        NSObject* retained = [[NSObject alloc] init];
        [coordinator retainFloatingButton:(id)retained];
        NSCAssert((id)coordinator.floatingButton == retained, @"resource was not retained");
        [coordinator stop];
        NSCAssert(coordinator.floatingButton == nil, @"stop did not release resources");
    }
    return 0;
}
