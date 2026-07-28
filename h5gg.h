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

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getLocalScripts;
JSExportAs(pickScriptFile, -(void)pickScriptFile:(JSValue*)callback withTypes:(nullable JSValue*)types);

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getRangesList:(nullable JSValue*)filter;

-(nullable JSValue*)getProcList:(nullable JSValue*)filter;
-(BOOL)setTargetProc:(pid_t)pid;

JSExportAs(loadPlugin, -(nullable id)loadPlugin:(NSString*)className path:(NSString*)dylib);

JSExportAs(makeTweak, -(NSString*)makeTweak:(NSString*)icon with:(NSString*)html);

@end

@interface h5ggEngine : NSObject <h5ggJSExport>
@property JJMemoryEngine* engine;
@property (nullable) NSString* lastSearchType;
@property BOOL firstSearchDone;
@property pid_t targetpid;
@property task_port_t targetport;
@end

NS_ASSUME_NONNULL_END

#endif /* h5gg_h */
