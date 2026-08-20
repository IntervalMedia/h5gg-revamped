#import "DumpControllerInternal.h"

#include "FileNames.h"
#include "MemoryDump.h"
#include "MemoryReader.h"
#include "MemoryValue.h"

#include <limits>

@interface H5GGDumpTargetLease ()
@property (nonatomic, copy) H5GGDumpReadBlock reader;
@property (nonatomic, copy, nullable) H5GGDumpReleaseBlock releaseBlock;
@end

@implementation H5GGDumpTargetLease

-(instancetype)initWithReader:(H5GGDumpReadBlock)reader
                       release:(H5GGDumpReleaseBlock)release {
    if(!reader || !release) return nil;
    if(self = [super init]) {
        _reader = [reader copy];
        _releaseBlock = [release copy];
    }
    return self;
}

-(void)dealloc {
    [self invalidate];
}

-(size_t)readBytes:(void*)output address:(uint64_t)address length:(size_t)length {
    H5GGDumpReadBlock reader = self.reader;
    return reader ? reader(output, address, length) : 0;
}

-(void)invalidate {
    H5GGDumpReleaseBlock release = nil;
    @synchronized(self) {
        release = self.releaseBlock;
        self.releaseBlock = nil;
        self.reader = nil;
    }
    if(release) release();
}

@end

@interface H5GGDumpController ()
@property (nonatomic, copy) NSString* documentsPath;
@property (nonatomic, copy) H5GGDumpTargetProvider targetProvider;
@property (nonatomic, copy) H5GGDumpCompletionProvider completionProvider;
@property (nonatomic, copy) H5GGDumpExecutor workExecutor;
@property (nonatomic, copy) H5GGDumpExecutor completionExecutor;
@property (atomic) BOOL cancelled;
@property (atomic, copy, readwrite) NSDictionary<NSString*,id>* status;
@end

@implementation H5GGDumpController

-(instancetype)initWithDocumentsPath:(NSString*)documentsPath
                       targetProvider:(H5GGDumpTargetProvider)targetProvider
                   completionProvider:(H5GGDumpCompletionProvider)completionProvider {
    return [self initWithDocumentsPath:documentsPath
                        targetProvider:targetProvider
                    completionProvider:completionProvider
                          workExecutor:^(dispatch_block_t work) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), work);
    }
                    completionExecutor:^(dispatch_block_t work) {
        dispatch_async(dispatch_get_main_queue(), work);
    }];
}

-(instancetype)initWithDocumentsPath:(NSString*)documentsPath
                       targetProvider:(H5GGDumpTargetProvider)targetProvider
                   completionProvider:(H5GGDumpCompletionProvider)completionProvider
                         workExecutor:(H5GGDumpExecutor)workExecutor
                   completionExecutor:(H5GGDumpExecutor)completionExecutor {
    if(documentsPath.length == 0 || !targetProvider || !completionProvider ||
       !workExecutor || !completionExecutor) return nil;
    if(self = [super init]) {
        _documentsPath = [documentsPath copy];
        _targetProvider = [targetProvider copy];
        _completionProvider = [completionProvider copy];
        _workExecutor = [workExecutor copy];
        _completionExecutor = [completionExecutor copy];
        _status = @{@"state": @"idle", @"progress": @0};
    }
    return self;
}

-(void)dealloc {
    self.cancelled = YES;
}

-(BOOL)startFrom:(NSString*)start end:(NSString*)end filename:(NSString*)filename {
    if(!start || !end || !filename || !H5GGIsSafeFileName(filename.UTF8String)) {
        return NO;
    }

    uint64_t address = 0;
    uint64_t endAddress = 0;
    if(!JJParseAddress(start.UTF8String, [start hasPrefix:@"0x"] ? 16 : 10, address) ||
       !JJParseAddress(end.UTF8String, [end hasPrefix:@"0x"] ? 16 : 10, endAddress) ||
       !address || address >= endAddress ||
       endAddress - address > std::numeric_limits<size_t>::max()) {
        return NO;
    }

    size_t totalSize = static_cast<size_t>(endAddress - address);
    NSString* outputPath = [self.documentsPath stringByAppendingPathComponent:filename];
    H5GGDumpTargetLease* lease = nil;
    H5GGDumpCompletion completion = nil;
    @synchronized(self) {
        if([self.status[@"state"] isEqualToString:@"running"]) return NO;
        lease = self.targetProvider();
        if(!lease) return NO;
        completion = self.completionProvider();
        if(!completion) {
            [lease invalidate];
            return NO;
        }
        self.cancelled = NO;
        self.status = @{
            @"state": @"running",
            @"progress": @0,
            @"written": @0,
            @"total": @(totalSize),
            @"path": outputPath,
        };
    }

    __weak __typeof(self) weakSelf = self;
    H5GGDumpExecutor completionExecutor = self.completionExecutor;
    self.workExecutor(^{
        BOOL success = NO;
        BOOL cancelled = NO;
        NSString* failure = nil;
        size_t totalWritten = 0;
        JJCallbackMemoryReader reader([lease](void* output,
                                               uint64_t readAddress,
                                               size_t length) {
            return [lease readBytes:output address:readAddress length:length];
        });

        BOOL created = [NSFileManager.defaultManager createFileAtPath:outputPath
                                                              contents:nil
                                                            attributes:nil];
        NSFileHandle* handle = created
            ? [NSFileHandle fileHandleForWritingAtPath:outputPath]
            : nil;
        if(!handle) {
            failure = @"Unable to create dump file";
        } else {
            @try {
                JJMemoryDumpResult result = JJStreamMemoryDump(
                    address, totalSize, reader,
                    [handle](const void* bytes, size_t length) {
                        [handle writeData:[NSData dataWithBytes:bytes length:length]];
                        return true;
                    },
                    [weakSelf]() {
                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                        return !strongSelf || strongSelf.cancelled;
                    },
                    [weakSelf, outputPath](size_t written, size_t total) {
                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                        if(!strongSelf) return;
                        strongSelf.status = @{
                            @"state": @"running",
                            @"progress": @((double)written / (double)total),
                            @"written": @(written),
                            @"total": @(total),
                            @"path": outputPath,
                        };
                    });
                totalWritten = result.bytesWritten;
                cancelled = result.status == JJMemoryDumpStatus::Cancelled;
                if(result.status == JJMemoryDumpStatus::ReadFailed) {
                    failure = [NSString stringWithFormat:
                        @"Unreadable memory at 0x%llX", result.failureAddress];
                } else if(result.status == JJMemoryDumpStatus::WriteFailed) {
                    failure = @"Unable to write dump file";
                } else if(result.status == JJMemoryDumpStatus::InvalidInput) {
                    failure = @"Invalid dump request";
                }
                success = result.status == JJMemoryDumpStatus::Completed;
            } @catch(NSException* exception) {
                failure = exception.reason ?: @"File write failed";
            }
            [handle closeFile];
        }

        if(!success) {
            [NSFileManager.defaultManager removeItemAtPath:outputPath error:nil];
        }
        [lease invalidate];

        completionExecutor(^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if(strongSelf) {
                NSString* state = success
                    ? @"completed"
                    : (cancelled ? @"cancelled" : @"failed");
                strongSelf.status = @{
                    @"state": state,
                    @"progress": @(success ? 1.0 :
                        (totalSize ? (double)totalWritten / (double)totalSize : 0)),
                    @"written": @(totalWritten),
                    @"total": @(totalSize),
                    @"path": outputPath,
                    @"error": failure ?: NSNull.null,
                };
            }
            completion(success);
        });
    });
    return YES;
}

-(BOOL)cancel {
    @synchronized(self) {
        if(![self.status[@"state"] isEqualToString:@"running"]) return NO;
        self.cancelled = YES;
        return YES;
    }
}

@end
