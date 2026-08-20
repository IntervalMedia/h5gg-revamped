#ifndef H5GG_DUMP_CONTROLLER_INTERNAL_H
#define H5GG_DUMP_CONTROLLER_INTERNAL_H

#import "DumpController.h"

#include <stddef.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef size_t (^H5GGDumpReadBlock)(void* output, uint64_t address, size_t length);
typedef void (^H5GGDumpReleaseBlock)(void);
typedef void (^H5GGDumpCompletion)(BOOL success);
typedef void (^H5GGDumpExecutor)(dispatch_block_t work);

@interface H5GGDumpTargetLease : NSObject

-(instancetype)init NS_UNAVAILABLE;
-(instancetype)initWithReader:(H5GGDumpReadBlock)reader
                       release:(H5GGDumpReleaseBlock)release;
-(size_t)readBytes:(void*)output address:(uint64_t)address length:(size_t)length;
-(void)invalidate;

@end

typedef H5GGDumpTargetLease* _Nullable (^H5GGDumpTargetProvider)(void);
typedef H5GGDumpCompletion _Nullable (^H5GGDumpCompletionProvider)(void);

@interface H5GGDumpController (Internal)

-(instancetype)initWithDocumentsPath:(NSString*)documentsPath
                       targetProvider:(H5GGDumpTargetProvider)targetProvider
                   completionProvider:(H5GGDumpCompletionProvider)completionProvider;
-(instancetype)initWithDocumentsPath:(NSString*)documentsPath
                       targetProvider:(H5GGDumpTargetProvider)targetProvider
                   completionProvider:(H5GGDumpCompletionProvider)completionProvider
                         workExecutor:(H5GGDumpExecutor)workExecutor
                   completionExecutor:(H5GGDumpExecutor)completionExecutor;

@end

NS_ASSUME_NONNULL_END

#endif
