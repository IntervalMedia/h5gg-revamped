#import "../FilePickerRequest.h"

#import <Foundation/Foundation.h>

int main(void) {
    @autoreleasepool {
        __block NSUInteger firstResolutionCount = 0;
        __block NSNumber* firstResolvedCallId = nil;
        __block NSString* firstResolvedPath = @"not-set";
        H5GGFilePickerRequest* first = [[H5GGFilePickerRequest alloc]
            initWithCallId:@41
            requestedTypes:@[@" public.html ", @"", @7, @"public.html", @"public.data"]
            resolver:^(NSNumber* callId, NSString* path) {
                firstResolutionCount++;
                firstResolvedCallId = callId;
                firstResolvedPath = path;
            }];
        NSArray<NSString*>* expectedTypes = @[@"public.html", @"public.data"];
        NSCAssert([first.documentTypes isEqual:expectedTypes],
                  @"document types were not normalized and deduplicated");
        NSCAssert([first completeWithPath:nil], @"cancellation did not settle");
        NSCAssert(firstResolutionCount == 1, @"cancellation settled more than once");
        NSCAssert([firstResolvedCallId isEqual:@41], @"wrong call ID was resolved");
        NSCAssert(firstResolvedPath == nil, @"cancellation did not resolve nil");
        NSCAssert(![first completeWithPath:@"/ignored"], @"request settled twice");
        NSCAssert(firstResolutionCount == 1, @"duplicate callback reached resolver");

        __block NSMutableArray<NSNumber*>* resolvedOrder = [NSMutableArray array];
        __block NSMutableDictionary<NSNumber*, NSString*>* paths = [NSMutableDictionary dictionary];
        H5GGFilePickerResolver resolver = ^(NSNumber* callId, NSString* path) {
            [resolvedOrder addObject:callId];
            if(path) paths[callId] = path;
        };
        H5GGFilePickerRequest* second = [[H5GGFilePickerRequest alloc]
            initWithCallId:@42 requestedTypes:nil resolver:resolver];
        H5GGFilePickerRequest* third = [[H5GGFilePickerRequest alloc]
            initWithCallId:@43 requestedTypes:@[NSNull.null, @"   "] resolver:resolver];
        NSCAssert([second.documentTypes isEqual:@[@"public.data"]],
                  @"nil types did not use the default");
        NSCAssert([third.documentTypes isEqual:@[@"public.data"]],
                  @"invalid types did not use the default");
        NSCAssert([third completeWithPath:@"/third"], @"third request did not settle");
        NSCAssert([second completeWithPath:@"/second"], @"second request did not settle");
        NSArray<NSNumber*>* expectedOrder = @[@43, @42];
        NSCAssert([resolvedOrder isEqual:expectedOrder],
                  @"overlapping requests did not retain independent call IDs");
        NSCAssert([paths[@42] isEqualToString:@"/second"], @"second path was crossed");
        NSCAssert([paths[@43] isEqualToString:@"/third"], @"third path was crossed");

        __block NSUInteger racingResolutionCount = 0;
        H5GGFilePickerRequest* racing = [[H5GGFilePickerRequest alloc]
            initWithCallId:@44
            requestedTypes:@[@"public.item"]
            resolver:^(__unused NSNumber* callId, __unused NSString* path) {
                @synchronized(resolvedOrder) {
                    racingResolutionCount++;
                }
            }];
        dispatch_apply(32, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
                       ^(size_t index) {
            [racing completeWithPath:[NSString stringWithFormat:@"/%zu", index]];
        });
        NSCAssert(racingResolutionCount == 1, @"racing callbacks settled more than once");
    }
    return 0;
}
