#import "FilePickerRequest.h"

@interface H5GGFilePickerRequest ()
@property (nonatomic, copy) NSNumber* callId;
@property (nonatomic, copy, nullable) H5GGFilePickerResolver resolver;
@property (nonatomic, copy, readwrite) NSArray<NSString*>* documentTypes;
@property (nonatomic) BOOL completed;
@end

@implementation H5GGFilePickerRequest

-(instancetype)initWithCallId:(NSNumber*)callId
                requestedTypes:(NSArray*)requestedTypes
                      resolver:(H5GGFilePickerResolver)resolver {
    if(!callId || !resolver) return nil;
    if(self = [super init]) {
        _callId = [callId copy];
        _resolver = [resolver copy];

        NSMutableArray<NSString*>* validTypes = [NSMutableArray array];
        NSMutableSet<NSString*>* seenTypes = [NSMutableSet set];
        NSCharacterSet* whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        for(id candidate in requestedTypes) {
            if(![candidate isKindOfClass:NSString.class]) continue;
            NSString* type = [candidate stringByTrimmingCharactersInSet:whitespace];
            if(type.length == 0 || [seenTypes containsObject:type]) continue;
            [seenTypes addObject:type];
            [validTypes addObject:type];
        }
        _documentTypes = validTypes.count ? [validTypes copy] : @[@"public.data"];
    }
    return self;
}

-(BOOL)completeWithPath:(NSString*)path {
    H5GGFilePickerResolver resolver = nil;
    @synchronized(self) {
        if(self.completed) return NO;
        self.completed = YES;
        resolver = self.resolver;
        self.resolver = nil;
    }
    if(resolver) resolver(self.callId, path);
    return YES;
}

@end
