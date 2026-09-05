#import "PreferencesStoreInternal.h"

static NSString* const H5GGInputHistoryKey = @"H5GGInputHistory";
static NSString* const H5GGBookmarksKey = @"H5GGBookmarks";
static NSString* const H5GGSearchHistoryKey = @"H5GGSearchHistory";
static const NSUInteger H5GGMaximumInputHistory = 20;
static const NSUInteger H5GGMaximumSearchHistory = 50;

@interface H5GGPreferencesStore ()
@property (nonatomic, strong) NSUserDefaults* defaults;
@property (nonatomic, copy) H5GGTimestampProvider timestampProvider;
@end

@implementation H5GGPreferencesStore

-(instancetype)initWithUserDefaults:(NSUserDefaults*)defaults {
    return [self initWithUserDefaults:defaults timestampProvider:^NSString* {
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss";
        return [formatter stringFromDate:NSDate.date];
    }];
}

-(instancetype)initWithUserDefaults:(NSUserDefaults*)defaults
                   timestampProvider:(H5GGTimestampProvider)timestampProvider {
    if(!defaults || !timestampProvider) return nil;
    if(self = [super init]) {
        _defaults = defaults;
        _timestampProvider = [timestampProvider copy];
    }
    return self;
}

-(NSArray<NSString*>*)inputHistory {
    NSMutableArray<NSString*>* history = [NSMutableArray array];
    for(id value in [self.defaults arrayForKey:H5GGInputHistoryKey]) {
        if([value isKindOfClass:NSString.class]) [history addObject:value];
    }
    return history;
}

-(void)addInputHistoryValue:(NSString*)value {
    if(!value || value.length == 0) return;
    @synchronized(self) {
        NSMutableArray<NSString*>* history = [[self inputHistory] mutableCopy];
        if([history.firstObject isEqualToString:value]) return;
        [history insertObject:value atIndex:0];
        if(history.count > H5GGMaximumInputHistory) {
            [history removeObjectsInRange:NSMakeRange(
                H5GGMaximumInputHistory, history.count - H5GGMaximumInputHistory)];
        }
        [self.defaults setObject:history forKey:H5GGInputHistoryKey];
    }
}

-(void)clearInputHistory {
    @synchronized(self) {
        [self.defaults removeObjectForKey:H5GGInputHistoryKey];
    }
}

-(BOOL)addBookmarkAtAddress:(NSString*)address
                       name:(NSString*)name
                       type:(NSString*)type {
    if(!address || !name || !type) return NO;
    @synchronized(self) {
        NSMutableArray<NSDictionary<NSString*,NSString*>*>* stored =
            [[self bookmarks] mutableCopy];
        for(NSDictionary<NSString*,NSString*>* bookmark in stored) {
            if([bookmark[@"address"] isEqualToString:address]) return NO;
        }
        [stored addObject:@{@"address": address, @"name": name, @"type": type}];
        [self.defaults setObject:stored forKey:H5GGBookmarksKey];
    }
    return YES;
}

-(BOOL)removeBookmarkAtAddress:(NSString*)address {
    if(!address) return NO;
    @synchronized(self) {
        NSMutableArray<NSDictionary<NSString*,NSString*>*>* stored =
            [[self bookmarks] mutableCopy];
        NSUInteger index = [stored indexOfObjectPassingTest:
            ^BOOL(NSDictionary<NSString*,NSString*>* bookmark,
                  __unused NSUInteger candidateIndex,
                  __unused BOOL* stop) {
            return [bookmark[@"address"] isEqualToString:address];
        }];
        if(index == NSNotFound) return NO;
        [stored removeObjectAtIndex:index];
        [self.defaults setObject:stored forKey:H5GGBookmarksKey];
    }
    return YES;
}

-(NSArray<NSDictionary<NSString*,NSString*>*>*)bookmarks {
    NSMutableArray<NSDictionary<NSString*,NSString*>*>* bookmarks =
        [NSMutableArray array];
    for(id value in [self.defaults arrayForKey:H5GGBookmarksKey]) {
        if(![value isKindOfClass:NSDictionary.class]) continue;
        id address = value[@"address"];
        id name = value[@"name"];
        id type = value[@"type"];
        if([address isKindOfClass:NSString.class] &&
           [name isKindOfClass:NSString.class] &&
           [type isKindOfClass:NSString.class]) {
            [bookmarks addObject:@{@"address": address, @"name": name, @"type": type}];
        }
    }
    return bookmarks;
}

-(void)clearBookmarks {
    @synchronized(self) {
        [self.defaults removeObjectForKey:H5GGBookmarksKey];
    }
}

-(NSArray<NSDictionary<NSString*,id>*>*)searchHistory {
    NSMutableArray<NSDictionary<NSString*,id>*>* history = [NSMutableArray array];
    for(id value in [self.defaults arrayForKey:H5GGSearchHistoryKey]) {
        if(![value isKindOfClass:NSDictionary.class]) continue;
        id searchValue = value[@"value"];
        id type = value[@"type"];
        id count = value[@"count"];
        id time = value[@"time"];
        if([searchValue isKindOfClass:NSString.class] &&
           [type isKindOfClass:NSString.class] &&
           [count isKindOfClass:NSNumber.class] &&
           [time isKindOfClass:NSString.class]) {
            [history addObject:@{
                @"value": searchValue,
                @"type": type,
                @"count": count,
                @"time": time,
            }];
        }
    }
    return history;
}

-(void)addSearchHistoryValue:(NSString*)value type:(NSString*)type count:(int)count {
    if(!value) return;
    @synchronized(self) {
        NSMutableArray<NSDictionary<NSString*,id>*>* history =
            [[self searchHistory] mutableCopy];
        [history insertObject:@{
            @"value": value,
            @"type": type ?: @"",
            @"count": @(count),
            @"time": self.timestampProvider(),
        } atIndex:0];
        if(history.count > H5GGMaximumSearchHistory) {
            [history removeObjectsInRange:NSMakeRange(
                H5GGMaximumSearchHistory, history.count - H5GGMaximumSearchHistory)];
        }
        [self.defaults setObject:history forKey:H5GGSearchHistoryKey];
    }
}

-(void)clearSearchHistory {
    @synchronized(self) {
        [self.defaults removeObjectForKey:H5GGSearchHistoryKey];
    }
}

@end
