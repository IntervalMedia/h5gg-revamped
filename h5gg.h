//
//  h5gg.h
//  h5gg
//
//  Created by admin on 11/3/2022.
//

/**
 *  Strong reminder: Please do not modify this JS interface to maintain the compatibility of js scripts
 */

#ifndef h5gg_h
#define h5gg_h

@class FloatMenu;
extern FloatMenu* _Nullable floatH5;

#include <sys/stat.h>
#include <sys/mount.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include "MemScan.h"
#include "TopShow.h"
#include "crossproc.h"
#include "version.h"

NS_ASSUME_NONNULL_BEGIN

@protocol h5ggJSExport <JSExport>

-(BOOL)require:(double)minver;

-(void)setFloatTolerance:(NSString*)value;

JSExportAs(searchNumber, -(void)searchNumber:(NSString*)value param2:(NSString*)type param3:(NSString*)memoryFrom param4:(NSString*)memoryTo);

JSExportAs(searchNearby, -(void)searchNearby:(NSString*)value param2:(NSString*)type param3:(NSString*)range);

JSExportAs(getValue, -(nullable NSString*)getValue:(NSString*)address param2:(NSString*)type);
JSExportAs(setValue, -(BOOL)setValue:(NSString*)address param2:(NSString*)value param3:(NSString*)type);

JSExportAs(editAll, -(int)editAll:(NSString*)value param3:(NSString*)type);

JSExportAs(getResults, -(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getResults:(int)maxCount param1:(int)skipCount);

-(long)getResultsCount;
-(void)clearResults;

JSExportAs(searchChange, -(void)searchChange:(NSString*)type);

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getLocalScripts;
-(void)pickScriptFileWithTypes:(nullable id)types;

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getRangesList:(nullable id)filter;

JSExportAs(addBookmark, -(BOOL)addBookmark:(NSString*)address name:(NSString*)name type:(NSString*)type);
JSExportAs(removeBookmark, -(BOOL)removeBookmark:(NSString*)address);
-(NSArray<NSDictionary<NSString*,NSString*>*>*)getBookmarks;
-(void)clearBookmarks;

-(nullable NSArray<NSDictionary<NSString*,id>*>*)getProcList:(nullable id)filter;
-(BOOL)setTargetProc:(pid_t)pid;

JSExportAs(loadPlugin, -(nullable id)loadPlugin:(NSString*)className path:(NSString*)dylib);

JSExportAs(makeTweak, -(NSString*)makeTweak:(NSString*)icon with:(NSString*)html);

-(NSArray<NSString*>*)getInputHistory;
-(void)addInputHistory:(NSString*)value;
-(void)clearInputHistory;

-(BOOL)addBookmark:(NSString*)address name:(NSString*)name type:(NSString*)type;
-(BOOL)removeBookmark:(NSString*)address;
-(NSArray<NSDictionary<NSString*,NSString*>*>*)getBookmarks;
-(void)clearBookmarks;

-(BOOL)freezeValue:(NSString*)address value:(NSString*)value type:(NSString*)type;
-(BOOL)unfreezeValue:(NSString*)address;
-(NSArray<NSDictionary<NSString*,NSString*>*>*)getFrozenValues;
-(void)clearFrozenValues;

// Hex search
-(void)searchHex:(NSString*)hex memoryFrom:(NSString*)memoryFrom memoryTo:(NSString*)memoryTo;

// Search history
-(NSArray<NSDictionary<NSString*,NSString*>*>*)getSearchHistory;
-(void)addSearchHistory:(NSString*)value type:(NSString*)type count:(int)count;
-(void)clearSearchHistory;

// Dump memory
-(BOOL)dumpMemory:(NSString*)start end:(NSString*)end filename:(NSString*)filename;

// Pointer chain
-(NSString*)readPointer:(NSString*)address;
-(void)appendLog:(NSString*)message;

// Find pointers
-(NSArray<NSDictionary<NSString*,NSString*>*>*)findPointers:(NSString*)address rangeStart:(NSString*)rangeStart rangeEnd:(NSString*)rangeEnd;

// Script editor
-(BOOL)saveScript:(NSString*)name content:(NSString*)content;
-(NSString*)loadScript:(NSString*)name;
-(BOOL)deleteScript:(NSString*)name;
-(NSArray<NSString*>*)listScripts;

-(int)searchFilter:(NSString*)value type:(NSString*)type mode:(int)mode;

// Read raw bytes
-(NSString*)readBytes:(NSString*)address length:(int)length;

@end

@interface h5ggEngine : NSObject <h5ggJSExport>
@property JJMemoryEngine* engine;
@property (nullable) NSString* lastSearchType;
@property BOOL firstSearchDone;
@property pid_t targetpid;
@property task_port_t targetport;
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSDictionary*>* frozenValues;
@property (nonatomic, strong) NSTimer* freezerTimer;
-(NSArray<NSString*>*)getInputHistory;
-(void)addInputHistory:(NSString*)value;
-(void)clearInputHistory;
-(BOOL)addBookmark:(NSString*)address name:(NSString*)name type:(NSString*)type;
-(BOOL)removeBookmark:(NSString*)address;
-(NSArray<NSDictionary<NSString*,NSString*>*>*)getBookmarks;
-(void)clearBookmarks;
-(BOOL)freezeValue:(NSString*)address value:(NSString*)value type:(NSString*)type;
-(BOOL)unfreezeValue:(NSString*)address;
-(NSArray<NSDictionary<NSString*,NSString*>*>*)getFrozenValues;
-(void)clearFrozenValues;
-(void)searchHex:(NSString*)hex memoryFrom:(NSString*)memoryFrom memoryTo:(NSString*)memoryTo;
-(NSArray<NSDictionary<NSString*,NSString*>*>*)getSearchHistory;
-(void)addSearchHistory:(NSString*)value type:(NSString*)type count:(int)count;
-(void)clearSearchHistory;
-(BOOL)dumpMemory:(NSString*)start end:(NSString*)end filename:(NSString*)filename;
-(NSString*)readPointer:(NSString*)address;
-(void)appendLog:(NSString*)message;
-(NSArray<NSDictionary<NSString*,NSString*>*>*)findPointers:(NSString*)address rangeStart:(NSString*)rangeStart rangeEnd:(NSString*)rangeEnd;
-(BOOL)saveScript:(NSString*)name content:(NSString*)content;
-(NSString*)loadScript:(NSString*)name;
-(BOOL)deleteScript:(NSString*)name;
-(NSArray<NSString*>*)listScripts;
-(NSString*)readBytes:(NSString*)address length:(int)length;
-(int)searchFilter:(NSString*)value type:(NSString*)type mode:(int)mode;
@end

NS_ASSUME_NONNULL_END

#endif /* h5gg_h */
