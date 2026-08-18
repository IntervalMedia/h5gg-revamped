#import "FloatMenu.h"
#import "TopShow.h"
#import "ModalShow.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import "Localized.h"
#import "version.h"
#import "globalview/globalview.h"
#include "BridgeMethods.h"
#define INCBIN_SILENCE_BITCODE_WARNING
#include "incbin.h"

INCTXT(INITIAL_JS, "initial.js");

extern GVData* PGVSharedData;

#pragma mark - FloatMenu implementation

@interface FloatMenu () <WKScriptMessageHandler>
@property (nonatomic, strong) NSMutableDictionary<NSString*, id>* actions;
@end

#pragma mark - FloatMenu implementation

@implementation FloatMenu

- (instancetype)initWithFrame:(CGRect)frame {
    WKUserContentController *userController = [[WKUserContentController alloc] init];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userController;

    self = [super initWithFrame:frame configuration:config];
    if (self) {
        NSLog(@"init FloatMenu=%@", self);

        float version = [UIDevice currentDevice].systemVersion.floatValue;
        self.usingCustomDialog = version > 13.0 && version < 13.4;

        self.touchableAll = YES;
        self.actions = [[NSMutableDictionary alloc] init];

        [userController addScriptMessageHandler:self name:@"h5gg"];

        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;

        self.navigationDelegate = self;
        self.UIDelegate = self;

        self.scrollView.bounces = NO;
        self.scrollView.scrollEnabled = NO;
        [self.scrollView setShowsVerticalScrollIndicator:NO];
        [self.scrollView setShowsHorizontalScrollIndicator:NO];

        __weak __typeof(self) weakSelf = self;
        self.frontTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer* t) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf.superview bringSubviewToFront:strongSelf];
        }];

        self.dragableRect = frame;

        UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMe:)];
        [self addGestureRecognizer:drag];

        [self _injectMainBridge];
        [self _injectInitialJS];
    }
    return self;
}

- (void)dealloc {
    [self.configuration.userContentController removeScriptMessageHandlerForName:@"h5gg"];
}

#pragma mark - JS Bridge injection

static NSString* _bridgeSource() {
    static NSString *source = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        size_t methodCount = 0;
        const H5GGBridgeMethod* methods = H5GGBridgeMethods(methodCount);
        NSMutableArray<NSString*>* methodNames = [NSMutableArray arrayWithCapacity:methodCount];
        for(size_t index = 0; index < methodCount; index++) {
            [methodNames addObject:[NSString stringWithFormat:@"'%s'", methods[index].name]];
        }
        NSString* methodsSource = [methodNames componentsJoinedByString:@","];

        source = [NSString stringWithFormat:
        @"(function(){"
        "if(window.__h5ggPM)return;"
        "window.__h5ggPM=true;"
        "var _id=0,_cb={};"
        "window.__h5gg_onResult=function(i,e,r){"
        "var c=_cb[i];if(c){delete _cb[i];if(e)c[1](e);else c[0](r);}"
        "};"
        "window.__h5gg_native=function(m,a){"
        "return new Promise(function(res,rej){"
        "var i=++_id;_cb[i]=[res,rej];"
        "window.webkit.messageHandlers.h5gg.postMessage({callId:i,method:m,args:a});"
        "});"
        "};"
        "var methods=[%@];"
        "window.h5gg={};"
        "methods.forEach(function(m){"
        "Object.defineProperty(window.h5gg,m,{"
        "configurable:true,writable:true,"
        "value:function(){return window.__h5gg_native(m,Array.prototype.slice.call(arguments));}"
        "});"
        "});"
        "})();", methodsSource];
    });
    return source;
}

- (void)_injectMainBridge {
    WKUserScript *script = [[WKUserScript alloc] initWithSource:_bridgeSource()
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:YES];
    [self.configuration.userContentController addUserScript:script];
}

- (void)_injectInitialJS {
    NSString *initialJS = [NSString stringWithUTF8String:gINITIAL_JSData];
    if(initialJS && initialJS.length > 0) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:initialJS
                                                       injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                    forMainFrameOnly:YES];
        [self.configuration.userContentController addUserScript:script];
    }
}

#pragma mark - Touch / Hit testing

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return [super hitTest:point withEvent:event];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if(self.touchableAll || CGRectContainsPoint(self.touchableRect, point))
        return [super pointInside:point withEvent:event];
    return NO;
}

#pragma mark - Drag

- (void)setDragRect:(CGRect)rect {
    self.dragableRect = rect;
}

- (void)dragMe:(UIPanGestureRecognizer *)sender {
    CGPoint locationPoint = [sender locationInView:sender.view];

    if(sender.state == UIGestureRecognizerStateBegan) {
        self.startLocation = locationPoint;
    }

    if(sender.state == UIGestureRecognizerStateChanged) {
        if(!CGRectContainsPoint(self.dragableRect, self.startLocation))
            return;

        float dx = locationPoint.x - self.startLocation.x;
        float dy = locationPoint.y - self.startLocation.y;

        CGPoint newcenter = CGPointMake(self.center.x + dx, self.center.y + dy);
        float halfy = CGRectGetMidY(self.bounds);
        newcenter.y = MAX(halfy, newcenter.y);

        self.center = newcenter;
        PGVSharedData->floatMenuRect = self.frame;
    }
}

#pragma mark - Public API

- (void)setLocation:(CGPoint*)point {
    if(point) self.frame = CGRectMake(point->x, point->y, self.frame.size.width, self.frame.size.height);
}

- (void)setAction:(NSString*)name callback:(id)block {
    if(!name) return;

    self.actions[name] = block;

    // The h5gg engine is stored as an action but accessed via method dispatch, not a JS function wrapper
    if([name isEqualToString:@"h5gg"]) return;

    WKUserContentController *uc = self.configuration.userContentController;

    NSString *js = [NSString stringWithFormat:
        @"(function(){if(typeof window.%@=='function')return;window.%@=function(){return window.__h5gg_native('%@',Array.prototype.slice.call(arguments));};})()",
        name, name, name];
    WKUserScript *us = [[WKUserScript alloc] initWithSource:js
                                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                           forMainFrameOnly:YES];
    [uc addUserScript:us];

    [self evaluateJavaScript:js completionHandler:nil];
}

- (NSString*)evalJS:(NSString*)code {
    if(!code) return nil;
    __block NSString *result = nil;
    __block BOOL done = NO;
    [self evaluateJavaScript:code completionHandler:^(id value, NSError *error) {
        if(error) NSLog(@"evalJS error: %@", error);
        if([value isKindOfClass:[NSString class]])
            result = value;
        else if(value)
            result = [value description];
        done = YES;
    }];
    while(!done) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    return result;
}

- (NSString*)getValueByName:(NSString*)name {
    return [self evalJS:name];
}

#pragma mark - Dialogs (native-side, used by Engine)

- (void)alert:(NSString*)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.superview sendSubviewToBack:self];
    });
    [ModalShow alert:@"H5GG" message:message InWindow:self.window];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.superview bringSubviewToFront:self];
    });
}

- (BOOL)confirm:(NSString*)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.superview sendSubviewToBack:self];
    });
    BOOL result = [ModalShow confirm:message InWindow:self.window];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.superview bringSubviewToFront:self];
    });
    return result;
}

- (NSString*)prompt:(NSString*)text defaultText:(NSString*)defaultText {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.superview sendSubviewToBack:self];
    });
    NSString* result = [ModalShow prompt:text defaultText:defaultText InWindow:self.window];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.superview bringSubviewToFront:self];
    });
    return result;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    NSLog(@"webView didStartProvisionalNavigation=%@", webView);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"webView didFinishNavigation=%@", webView);
    [self _onBridgeReady];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"webView %@ didFailNavigation %@", webView, error);
    NSString *scheme = [[error.userInfo[NSURLErrorFailingURLErrorKey] scheme] lowercaseString];
    if([scheme isEqualToString:@"file"] || [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        [TopShow alert:Localized(@"H5加载失败") message:[NSString stringWithFormat:@"%@", error]];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"webView %@ didFailProvisionalNavigation %@", webView, error);
}

#pragma mark - WKUIDelegate (standard JS dialogs)

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    [self alert:message];
    completionHandler();
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler {
    BOOL result = [self confirm:message];
    completionHandler(result);
}

#pragma mark - Bridge ready logic (replaces old ts_didCreateJavaScriptContext)

- (void)_onBridgeReady {
    NSString *reloadStr = [self evalJS:@"window.h5gg_mainframe_reload||false"];
    BOOL reload = [reloadStr isEqualToString:@"true"];
    if(!reload) {
        [self evalJS:@"window.h5gg_mainframe_reload=true"];

        self.touchableAll = YES;
        self.touchableRect = CGRectZero;

        PGVSharedData->touchableAll = YES;
        PGVSharedData->touchableRect = CGRectZero;

        if(self.reloadAction) self.reloadAction();
    }

    [self evalJS:[NSString stringWithFormat:@"window.h5gg_internel_version=%f;", H5GG_VERSION]];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    NSDictionary *body = (NSDictionary*)message.body;
    if(![body isKindOfClass:[NSDictionary class]]) return;

    NSNumber *callId = body[@"callId"];
    NSString *methodName = body[@"method"];
    NSArray *args = body[@"args"];
    if(![callId isKindOfClass:NSNumber.class]) return;
    if(![methodName isKindOfClass:NSString.class] || ![args isKindOfClass:NSArray.class]) {
        [self resolveCallId:callId result:nil error:@"Invalid bridge message"];
        return;
    }

    self.pendingCallId = callId;
    self.hasPendingCallback = NO;
    NSString* dispatchError = nil;
    id result = nil;
    @try {
        result = [self _dispatchMethod:methodName args:args error:&dispatchError];
    } @catch(NSException* exception) {
        dispatchError = [NSString stringWithFormat:@"Native call failed: %@", exception.reason ?: exception.name];
    }

    if(self.hasPendingCallback) {
        self.pendingCallId = nil;
        return;
    }

    self.pendingCallId = nil;
    [self resolveCallId:callId result:result error:dispatchError];
}

- (id)_dispatchMethod:(NSString*)methodName args:(NSArray*)args error:(NSString**)error {
    id action = self.actions[methodName];
    if(action && [action isKindOfClass:NSClassFromString(@"NSBlock")]) {
        NSMethodSignature *signature = [action methodSignatureForSelector:@selector(invoke)];
        NSUInteger parameterCount = signature.numberOfArguments > 2 ? signature.numberOfArguments - 2 : 0;
        if(parameterCount != args.count) {
            if(error) *error = [NSString stringWithFormat:@"Invalid argument count for %@", methodName];
            return nil;
        }
        return [self _invokeBlock:action withArgs:args];
    }

    const H5GGBridgeMethod* method = H5GGBridgeMethodNamed(methodName.UTF8String);
    if(!method) {
        if(error) *error = [NSString stringWithFormat:@"Unknown bridge method: %@", methodName];
        return nil;
    }
    if(!method->acceptsArgumentCount(args.count)) {
        if(error) *error = [NSString stringWithFormat:@"Invalid argument count for %@", methodName];
        return nil;
    }

    id engine = self.actions[@"h5gg"];
    if(engine) {
        return [self _invokeMethod:method onObject:engine withArgs:args error:error];
    }
    if(error) *error = @"H5GG engine is unavailable";
    return nil;
}

- (void)resolveCallId:(NSNumber*)callId result:(id)result error:(NSString*)error {
    if(!callId) return;

    NSError* serializationError = nil;
    NSString* errorJSON = @"null";
    NSString* resultJSON = @"null";

    if(error) {
        NSData* data = [NSJSONSerialization dataWithJSONObject:error
                                                       options:NSJSONWritingFragmentsAllowed
                                                         error:&serializationError];
        if(data) errorJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    } else if(result && result != NSNull.null) {
        NSData* data = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingFragmentsAllowed
                                                         error:&serializationError];
        if(data) {
            resultJSON = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        } else {
            errorJSON = @"\"Native result is not JSON serializable\"";
        }
    }

    if(serializationError && [errorJSON isEqualToString:@"null"]) {
        errorJSON = @"\"Failed to serialize native result\"";
    }

    NSString *js = [NSString stringWithFormat:@"window.__h5gg_onResult(%@,%@,%@)",
                     callId, errorJSON, resultJSON];
    [self evaluateJavaScript:js completionHandler:nil];
}

- (NSNumber*)deferCurrentCall {
    if(!self.pendingCallId) return nil;
    self.hasPendingCallback = YES;
    return self.pendingCallId;
}

#pragma mark - Dynamic invocation helpers

- (id)_invokeBlock:(id)block withArgs:(NSArray*)args {
    if(!block) return nil;

    NSMethodSignature *sig = [block methodSignatureForSelector:@selector(invoke)];
    if(!sig) return nil;

    NSUInteger argCount = sig.numberOfArguments;
    NSUInteger paramCount = argCount > 2 ? argCount - 2 : 0;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:block];
    [inv setSelector:@selector(invoke)];

    for (NSUInteger i = 0; i < paramCount && i < args.count; i++) {
        const char *type = [sig getArgumentTypeAtIndex:i + 2];
        [self _setInvocationArgument:inv atIndex:i + 2 withType:type value:args[i]];
    }

    [inv invoke];
    return [self _extractReturnValue:inv];
}

- (id)_invokeMethod:(const H5GGBridgeMethod*)method
            onObject:(id)object
            withArgs:(NSArray*)args
               error:(NSString**)error {
    if(!object || !method) return nil;

    NSString *selName = [NSString stringWithUTF8String:method->selector];
    SEL selector = NSSelectorFromString(selName);
    if(![object respondsToSelector:selector]) {
        NSLog(@"h5gg bridge: no method %s (%@) on %@", method->name, selName, object);
        if(error) *error = [NSString stringWithFormat:@"Native method unavailable: %s", method->name];
        return nil;
    }

    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if(!sig) return nil;

    NSUInteger paramCount = sig.numberOfArguments > 2 ? sig.numberOfArguments - 2 : 0;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:object];
    [inv setSelector:selector];

    for (NSUInteger i = 0; i < paramCount; i++) {
        const char *type = [sig getArgumentTypeAtIndex:i + 2];
        id value = i < args.count ? args[i] : nil;
        [self _setInvocationArgument:inv atIndex:i + 2 withType:type value:value];
    }

    [inv invoke];
    return [self _extractReturnValue:inv];
}

- (void)_setInvocationArgument:(NSInvocation*)inv atIndex:(NSInteger)idx withType:(const char*)type value:(id)value {
    if(strcmp(type, @encode(id)) == 0) {
        if(value == NSNull.null) value = nil;
        [inv setArgument:&value atIndex:idx];
    } else if(strcmp(type, @encode(BOOL)) == 0) {
        BOOL v = value && value != NSNull.null ? [value boolValue] : NO;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(int)) == 0) {
        int v = value && value != NSNull.null ? [value intValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(unsigned int)) == 0) {
        unsigned int v = value && value != NSNull.null ? [value unsignedIntValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(float)) == 0) {
        float v = value && value != NSNull.null ? [value floatValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(double)) == 0) {
        double v = value && value != NSNull.null ? [value doubleValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(long)) == 0) {
        long v = value && value != NSNull.null ? [value longValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(long long)) == 0) {
        long long v = value && value != NSNull.null ? [value longLongValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(short)) == 0) {
        short v = value && value != NSNull.null ? [value shortValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(char)) == 0) {
        char v = value && value != NSNull.null ? (char)[value charValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(unsigned long)) == 0) {
        unsigned long v = value && value != NSNull.null ? [value unsignedLongValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(unsigned long long)) == 0) {
        unsigned long long v = value && value != NSNull.null ? [value unsignedLongLongValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else if(strcmp(type, @encode(CGFloat)) == 0) {
        CGFloat v = value && value != NSNull.null ? [value doubleValue] : 0;
        [inv setArgument:&v atIndex:idx];
    } else {
        [inv setArgument:&value atIndex:idx];
    }
}

- (id)_extractReturnValue:(NSInvocation*)inv {
    const char *type = inv.methodSignature.methodReturnType;

    if(strcmp(type, @encode(void)) == 0) return nil;

    if(strcmp(type, @encode(id)) == 0) {
        __unsafe_unretained id v = nil;
        [inv getReturnValue:&v];
        if(!v) return [NSNull null];
        if([v isKindOfClass:[JSValue class]])
            v = [(JSValue*)v toObject];
        return v ?: [NSNull null];
    }

    if(strcmp(type, @encode(BOOL)) == 0) { BOOL v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(int)) == 0) { int v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(unsigned int)) == 0) { unsigned int v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(float)) == 0) { float v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(double)) == 0) { double v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(long)) == 0) { long v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(long long)) == 0) { long long v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(short)) == 0) { short v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(char)) == 0) { char v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(unsigned long)) == 0) { unsigned long v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(unsigned long long)) == 0) { unsigned long long v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(unsigned short)) == 0) { unsigned short v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(unsigned char)) == 0) { unsigned char v = 0; [inv getReturnValue:&v]; return @(v); }
    if(strcmp(type, @encode(CGFloat)) == 0) { CGFloat v = 0; [inv getReturnValue:&v]; return @(v); }

    return nil;
}

@end
