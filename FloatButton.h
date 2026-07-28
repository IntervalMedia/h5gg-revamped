#ifndef FloatButton_h
#define FloatButton_h

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FloatButton : UIImageView
@property (nonatomic) BOOL keepFront;
@property (nonatomic) BOOL keepWindow;
@property (nonatomic, strong, nullable) NSTimer* frontTimer;
@property (nonatomic) CGPoint startLocation;
@property (nonatomic, copy, nullable) void(^actionBlock)(void);

- (instancetype)init;
- (void)setIcon:(UIImage*)image;
- (void)setAction:(void(^)(void))block;
- (void)setLocation:(CGPoint*)point;

@end

NS_ASSUME_NONNULL_END

#endif /* FloatButton_h */
