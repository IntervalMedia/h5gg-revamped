#import "../FreezerControllerInternal.h"

#include "../MemoryValue.h"
#include <cstring>

@interface H5GGTestFreezerScheduler : NSObject <H5GGFreezerScheduling>
@property (nonatomic) NSUInteger startCount;
@property (nonatomic) NSUInteger stopCount;
@property (nonatomic, copy, nullable) H5GGFreezerTimerHandler handler;
-(void)fire;
@end

@implementation H5GGTestFreezerScheduler

-(id)startRepeatingTimerWithInterval:(NSTimeInterval)interval
                              handler:(H5GGFreezerTimerHandler)handler {
    NSCAssert(interval == 0.1, @"unexpected freezer interval");
    self.startCount++;
    self.handler = handler;
    return [[NSObject alloc] init];
}

-(void)stopTimer:(id)timer {
    NSCAssert(timer != nil, @"missing timer token");
    self.stopCount++;
    self.handler = nil;
}

-(void)fire {
    if(self.handler) self.handler();
}

@end

static NSDictionary<NSString*,id>* entryAtAddress(
    H5GGFreezerController* freezer,
    NSString* address) {
    for(NSDictionary<NSString*,id>* entry in freezer.frozenValues) {
        if([entry[@"address"] isEqualToString:address]) return entry;
    }
    return nil;
}

int main(void) {
    @autoreleasepool {
        __block pid_t targetPID = 123;
        __block BOOL targetAvailable = NO;
        __block BOOL writesSucceed = YES;
        __block NSUInteger writeCount = 0;
        NSMutableDictionary<NSNumber*, NSData*>* writtenBytes = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSNumber*, NSNumber*>* writtenTypes = [NSMutableDictionary dictionary];
        H5GGTestFreezerScheduler* scheduler = [[H5GGTestFreezerScheduler alloc] init];

        H5GGFreezerController* freezer = [[H5GGFreezerController alloc]
            initWithTargetPIDProvider:^pid_t {
                return targetPID;
            }
            targetAvailabilityProvider:^BOOL {
                return targetAvailable;
            }
            writer:^BOOL(uint64_t address, const void* bytes, int valueType) {
                writeCount++;
                size_t length = (size_t)JJ_Search_Type_Len[valueType];
                writtenBytes[@(address)] = [NSData dataWithBytes:bytes length:length];
                writtenTypes[@(address)] = @(valueType);
                return writesSucceed;
            }
            scheduler:scheduler];

        NSCAssert(![freezer freezeAddress:@"0x100" value:@"1" type:@"I32"],
                  @"accepted an unavailable target");
        NSCAssert(scheduler.startCount == 0, @"scheduled an invalid freeze");

        targetAvailable = YES;
        NSCAssert(![freezer freezeAddress:@"0" value:@"1" type:@"I32"],
                  @"accepted the null address");
        NSCAssert(![freezer freezeAddress:@"invalid" value:@"1" type:@"I32"],
                  @"accepted an invalid address");
        NSCAssert(![freezer freezeAddress:@"0x100" value:@"bad" type:@"I32"],
                  @"accepted an invalid value");
        NSCAssert(![freezer freezeAddress:@"0x100" value:@"1" type:@"bad"],
                  @"accepted an invalid type");

        NSCAssert([freezer freezeAddress:@"0x200" value:@"7" type:@"I32"],
                  @"failed to freeze a valid value");
        NSCAssert([freezer freezeAddress:@"16" value:@"255" type:@"U8"],
                  @"failed to freeze a decimal address");
        NSCAssert(scheduler.startCount == 1, @"started more than one timer");
        NSCAssert(freezer.frozenValues.count == 2, @"wrong entry count");
        NSCAssert([freezer.frozenValues[0][@"address"] isEqualToString:@"0x10"],
                  @"entries are not sorted by numeric address");
        NSCAssert([freezer.frozenValues[1][@"address"] isEqualToString:@"0x200"],
                  @"canonical address is wrong");

        NSCAssert([freezer freezeAddress:@"512" value:@"8" type:@"I32"],
                  @"failed to replace an entry");
        NSCAssert(freezer.frozenValues.count == 2, @"replacement duplicated an entry");
        NSCAssert(scheduler.startCount == 1, @"replacement restarted the timer");

        [scheduler fire];
        NSCAssert(writeCount == 2, @"tick did not write every entry");
        NSCAssert([writtenTypes[@0x200] intValue] == JJ_Search_Type_SInt,
                  @"wrong parsed write type");
        int32_t writtenI32 = 0;
        [writtenBytes[@0x200] getBytes:&writtenI32 length:sizeof(writtenI32)];
        NSCAssert(writtenI32 == 8, @"replacement value was not written");
        uint8_t writtenU8 = 0;
        [writtenBytes[@0x10] getBytes:&writtenU8 length:sizeof(writtenU8)];
        NSCAssert(writtenU8 == 255, @"unsigned value was not written");

        writesSucceed = NO;
        [scheduler fire];
        [scheduler fire];
        NSDictionary<NSString*,id>* failed = entryAtAddress(freezer, @"0x200");
        NSCAssert([failed[@"status"] isEqualToString:@"write-failed"],
                  @"write failure status missing");
        NSCAssert([failed[@"failures"] unsignedIntegerValue] == 2,
                  @"write failure count is wrong");
        NSCAssert([failed[@"lastError"] isEqualToString:@"Memory write failed"],
                  @"write error missing");

        writesSucceed = YES;
        [scheduler fire];
        NSDictionary<NSString*,id>* recovered = entryAtAddress(freezer, @"0x200");
        NSCAssert([recovered[@"status"] isEqualToString:@"active"],
                  @"successful write did not recover status");
        NSCAssert([recovered[@"failures"] unsignedIntegerValue] == 0,
                  @"successful write did not reset failures");
        NSCAssert(recovered[@"lastError"] == NSNull.null,
                  @"successful write retained an error");

        NSUInteger writesBeforeTargetChange = writeCount;
        targetPID = 456;
        [scheduler fire];
        NSDictionary<NSString*,id>* unavailable = entryAtAddress(freezer, @"0x200");
        NSCAssert([unavailable[@"status"] isEqualToString:@"target-unavailable"],
                  @"target mismatch was not detected");
        NSCAssert(writeCount == writesBeforeTargetChange,
                  @"wrote an entry belonging to another target");

        targetPID = 123;
        targetAvailable = NO;
        [scheduler fire];
        NSCAssert(writeCount == writesBeforeTargetChange,
                  @"wrote while the target was unavailable");
        targetAvailable = YES;

        NSCAssert([freezer unfreezeAddress:@"512"], @"decimal unfreeze failed");
        NSCAssert(scheduler.stopCount == 0, @"stopped with entries remaining");
        NSCAssert([freezer unfreezeAddress:@"0x10"], @"hex unfreeze failed");
        NSCAssert(scheduler.stopCount == 1, @"last removal did not stop timer");
        NSCAssert(![freezer unfreezeAddress:@"0x10"], @"removed a missing entry");

        NSCAssert([freezer freezeAddress:@"0x300" value:@"3" type:@"I16"],
                  @"failed to restart after becoming empty");
        NSCAssert(scheduler.startCount == 2, @"timer did not restart");
        [freezer clear];
        NSCAssert(freezer.frozenValues.count == 0, @"clear retained entries");
        NSCAssert(scheduler.stopCount == 2, @"clear did not stop timer");

        targetPID = 0;
        NSCAssert(![freezer freezeAddress:@"0x400" value:@"4" type:@"I32"],
                  @"accepted a target without a PID");
    }
    return 0;
}
