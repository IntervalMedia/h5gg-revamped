#import "../PreferencesStoreInternal.h"

#import <Foundation/Foundation.h>

static void H5GGTestAssert(BOOL condition, NSString* message) {
    if(condition) return;
    fprintf(stderr, "PreferencesStore test failed: %s\n", message.UTF8String);
    exit(1);
}

int main(void) {
    @autoreleasepool {
        NSString* suiteName = [@"com.test.h5gg.preferences."
            stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        [defaults removePersistentDomainForName:suiteName];
        H5GGPreferencesStore* store = [[H5GGPreferencesStore alloc]
            initWithUserDefaults:defaults
            timestampProvider:^NSString* {
                return @"12:34:56";
            }];

        [defaults setObject:@[@"valid", @7]
                     forKey:@"H5GGInputHistory"];
        NSArray<NSString*>* validOnly = @[@"valid"];
        H5GGTestAssert([store.inputHistory isEqual:validOnly],
                  @"malformed input history was exposed");
        [store clearInputHistory];
        for(NSUInteger index = 0; index < 25; index++) {
            [store addInputHistoryValue:[NSString stringWithFormat:@"%lu",
                                         (unsigned long)index]];
        }
        H5GGTestAssert(store.inputHistory.count == 20, @"input history was not capped");
        H5GGTestAssert([store.inputHistory.firstObject isEqualToString:@"24"],
                  @"input history is not newest-first");
        H5GGTestAssert([store.inputHistory.lastObject isEqualToString:@"5"],
                  @"input history retained the wrong tail");
        [store addInputHistoryValue:@"24"];
        H5GGTestAssert(store.inputHistory.count == 20, @"adjacent duplicate was inserted");
        [store clearInputHistory];
        H5GGTestAssert(store.inputHistory.count == 0, @"input history did not clear");

        H5GGTestAssert([store addBookmarkAtAddress:@"0x10" name:@"first" type:@"I32"],
                  @"valid bookmark was rejected");
        H5GGTestAssert(![store addBookmarkAtAddress:@"0x10" name:@"duplicate" type:@"U8"],
                  @"duplicate bookmark was accepted");
        H5GGTestAssert([store addBookmarkAtAddress:@"0x20" name:@"second" type:@"F32"],
                  @"second bookmark was rejected");
        H5GGTestAssert(store.bookmarks.count == 2, @"bookmark count is wrong");
        H5GGTestAssert(![store removeBookmarkAtAddress:@"0x30"],
                  @"missing bookmark was removed");
        H5GGTestAssert([store removeBookmarkAtAddress:@"0x10"],
                  @"bookmark removal failed");
        H5GGTestAssert([store.bookmarks.firstObject[@"address"] isEqualToString:@"0x20"],
                  @"wrong bookmark remained");
        [store clearBookmarks];
        H5GGTestAssert(store.bookmarks.count == 0, @"bookmarks did not clear");

        for(NSUInteger index = 0; index < 52; index++) {
            [store addSearchHistoryValue:[NSString stringWithFormat:@"value-%lu",
                                          (unsigned long)index]
                                    type:index % 2 ? @"I32" : nil
                                   count:(int)index];
        }
        H5GGTestAssert(store.searchHistory.count == 50, @"search history was not capped");
        NSDictionary<NSString*,id>* newest = store.searchHistory.firstObject;
        NSDictionary<NSString*,id>* oldest = store.searchHistory.lastObject;
        H5GGTestAssert([newest[@"value"] isEqualToString:@"value-51"],
                  @"search history is not newest-first");
        H5GGTestAssert([newest[@"count"] intValue] == 51, @"search count was not preserved");
        H5GGTestAssert([newest[@"time"] isEqualToString:@"12:34:56"],
                  @"timestamp provider was not used");
        H5GGTestAssert([oldest[@"value"] isEqualToString:@"value-2"],
                  @"search history retained the wrong tail");
        [store clearSearchHistory];
        H5GGTestAssert(store.searchHistory.count == 0, @"search history did not clear");

        [defaults removePersistentDomainForName:suiteName];
    }
    return 0;
}
