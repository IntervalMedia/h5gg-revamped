#ifndef H5GG_RUNTIME_COORDINATOR_H
#define H5GG_RUNTIME_COORDINATOR_H

#import <Foundation/Foundation.h>

@class UIWindow;
@class FloatButton;
@class FloatMenu;
@class h5ggEngine;

typedef NS_OPTIONS(NSUInteger, H5GGRuntimeMode) {
    H5GGRuntimeModeNone = 0,
    H5GGRuntimeModeDylib = 1 << 0,
    H5GGRuntimeModeTestApp = 1 << 1,
    H5GGRuntimeModeCommonApp = 1 << 2,
    H5GGRuntimeModeSystemApp = 1 << 3,
    H5GGRuntimeModeStandalone = 1 << 4
};

NS_ASSUME_NONNULL_BEGIN

@interface H5GGRuntimeCoordinator : NSObject

@property (nonatomic, readonly) H5GGRuntimeMode modes;
@property (nonatomic, strong, readonly, nullable) UIWindow* floatingWindow;
@property (nonatomic, strong, readonly, nullable) FloatButton* floatingButton;
@property (nonatomic, strong, readonly, nullable) FloatMenu* floatingMenu;
@property (nonatomic, strong, readonly, nullable) h5ggEngine* engine;
@property (nonatomic, strong, readonly, nullable) UIWindow* applicationWindow;
@property (nonatomic, readonly, getter=isInitialized) BOOL initialized;

+ (instancetype)sharedCoordinator;

- (void)configureModes:(H5GGRuntimeMode)modes;
- (BOOL)hasMode:(H5GGRuntimeMode)mode;

- (void)retainFloatingButton:(nullable FloatButton*)button;
- (void)retainFloatingWindow:(nullable UIWindow*)window
                        menu:(nullable FloatMenu*)menu
                      engine:(nullable h5ggEngine*)engine;
- (void)retainApplicationWindow:(nullable UIWindow*)window;

- (void)startWhenReady:(BOOL (^)(void))readiness
               interval:(NSTimeInterval)interval
             initialize:(dispatch_block_t)initialize;
- (void)startGlobalViewMonitorWithInterval:(NSTimeInterval)interval
                                      tick:(dispatch_block_t)tick;
- (void)stopGlobalViewMonitor;
- (void)stop;

@end

#ifdef __cplusplus
extern "C" {
#endif

BOOL H5GGRuntimeHasMode(H5GGRuntimeMode mode);
FloatMenu* _Nullable H5GGCurrentMenu(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END

#endif /* H5GG_RUNTIME_COORDINATOR_H */
