#import "FloatButton.h"
#import <ImageIO/ImageIO.h>

@implementation FloatButton

static UIWindow * _Nullable GVForegroundWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) return window;
            }
            if (windowScene.windows.count > 0) return windowScene.windows.firstObject;
        }
    }
    return nil;
}

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 25, 50, 50)];
    if (self) {
        self.clipsToBounds = YES;
        self.layer.cornerRadius = self.frame.size.width / 2;

        self.alpha = 0.8;
        self.layer.zPosition = MAXFLOAT;
        self.backgroundColor = [UIColor redColor];

        self.userInteractionEnabled = YES;

        self.keepFront = YES;
        self.keepWindow = NO;

        __weak __typeof(self) weakSelf = self;
        self.frontTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer* t) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if(!strongSelf || strongSelf.hidden) return;

            if(strongSelf.keepFront) [strongSelf.superview bringSubviewToFront:strongSelf];

            if(!strongSelf.keepWindow) {
                UIWindow *window = GVForegroundWindow();
                if(strongSelf.superview != window) [window addSubview:strongSelf];
            }

            CGRect newFrame = strongSelf.superview.frame;
            static CGRect lastFrame = {0};
            if(!CGRectEqualToRect(lastFrame, newFrame)) {
                float newX = newFrame.size.width * strongSelf.frame.origin.x / lastFrame.size.width;
                float newY = newFrame.size.height * strongSelf.frame.origin.y / lastFrame.size.height;

                if(newX < 0) newX = 0;
                if((newX + strongSelf.frame.size.width) > newFrame.size.width)
                    newX = newFrame.size.width - strongSelf.frame.size.width;

                if(newY < 0) newY = 0;
                if((newY + strongSelf.frame.size.height) > newFrame.size.height)
                    newY = newFrame.size.height - strongSelf.frame.size.height;

                strongSelf.frame = CGRectMake(newX, newY, strongSelf.frame.size.width, strongSelf.frame.size.height);

                lastFrame = newFrame;
            }
        }];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapMe)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
    CGPoint pt = [[touches anyObject] locationInView:self];
    self.startLocation = pt;
    [[self superview] bringSubviewToFront:self];
}

- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
    CGPoint pt = [[touches anyObject] locationInView:self];
    float dx = pt.x - self.startLocation.x;
    float dy = pt.y - self.startLocation.y;
    CGPoint newcenter = CGPointMake(self.center.x + dx, self.center.y + dy);

    float halfx = CGRectGetMidX(self.bounds);
    newcenter.x = MAX(halfx, newcenter.x);
    newcenter.x = MIN(self.superview.bounds.size.width - halfx, newcenter.x);

    float halfy = CGRectGetMidY(self.bounds);
    newcenter.y = MAX(halfy, newcenter.y);
    newcenter.y = MIN(self.superview.bounds.size.height - halfy, newcenter.y);

    self.center = newcenter;
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
}

- (void)tapMe {
    NSLog(@"click FloatButton!");
    if(self.actionBlock) self.actionBlock();
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

- (void)setIcon:(UIImage*)image {
    self.image = image;
    self.animationImages = nil;
    [self stopAnimating];
    if(image) self.backgroundColor = [UIColor clearColor];
}

- (void)setIconWithData:(NSData*)data {
    if(data.length < 3) return;

    char magic[4] = {0};
    [data getBytes:magic length:3];
    if(magic[0] == 'G' && magic[1] == 'I' && magic[2] == 'F') {
        [self _loadGifWithData:data];
    } else {
        UIImage* image = [UIImage imageWithData:data];
        if(!image) return;
        [self setIcon:image];
    }
}

- (void)_loadGifWithData:(NSData*)data {
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if(!src) return;

    size_t count = CGImageSourceGetCount(src);
    if(count <= 1) {
        UIImage* image = [UIImage imageWithData:data];
        if(image) [self setIcon:image];
        CFRelease(src);
        return;
    }

    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval dur = 0;

    for(size_t i = 0; i < count; i++) {
        CGImageRef cg = CGImageSourceCreateImageAtIndex(src, i, NULL);
        if(cg) { [frames addObject:[UIImage imageWithCGImage:cg]]; CGImageRelease(cg); }

        CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
        if(props) {
            CFDictionaryRef gif = CFDictionaryGetValue(props, kCGImagePropertyGIFDictionary);
            if(gif) {
                NSNumber *d = (__bridge NSNumber*)CFDictionaryGetValue(gif, kCGImagePropertyGIFDelayTime);
                if(d) dur += d.doubleValue;
            }
            CFRelease(props);
        }
    }
    CFRelease(src);

    if(frames.count == 0) return;
    self.backgroundColor = [UIColor clearColor];
    self.animationImages = frames;
    self.animationDuration = dur > 0 ? dur : 1.0;
    self.animationRepeatCount = 0;
    self.image = frames.firstObject;
    [self startAnimating];
}

- (void)setLocation:(CGPoint*)point {
    if(point) self.frame = CGRectMake(point->x, point->y, self.frame.size.width, self.frame.size.height);
}

@end
