#import "../DumpControllerInternal.h"

#import <Foundation/Foundation.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

static void H5GGTestAssert(BOOL condition, NSString* message) {
    if(condition) return;
    fprintf(stderr, "DumpController test failed: %s\n", message.UTF8String);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        char rootTemplate[] = "/tmp/h5gg-dump-controller.XXXXXX";
        char* createdRoot = mkdtemp(rootTemplate);
        H5GGTestAssert(createdRoot != nullptr, @"temporary root creation failed");
        NSString* root = [NSString stringWithUTF8String:createdRoot];

        NSMutableData* source = [NSMutableData dataWithLength:20];
        for(NSUInteger index = 0; index < source.length; index++) {
            ((uint8_t*)source.mutableBytes)[index] = (uint8_t)index;
        }
        __block BOOL targetAvailable = YES;
        __block BOOL readerFails = NO;
        __block NSUInteger targetCount = 0;
        __block NSUInteger releaseCount = 0;
        __block NSUInteger completionCount = 0;
        __block BOOL completionResult = NO;
        H5GGDumpTargetProvider targetProvider = ^H5GGDumpTargetLease* {
            targetCount++;
            if(!targetAvailable) return nil;
            return [[H5GGDumpTargetLease alloc]
                initWithReader:^size_t(void* output, uint64_t address, size_t length) {
                    if(readerFails || address < 0x1000 || address >= 0x1000 + source.length) {
                        return 0;
                    }
                    NSUInteger offset = (NSUInteger)(address - 0x1000);
                    size_t readable = std::min(length, (size_t)source.length - offset);
                    readable = std::min(readable, (size_t)3);
                    std::memcpy(output, (const uint8_t*)source.bytes + offset, readable);
                    return readable;
                }
                release:^{
                    releaseCount++;
                }];
        };
        H5GGDumpCompletionProvider completionProvider = ^H5GGDumpCompletion {
            return ^(BOOL success) {
                completionCount++;
                completionResult = success;
            };
        };
        H5GGDumpExecutor immediate = ^(dispatch_block_t work) {
            work();
        };
        H5GGDumpController* controller = [[H5GGDumpController alloc]
            initWithDocumentsPath:root
            targetProvider:targetProvider
            completionProvider:completionProvider
            workExecutor:immediate
            completionExecutor:immediate];

        H5GGTestAssert([controller.status[@"state"] isEqualToString:@"idle"],
                       @"initial status is not idle");
        H5GGTestAssert(![controller cancel], @"idle dump was cancelled");
        H5GGTestAssert(![controller startFrom:@"0" end:@"20" filename:@"bad.bin"],
                       @"null start was accepted");
        H5GGTestAssert(![controller startFrom:@"0x1010" end:@"0x1000" filename:@"bad.bin"],
                       @"inverted range was accepted");
        H5GGTestAssert(![controller startFrom:@"0x1000" end:@"0x1010" filename:@"../bad.bin"],
                       @"traversal filename was accepted");
        H5GGTestAssert(targetCount == 0, @"invalid request acquired a target");

        H5GGTestAssert([controller startFrom:@"0x1000" end:@"0x1014"
                                           filename:@"complete.bin"],
                       @"valid dump did not start");
        H5GGTestAssert([controller.status[@"state"] isEqualToString:@"completed"],
                       @"completed dump has wrong state");
        H5GGTestAssert([controller.status[@"written"] unsignedIntegerValue] == source.length,
                       @"completed dump has wrong byte count");
        H5GGTestAssert([controller.status[@"progress"] doubleValue] == 1.0,
                       @"completed dump has wrong progress");
        H5GGTestAssert(completionCount == 1 && completionResult,
                       @"successful completion did not settle once");
        H5GGTestAssert(releaseCount == 1, @"successful target lease was not released");
        NSString* completePath = [root stringByAppendingPathComponent:@"complete.bin"];
        H5GGTestAssert([[NSData dataWithContentsOfFile:completePath] isEqualToData:source],
                       @"dump file does not match source memory");

        readerFails = YES;
        H5GGTestAssert([controller startFrom:@"0x1000" end:@"0x1008"
                                           filename:@"failed.bin"],
                       @"failing dump did not start");
        H5GGTestAssert([controller.status[@"state"] isEqualToString:@"failed"],
                       @"read failure has wrong state");
        H5GGTestAssert([controller.status[@"error"] hasPrefix:@"Unreadable memory at"],
                       @"read failure address is missing");
        H5GGTestAssert(completionCount == 2 && !completionResult,
                       @"failed completion did not settle false once");
        H5GGTestAssert(releaseCount == 2, @"failed target lease was not released");
        NSString* failedPath = [root stringByAppendingPathComponent:@"failed.bin"];
        H5GGTestAssert(![NSFileManager.defaultManager fileExistsAtPath:failedPath],
                       @"failed dump retained a partial file");

        readerFails = NO;
        targetAvailable = NO;
        H5GGTestAssert(![controller startFrom:@"0x1000" end:@"0x1008"
                                            filename:@"missing.bin"],
                       @"missing target was accepted");
        H5GGTestAssert(completionCount == 2, @"missing target created a completion");
        targetAvailable = YES;

        __block NSUInteger abandonedReleases = 0;
        H5GGDumpController* noCompletion = [[H5GGDumpController alloc]
            initWithDocumentsPath:root
            targetProvider:^H5GGDumpTargetLease* {
                return [[H5GGDumpTargetLease alloc]
                    initWithReader:^size_t(__unused void* output,
                                           __unused uint64_t address,
                                           __unused size_t length) {
                        return 0;
                    }
                    release:^{ abandonedReleases++; }];
            }
            completionProvider:^H5GGDumpCompletion {
                return nil;
            }
            workExecutor:immediate
            completionExecutor:immediate];
        H5GGTestAssert(![noCompletion startFrom:@"0x1000" end:@"0x1008"
                                             filename:@"no-completion.bin"],
                       @"request without deferred completion was accepted");
        H5GGTestAssert(abandonedReleases == 1,
                       @"setup failure did not release its target lease");

        __block dispatch_block_t pendingWork = nil;
        __block NSUInteger cancelledCompletions = 0;
        __block BOOL cancelledResult = YES;
        __block NSUInteger cancelledReleases = 0;
        H5GGDumpController* cancellable = [[H5GGDumpController alloc]
            initWithDocumentsPath:root
            targetProvider:^H5GGDumpTargetLease* {
                return [[H5GGDumpTargetLease alloc]
                    initWithReader:^size_t(void* output, uint64_t address, size_t length) {
                        if(address < 0x1000 || address >= 0x1000 + source.length) return 0;
                        NSUInteger offset = (NSUInteger)(address - 0x1000);
                        size_t readable = std::min(length, (size_t)source.length - offset);
                        std::memcpy(output, (const uint8_t*)source.bytes + offset, readable);
                        return readable;
                    }
                    release:^{ cancelledReleases++; }];
            }
            completionProvider:^H5GGDumpCompletion {
                return ^(BOOL success) {
                    cancelledCompletions++;
                    cancelledResult = success;
                };
            }
            workExecutor:^(dispatch_block_t work) {
                pendingWork = work;
            }
            completionExecutor:immediate];
        H5GGTestAssert([cancellable startFrom:@"0x1000" end:@"0x1014"
                                            filename:@"cancelled.bin"],
                       @"cancellable dump did not start");
        H5GGTestAssert([cancellable.status[@"state"] isEqualToString:@"running"],
                       @"queued dump is not running");
        H5GGTestAssert(![cancellable startFrom:@"0x1000" end:@"0x1008"
                                             filename:@"overlap.bin"],
                       @"overlapping dump was accepted");
        H5GGTestAssert([cancellable cancel], @"running dump was not cancelled");
        pendingWork();
        pendingWork = nil;
        H5GGTestAssert([cancellable.status[@"state"] isEqualToString:@"cancelled"],
                       @"cancelled dump has wrong state");
        H5GGTestAssert(cancelledCompletions == 1 && !cancelledResult,
                       @"cancelled completion did not settle false once");
        H5GGTestAssert(cancelledReleases == 1, @"cancelled lease was not released");
        NSString* cancelledPath = [root stringByAppendingPathComponent:@"cancelled.bin"];
        H5GGTestAssert(![NSFileManager.defaultManager fileExistsAtPath:cancelledPath],
                       @"cancelled dump retained a partial file");
        H5GGTestAssert(![cancellable cancel], @"completed cancellation was accepted");

        [NSFileManager.defaultManager removeItemAtPath:completePath error:nil];
        H5GGTestAssert(rmdir(createdRoot) == 0, @"temporary root cleanup failed");
    }
    return 0;
}
