#ifndef H5GG_FREEZER_CONTROLLER_H
#define H5GG_FREEZER_CONTROLLER_H

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

typedef pid_t (^H5GGFreezerTargetPIDProvider)(void);
typedef BOOL (^H5GGFreezerTargetAvailabilityProvider)(void);
typedef BOOL (^H5GGFreezerWriter)(uint64_t address,
                                  const void* bytes,
                                  int valueType);

@interface H5GGFreezerController : NSObject

-(instancetype)init NS_UNAVAILABLE;
-(instancetype)initWithTargetPIDProvider:(H5GGFreezerTargetPIDProvider)targetPIDProvider
              targetAvailabilityProvider:(H5GGFreezerTargetAvailabilityProvider)targetAvailabilityProvider
                                  writer:(H5GGFreezerWriter)writer;

-(BOOL)freezeAddress:(NSString*)address value:(NSString*)value type:(NSString*)type;
-(BOOL)unfreezeAddress:(NSString*)address;
-(NSArray<NSDictionary<NSString*,id>*>*)frozenValues;
-(void)clear;

@end

NS_ASSUME_NONNULL_END

#endif
