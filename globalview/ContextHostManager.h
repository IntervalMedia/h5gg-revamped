#import <Foundation/Foundation.h>
#import "ContextInterfaces.h"
#import "headers.h"
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

#define IS_IOS11orHIGHER ([[[UIDevice currentDevice] systemVersion] floatValue] >= 11.0)

SBApplication *applicationForID(NSString *applicationID);

@protocol ContextHostManagerExternalSceneDelegate <NSObject>
- (void)contextManager:(id)manager scene:(FBScene *)scene sceneStackDidChange:(UIView *)sceneStack;
- (void)contextManager:(id)manager scene:(FBScene *)scene externalSceneStackDidChange:(UIView *)sceneStack;
@end

@interface ContextHostManager : NSObject
@property (nonatomic, weak, nullable) id<ContextHostManagerExternalSceneDelegate> sceneDelegate;
+ (instancetype)sharedInstance;

- (nullable UIView *)hostViewForBundleID:(NSString *)bundleId;

- (void)stopHostingView:(UIView *)view forBundleId:(NSString *)bundleId;
- (BOOL)isHostViewHosting:(nullable UIView *)hostView;

@end

NS_ASSUME_NONNULL_END
