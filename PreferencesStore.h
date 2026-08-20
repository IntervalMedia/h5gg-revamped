#ifndef H5GG_PREFERENCES_STORE_H
#define H5GG_PREFERENCES_STORE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface H5GGPreferencesStore : NSObject

-(instancetype)init NS_UNAVAILABLE;
-(instancetype)initWithUserDefaults:(NSUserDefaults*)defaults;

-(NSArray<NSString*>*)inputHistory;
-(void)addInputHistoryValue:(NSString*)value;
-(void)clearInputHistory;

-(BOOL)addBookmarkAtAddress:(NSString*)address
                       name:(NSString*)name
                       type:(NSString*)type;
-(BOOL)removeBookmarkAtAddress:(NSString*)address;
-(NSArray<NSDictionary<NSString*,NSString*>*>*)bookmarks;
-(void)clearBookmarks;

-(NSArray<NSDictionary<NSString*,id>*>*)searchHistory;
-(void)addSearchHistoryValue:(NSString*)value type:(nullable NSString*)type count:(int)count;
-(void)clearSearchHistory;

@end

NS_ASSUME_NONNULL_END

#endif
