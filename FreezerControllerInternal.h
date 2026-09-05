#ifndef H5GG_FREEZER_CONTROLLER_INTERNAL_H
#define H5GG_FREEZER_CONTROLLER_INTERNAL_H

#import "FreezerController.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^H5GGFreezerTimerHandler)(void);

@protocol H5GGFreezerScheduling <NSObject>

-(id)startRepeatingTimerWithInterval:(NSTimeInterval)interval
                              handler:(H5GGFreezerTimerHandler)handler;
-(void)stopTimer:(id)timer;

@end

@interface H5GGFreezerController (Internal)

-(instancetype)initWithTargetPIDProvider:(H5GGFreezerTargetPIDProvider)targetPIDProvider
              targetAvailabilityProvider:(H5GGFreezerTargetAvailabilityProvider)targetAvailabilityProvider
                                  writer:(H5GGFreezerWriter)writer
                               scheduler:(id<H5GGFreezerScheduling>)scheduler;
-(void)performTick;

@end

NS_ASSUME_NONNULL_END

#endif
