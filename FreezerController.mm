#import "FreezerControllerInternal.h"

#include "MemoryValue.h"

static const NSTimeInterval H5GGFreezerInterval = 0.1;

@interface H5GGFrozenEntry : NSObject
@property (nonatomic, copy) NSString* address;
@property (nonatomic, copy) NSString* value;
@property (nonatomic, copy) NSString* type;
@property (nonatomic) uint64_t numericAddress;
@property (nonatomic) int valueType;
@property (nonatomic, copy) NSData* bytes;
@property (nonatomic) pid_t targetPID;
@property (nonatomic, copy) NSString* status;
@property (nonatomic) NSUInteger failures;
@property (nonatomic, copy, nullable) NSString* lastError;
@end

@implementation H5GGFrozenEntry
@end

@interface H5GGNSTimerScheduler : NSObject <H5GGFreezerScheduling>
@end

@implementation H5GGNSTimerScheduler

-(id)startRepeatingTimerWithInterval:(NSTimeInterval)interval
                              handler:(H5GGFreezerTimerHandler)handler {
    return [NSTimer scheduledTimerWithTimeInterval:interval
                                           repeats:YES
                                             block:^(__unused NSTimer* timer) {
        handler();
    }];
}

-(void)stopTimer:(id)timer {
    [(NSTimer*)timer invalidate];
}

@end

@interface H5GGFreezerController ()
@property (nonatomic, copy) H5GGFreezerTargetPIDProvider targetPIDProvider;
@property (nonatomic, copy) H5GGFreezerTargetAvailabilityProvider targetAvailabilityProvider;
@property (nonatomic, copy) H5GGFreezerWriter writer;
@property (nonatomic, strong) id<H5GGFreezerScheduling> scheduler;
@property (nonatomic, strong, nullable) id timer;
@property (nonatomic, strong) NSMutableDictionary<NSString*, H5GGFrozenEntry*>* entries;
-(void)stopTimer;
@end

@implementation H5GGFreezerController

-(instancetype)initWithTargetPIDProvider:(H5GGFreezerTargetPIDProvider)targetPIDProvider
              targetAvailabilityProvider:(H5GGFreezerTargetAvailabilityProvider)targetAvailabilityProvider
                                  writer:(H5GGFreezerWriter)writer {
    return [self initWithTargetPIDProvider:targetPIDProvider
                targetAvailabilityProvider:targetAvailabilityProvider
                                    writer:writer
                                 scheduler:[[H5GGNSTimerScheduler alloc] init]];
}

-(instancetype)initWithTargetPIDProvider:(H5GGFreezerTargetPIDProvider)targetPIDProvider
              targetAvailabilityProvider:(H5GGFreezerTargetAvailabilityProvider)targetAvailabilityProvider
                                  writer:(H5GGFreezerWriter)writer
                               scheduler:(id<H5GGFreezerScheduling>)scheduler {
    if(!targetPIDProvider || !targetAvailabilityProvider || !writer || !scheduler) return nil;
    if(self = [super init]) {
        _targetPIDProvider = [targetPIDProvider copy];
        _targetAvailabilityProvider = [targetAvailabilityProvider copy];
        _writer = [writer copy];
        _scheduler = scheduler;
        _entries = [NSMutableDictionary dictionary];
    }
    return self;
}

-(void)dealloc {
    [self clear];
}

-(BOOL)freezeAddress:(NSString*)address value:(NSString*)value type:(NSString*)type {
    if(!address || !value || !type || !self.targetAvailabilityProvider()) return NO;

    uint64_t numericAddress = 0;
    int valueType = JJTypeFromName(type.UTF8String);
    uint8_t parsedValue[8] = {};
    if(!valueType ||
       !JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10,
                       numericAddress) ||
       !numericAddress ||
       !JJParseValue(value.UTF8String, valueType, parsedValue)) {
        return NO;
    }

    pid_t targetPID = self.targetPIDProvider();
    if(targetPID <= 0) return NO;

    NSString* canonicalAddress = [NSString stringWithFormat:@"0x%llX", numericAddress];
    H5GGFrozenEntry* entry = [[H5GGFrozenEntry alloc] init];
    entry.address = canonicalAddress;
    entry.value = value;
    entry.type = type;
    entry.numericAddress = numericAddress;
    entry.valueType = valueType;
    entry.bytes = [NSData dataWithBytes:parsedValue length:JJ_Search_Type_Len[valueType]];
    entry.targetPID = targetPID;
    entry.status = @"active";
    entry.failures = 0;
    H5GGFrozenEntry* previousEntry = self.entries[canonicalAddress];
    self.entries[canonicalAddress] = entry;

    if(!self.timer) {
        __weak __typeof(self) weakSelf = self;
        self.timer = [self.scheduler startRepeatingTimerWithInterval:H5GGFreezerInterval
                                                              handler:^{
            [weakSelf performTick];
        }];
    }
    if(self.timer) return YES;
    if(previousEntry) self.entries[canonicalAddress] = previousEntry;
    else [self.entries removeObjectForKey:canonicalAddress];
    return NO;
}

-(BOOL)unfreezeAddress:(NSString*)address {
    if(!address) return NO;
    uint64_t numericAddress = 0;
    if(!JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10,
                       numericAddress)) {
        return NO;
    }

    NSString* canonicalAddress = [NSString stringWithFormat:@"0x%llX", numericAddress];
    if(!self.entries[canonicalAddress]) return NO;
    [self.entries removeObjectForKey:canonicalAddress];
    if(self.entries.count == 0) [self stopTimer];
    return YES;
}

-(NSArray<NSDictionary<NSString*,id>*>*)frozenValues {
    NSArray<H5GGFrozenEntry*>* sortedEntries = [[self.entries allValues]
        sortedArrayUsingComparator:^NSComparisonResult(H5GGFrozenEntry* left,
                                                       H5GGFrozenEntry* right) {
        if(left.numericAddress < right.numericAddress) return NSOrderedAscending;
        if(left.numericAddress > right.numericAddress) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSMutableArray<NSDictionary<NSString*,id>*>* values =
        [NSMutableArray arrayWithCapacity:sortedEntries.count];
    for(H5GGFrozenEntry* entry in sortedEntries) {
        [values addObject:@{
            @"address": entry.address,
            @"value": entry.value,
            @"type": entry.type,
            @"targetPid": @(entry.targetPID),
            @"status": entry.status,
            @"failures": @(entry.failures),
            @"lastError": entry.lastError ?: NSNull.null,
        }];
    }
    return values;
}

-(void)clear {
    [self.entries removeAllObjects];
    [self stopTimer];
}

-(void)performTick {
    BOOL targetAvailable = self.targetAvailabilityProvider();
    pid_t currentPID = self.targetPIDProvider();
    for(H5GGFrozenEntry* entry in [self.entries allValues]) {
        if(!targetAvailable || entry.targetPID != currentPID) {
            entry.status = @"target-unavailable";
            entry.lastError = @"Target process is no longer available";
            continue;
        }

        BOOL success = NO;
        NSString* exceptionReason = nil;
        @try {
            success = self.writer(entry.numericAddress, entry.bytes.bytes, entry.valueType);
        } @catch(NSException* exception) {
            exceptionReason = exception.reason;
        }
        if(success) {
            entry.status = @"active";
            entry.failures = 0;
            entry.lastError = nil;
        } else {
            entry.status = @"write-failed";
            entry.failures++;
            entry.lastError = exceptionReason ?: @"Memory write failed";
        }
    }
}

-(void)stopTimer {
    if(!self.timer) return;
    [self.scheduler stopTimer:self.timer];
    self.timer = nil;
}

@end
