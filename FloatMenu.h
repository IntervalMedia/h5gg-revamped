#ifndef FloatMenu_h
#define FloatMenu_h

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FloatMenu : WKWebView <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong, nullable) NSTimer* frontTimer;
@property (nonatomic) BOOL touchableAll;
@property (nonatomic) CGRect touchableRect;
@property (nonatomic) CGRect dragableRect;
@property (nonatomic) CGPoint startLocation;
@property (nonatomic) BOOL usingCustomDialog;
@property (nonatomic, copy, nullable) void(^reloadAction)(void);
@property (nullable, nonatomic, strong) NSString* rawHTML;
@property (nullable, nonatomic, strong) NSNumber* pendingCallId;
@property (nonatomic) BOOL hasPendingCallback;

- (void)setLocation:(CGPoint*)point;
- (void)setAction:(NSString*)name callback:(nullable id)block;
- (void)setDragRect:(CGRect)rect;
- (nullable NSString*)evalJS:(NSString*)code;
- (nullable NSString*)getValueByName:(NSString*)name;
- (void)alert:(NSString*)message;
- (BOOL)confirm:(NSString*)message;
- (nullable NSString*)prompt:(NSString*)text defaultText:(NSString*)defaultText;

@end

NS_ASSUME_NONNULL_END

#endif /* FloatMenu_h */
