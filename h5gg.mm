#include "Localized.h"
#include "h5gg.h"
#include "TopShow.h"
#include "FloatMenu.h"
#include "crossproc.h"
#include "version.h"
#include "FileNames.h"
#include "MemoryPage.h"
#include "MemoryDump.h"

#include <libgen.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <new>

#define CS_VALID                    0x00000001
#define CS_HARD                     0x00000100
#define CS_KILL                     0x00000200
#define CS_OPS_STATUS               0

extern bool g_standalone_runmode;

extern "C" int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

NSString* makeDYLIB(NSString* iconfile, NSString* htmlfile);

@interface FloatMenu (H5GGEngine)
-(void)alert:(NSString*)message;
@end

@interface h5ggEngine ()
-(int)ggtype2jjtype:(NSString*)type;
-(NSString*)jjtype2ggtype:(int)jjtype;
-(NSString*)formartValue:(void*)value byType:(NSString*)type;
-(int)parseValue:(void*)valuebuf from:(NSString*)value byType:(NSString*)type;
-(int)parseSearchValue:(void*)valuebuf from:(NSString*)value byType:(NSString*)type;
-(void)threadcall:(void(^)())block;
-(void)_freezerTick;
-(BOOL)_targetIsAvailable;
-(void)_invalidateTargetSession;
@end

@implementation h5ggEngine

-(instancetype)init {
    if (self = [super init]) {
        _firstSearchDone = NO;

        if(g_standalone_runmode) {
            _targetpid = 0;
            _targetport = MACH_PORT_NULL;
        } else {
            _targetpid = getpid();
            _targetport = mach_task_self();
        }

        _engine = new JJMemoryEngine(_targetport);
        _frozenValues = [NSMutableDictionary dictionary];
        _pluginObjects = [NSMutableDictionary dictionary];
        _dumpStatus = @{@"state": @"idle", @"progress": @0};
    }
    return self;
}

-(void)dealloc {
    self.dumpCancelled = YES;
    [_freezerTimer invalidate];
    _freezerTimer = nil;
    [_frozenValues removeAllObjects];

    if(_engine) {
        delete _engine;
        _engine = nullptr;
    }

    if(_targetport != MACH_PORT_NULL && _targetport != mach_task_self()) {
        mach_port_deallocate(mach_task_self(), _targetport);
        _targetport = MACH_PORT_NULL;
    }
}

-(BOOL)require:(double)minver {
    if(H5GG_VERSION < minver) {
        JSContext.currentContext.exception = [JSValue valueWithNewErrorFromMessage:Localized(@"当前H5GG版本过低") inContext:JSContext.currentContext];
        return NO;
    }
    return YES;
}

static NSString* _Nullable H5GGStringArgument(id _Nullable value) {
    if(!value || value == NSNull.null) return nil;
    if([value isKindOfClass:NSString.class]) return value;
    if([value isKindOfClass:JSValue.class]) {
        JSValue* jsValue = value;
        return jsValue.isUndefined || jsValue.isNull ? nil : jsValue.toString;
    }
    return [value description];
}

static NSString* _Nullable H5GGDocumentsPathForName(NSString* _Nullable name) {
    if(!name || !H5GGIsSafeFileName(name.UTF8String)) return nil;
    NSString* documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    return [documents stringByAppendingPathComponent:name];
}

-(NSArray<NSDictionary<NSString*,id>*>*)getProcList:(nullable id)filter {
    NSArray* allproc = getRunningProcess();
    if(!allproc)
        return nil;

    NSMutableArray* newarr = [[NSMutableArray alloc] init];
    NSString* filterString = H5GGStringArgument(filter);

    for(NSDictionary* proc in allproc) {
        char path[PATH_MAX] = {0};

        if(!proc_pidpath([proc[@"pid"] intValue], path, sizeof(path)))
            continue;

        if(strstr(path, "/private/var/") != path && strstr(path, "/var/") != path)
            continue;

        if(strstr(path, "/Application/") == NULL)
            continue;

        NSLog(@"allproc=%@, %@, %s", proc[@"pid"], proc[@"name"], path);

        if(!filterString || [filterString isEqualToString:proc[@"name"]])
            [newarr addObject:proc];
    }
    return newarr;
}

-(BOOL)setTargetProc:(pid_t)pid {
    if(pid <= 0) return NO;
    if(pid == _targetpid && _targetport != MACH_PORT_NULL) {
        if([self _targetIsAvailable]) return YES;
        [self _invalidateTargetSession];
    }

    task_port_t targetTask = MACH_PORT_NULL;
    kern_return_t ret = task_for_pid(mach_task_self(), pid, &targetTask);
    NSLog(@"task_for_pid=%d %d %d %s!", pid, ret, targetTask, mach_error_string(ret));
    if(ret != KERN_SUCCESS || targetTask == MACH_PORT_NULL) {
        if(targetTask != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), targetTask);
        }
        return NO;
    }

    JJMemoryEngine* newEngine = new(std::nothrow) JJMemoryEngine(targetTask);
    if(!newEngine) {
        mach_port_deallocate(mach_task_self(), targetTask);
        [floatH5 alert:Localized(@"错误:内存不足!")];
        return NO;
    }

    task_port_t previousPort = _targetport;
    JJMemoryEngine* previousEngine = _engine;

    _targetpid = pid;
    _targetport = targetTask;
    _engine = newEngine;
    _firstSearchDone = NO;
    _lastSearchType = nil;
    [self clearFrozenValues];

    delete previousEngine;
    if(previousPort != MACH_PORT_NULL && previousPort != mach_task_self()) {
        mach_port_deallocate(mach_task_self(), previousPort);
    }
    return YES;
}

-(BOOL)_targetIsAvailable {
    if(_targetport == MACH_PORT_NULL) return NO;
    if(_targetpid <= 0 || _targetpid == getpid()) return YES;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {};
    return proc_pidpath(_targetpid, path, sizeof(path)) > 0;
}

-(void)_invalidateTargetSession {
    task_port_t previousPort = _targetport;
    JJMemoryEngine* previousEngine = _engine;
    _targetpid = 0;
    _targetport = MACH_PORT_NULL;
    _engine = new JJMemoryEngine(MACH_PORT_NULL);
    _firstSearchDone = NO;
    _lastSearchType = nil;
    [self clearFrozenValues];
    delete previousEngine;
    if(previousPort != MACH_PORT_NULL && previousPort != mach_task_self()) {
        mach_port_deallocate(mach_task_self(), previousPort);
    }
}

-(NSDictionary<NSString*,id>*)getTargetStatus {
    BOOL available = [self _targetIsAvailable];
    pid_t pid = _targetpid;
    if(!available && _targetport != MACH_PORT_NULL) {
        [self _invalidateTargetSession];
    }
    return @{
        @"available": @(available),
        @"pid": @(pid),
        @"selected": @(pid > 0),
    };
}

-(void)setFloatTolerance:(NSString*)value {
    char* pvaluerr = NULL;
    float d = strtof(value.UTF8String, &pvaluerr);

    if(value.length == 0 || (pvaluerr && pvaluerr[0]) || d < 0) {
        [floatH5 alert:Localized(@"浮点误差格式错误")];
        return;
    }
    NSLog(@"SetFloatTolerance=%f", d);
    _engine->SetFloatTolerance(d);
}

-(void)clearResults {
    _firstSearchDone = NO;
    if(_engine) delete _engine;
    _engine = new JJMemoryEngine(_targetport);
}

-(void)searchChange:(NSString*)type {
    int changeType = 0;
    if([type isEqualToString:@"Unchanged"]) changeType = JJ_Change_Unchanged;
    else if([type isEqualToString:@"Changed"]) changeType = JJ_Change_Changed;
    else if([type isEqualToString:@"Increased"]) changeType = JJ_Change_Increased;
    else if([type isEqualToString:@"Decreased"]) changeType = JJ_Change_Decreased;
    else {
        [floatH5 alert:Localized(@"无效的变更类型, 请使用: Unchanged/Changed/Increased/Decreased")];
        return;
    }

    if(self.engine->getResultsCount() == 0) {
        [floatH5 alert:Localized(@"当前列表为空, 请先执行搜索")];
        return;
    }

    self.engine->JJRefineByChange(changeType);
    self.firstSearchDone = YES;
}

-(long)getResultsCount {
    return _engine->getResultsCount();
}

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getResults:(int)maxCount param1:(int)skipCount {
    NSMutableArray<NSDictionary<NSString*,NSString*>*>* resultArr = [[NSMutableArray alloc] init];

    map<void*, int8_t> results;

    try {
        results = _engine->getResultsAndTypes(maxCount, skipCount);
    } catch(std::bad_alloc) {
        [floatH5 alert:Localized(@"错误:内存不足!")];
    }

    for(const auto& [address, jjtype] : results) {
        int8_t resolvedType = jjtype;
        if(resolvedType == 0)
            resolvedType = [self ggtype2jjtype:_lastSearchType];

        NSString* ggtype = [self jjtype2ggtype:resolvedType];

        UInt8 valuebuf[8] = {0};
        _engine->JJReadMemory(valuebuf, (UInt64)address, resolvedType);

        [resultArr addObject:@{
            @"address": [NSString stringWithFormat:@"0x%llX", (uint64_t)address],
            @"value": [self formartValue:valuebuf byType:ggtype],
            @"type": ggtype,
        }];
    }

    return resultArr;
}

-(int)ggtype2jjtype:(NSString*)type {
    if([type isEqualToString:@"I8"])     return JJ_Search_Type_SByte;
    if([type isEqualToString:@"U8"])     return JJ_Search_Type_UByte;
    if([type isEqualToString:@"I16"])    return JJ_Search_Type_SShort;
    if([type isEqualToString:@"U16"])    return JJ_Search_Type_UShort;
    if([type isEqualToString:@"I32"])    return JJ_Search_Type_SInt;
    if([type isEqualToString:@"U32"])    return JJ_Search_Type_UInt;
    if([type isEqualToString:@"I64"])    return JJ_Search_Type_SLong;
    if([type isEqualToString:@"U64"])    return JJ_Search_Type_ULong;
    if([type isEqualToString:@"F32"])    return JJ_Search_Type_Float;
    if([type isEqualToString:@"F64"])    return JJ_Search_Type_Double;
    return 0;
}

-(NSString*)jjtype2ggtype:(int)jjtype {
    switch(jjtype) {
        case JJ_Search_Type_SByte:  return @"I8";
        case JJ_Search_Type_UByte:  return @"U8";
        case JJ_Search_Type_SShort: return @"I16";
        case JJ_Search_Type_UShort: return @"U16";
        case JJ_Search_Type_SInt:   return @"I32";
        case JJ_Search_Type_UInt:   return @"U32";
        case JJ_Search_Type_SLong:  return @"I64";
        case JJ_Search_Type_ULong:  return @"U64";
        case JJ_Search_Type_Float:  return @"F32";
        case JJ_Search_Type_Double: return @"F64";
    }
    return @"";
}

-(NSString*)formartValue:(void*)value byType:(NSString*)type {
    if([type isEqualToString:@"I8"])
        return [NSString stringWithFormat:@"%d", (int)*(int8_t*)value];
    if([type isEqualToString:@"U8"])
        return [NSString stringWithFormat:@"%u", (unsigned int)*(UInt8*)value];
    if([type isEqualToString:@"I16"])
        return [NSString stringWithFormat:@"%d", (int)*(int16_t*)value];
    if([type isEqualToString:@"U16"])
        return [NSString stringWithFormat:@"%u", (unsigned int)*(UInt16*)value];
    if([type isEqualToString:@"I32"])
        return [NSString stringWithFormat:@"%d", *(int32_t*)value];
    if([type isEqualToString:@"U32"])
        return [NSString stringWithFormat:@"%u", *(UInt32*)value];
    if([type isEqualToString:@"I64"])
        return [NSString stringWithFormat:@"%lld", *(int64_t*)value];
    if([type isEqualToString:@"U64"])
        return [NSString stringWithFormat:@"%llu", *(UInt64*)value];
    if([type isEqualToString:@"F32"]) {
        NSString* fmt = (*(uint32_t*)value && fabs(*(float*)value) < 1.0) ? @"%g" : @"%f";
        return [NSString stringWithFormat:fmt, *(float*)value];
    }
    if([type isEqualToString:@"F64"]) {
        NSString* fmt = (*(uint64_t*)value && fabs(*(double*)value) < 1.0) ? @"%g" : @"%f";
        return [NSString stringWithFormat:fmt, *(double*)value];
    }

    [floatH5 alert:Localized(@"不支持的数值类型")];
    return nil;
}

-(int)parseValue:(void*)valuebuf from:(NSString*)value byType:(NSString*)type {
    int JJType = [self ggtype2jjtype:type];
    if(!JJType) {
        [floatH5 alert:Localized(@"不支持的数值类型")];
        return 0;
    }

    if(!JJParseValue(value.UTF8String, JJType, (uint8_t*)valuebuf)) {
        [floatH5 alert:Localized(@"数值格式错误或与类型不匹配")];
        return 0;
    }

    return JJType;
}

-(int)parseSearchValue:(void*)valuebuf from:(NSString*)value byType:(NSString*)type {
    NSString* pattern = @"^([^~～]+)[~～]([^~～]+)$";
    NSRegularExpression* regex = [[NSRegularExpression alloc] initWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult* result = [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    NSLog(@"firstMatchInString rangeCount=%lu %@", (unsigned long)result.numberOfRanges, result);

    if(result.numberOfRanges != 3) {
        int jjtype = [self parseValue:valuebuf from:value byType:type];
        if(!jjtype) return 0;
        int len = JJ_Search_Type_Len[jjtype];
        void* valuebuf2 = (void*)((uint64_t)valuebuf + len);
        memcpy(valuebuf2, valuebuf, len);
        return jjtype;
    }

    NSString* value1 = [value substringWithRange:[result rangeAtIndex:1]];
    NSString* value2 = [value substringWithRange:[result rangeAtIndex:2]];

    NSLog(@"value1=%@ value2=%@", value1, value2);

    int jjtype = [self ggtype2jjtype:type];
    if(!jjtype) return 0;

    int len = JJ_Search_Type_Len[jjtype];

    if(![self parseValue:valuebuf from:value1 byType:type])
        return 0;

    void* valuebuf2 = (void*)((uint64_t)valuebuf + len);

    if(![self parseValue:valuebuf2 from:value2 byType:type])
        return 0;

    return jjtype;
}

-(void)searchNumber:(NSString*)value param2:(NSString*)type param3:(NSString*)memoryFrom param4:(NSString*)memoryTo {
    NSLog(@"searchNumber=%@:%@ [%@:%@]", type, value, memoryFrom, memoryTo);

    if(!(value.length && type.length && memoryFrom.length && memoryTo.length)) {
        [floatH5 alert:Localized(@"数值搜索:参数有误")];
        return;
    }

    UInt8 valuebuf[8*2];

    int jjtype = [self parseSearchValue:valuebuf from:value byType:type];
    if(!jjtype) return;

    if(![memoryFrom hasPrefix:@"0x"] || ![memoryTo hasPrefix:@"0x"]) {
        [floatH5 alert:Localized(@"搜索范围需以0x开头十六进制数")];
        return;
    }

    AddrRange range = {};
    if(!JJParseAddress(memoryFrom.UTF8String, 16, range.start) ||
       !JJParseAddress(memoryTo.UTF8String, 16, range.end) ||
       range.start >= range.end) {
        [floatH5 alert:Localized(@"内存搜索范围格式错误")];
        return;
    }

    NSArray *parts = [value componentsSeparatedByString:@","];
    if(parts.count > 1) {
        if(_firstSearchDone && _engine->getResultsCount() == 0) {
            [floatH5 alert:Localized(@"改善搜索失败: 当前列表为空, 请清除后再重新开始搜索")];
            return;
        }

        BOOL firstGroup = !_firstSearchDone;

        for(NSString *part in parts) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if(trimmed.length == 0) continue;

            UInt8 valuebuf[8*2];
            int jjtype = [self parseSearchValue:valuebuf from:trimmed byType:type];
            if(!jjtype) continue;

            _engine->JJScanMemory(range, valuebuf, jjtype);
            if(firstGroup) {
                _firstSearchDone = YES;
                firstGroup = NO;
            }
        }
        _lastSearchType = type;
        return;
    }

    if(_firstSearchDone && _engine->getResultsCount() == 0) {
        [floatH5 alert:Localized(@"改善搜索失败: 当前列表为空, 请清除后再重新开始搜索")];
        return;
    }

    NSLog(@"searchNumber=%d [%p:%p]", jjtype, (void*)range.start, (void*)range.end);

    try {
        _engine->JJScanMemory(range, valuebuf, jjtype);
    } catch(std::bad_alloc) {
        [floatH5 alert:Localized(@"错误:内存不足!")];
    }

    [self addSearchHistory:value type:type count:(int)_engine->getResultsCount()];
    _firstSearchDone = YES;
    _lastSearchType = type;
}

-(void)searchNearby:(NSString*)value param2:(NSString*)type param3:(NSString*)range {
    NSLog(@"searchNearby=%@:%@ [%@]", type, value, range);

    if(!(value.length && type.length && range.length)) {
        [floatH5 alert:Localized(@"邻近搜索:参数有误")];
        return;
    }

    if(![range hasPrefix:@"0x"]) {
        [floatH5 alert:Localized(@"邻近范围需以0x开头十六进制数")];
        return;
    }

    UInt8 valuebuf[8*2];

    int jjtype = [self parseSearchValue:valuebuf from:value byType:type];
    if(!jjtype) return;

    uint64_t parsedSearchRange = 0;
    if(!JJParseAddress(range.UTF8String, 16, parsedSearchRange) ||
       parsedSearchRange > SIZE_MAX) {
        [floatH5 alert:Localized(@"邻近范围格式错误")];
        return;
    }
    size_t searchRange = (size_t)parsedSearchRange;

    if(searchRange < 2 || searchRange > 4096) {
        [floatH5 alert:Localized(@"邻近范围只能在2~4096之间")];
        return;
    }

    if(_engine->getResultsCount() == 0) {
        [floatH5 alert:Localized(@"邻近搜索错误: 当前列表为空, 请清除后再重新开始搜索")];
        return;
    }

    try {
        _engine->JJNearBySearch(searchRange, valuebuf, jjtype);
    } catch(std::bad_alloc) {
        [floatH5 alert:Localized(@"错误:内存不足!")];
    }

    _lastSearchType = type;
}

-(nullable NSString*)getValue:(NSString*)address param2:(NSString*)type {
    NSLog(@"getValue %@ %@", address, type);

    int jjtype = [self ggtype2jjtype:type];
    if(!jjtype) return @"";

    UInt64 addr = 0;
    if(!JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !addr) {
        [floatH5 alert:Localized(@"读取失败:地址格式有误!")];
        return @"";
    }

    UInt8 valuebuf[8];
    if(!_engine->JJReadMemory(valuebuf, addr, jjtype))
        return @"";

    return [self formartValue:valuebuf byType:type];
}

-(BOOL)setValue:(NSString*)address param2:(NSString*)value param3:(NSString*)type {
    UInt8 valuebuf[8];

    int jjtype = [self parseValue:valuebuf from:value byType:type];
    if(!jjtype) return NO;

    UInt64 addr = 0;
    if(!JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !addr) {
        [floatH5 alert:Localized(@"修改失败:地址格式有误!")];
        return NO;
    }

    return _engine->JJWriteMemory((void*)addr, valuebuf, jjtype);
}

-(int)editAll:(NSString*)value param3:(NSString*)type {
    UInt8 valuebuf[8];

    int jjtype = [self parseValue:valuebuf from:value byType:type];
    if(!jjtype) return 0;

    if(_engine->getResultsCount() == 0) {
        [floatH5 alert:Localized(@"修改全部: 结果列表为空!")];
        return 0;
    }

    return _engine->JJWriteAll(valuebuf, jjtype);
}

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getRangesList:(nullable id)filter {
    NSString* filterString = H5GGStringArgument(filter);
    if(_targetpid != getpid())
        return getRangesList2(_targetpid, _targetport, filterString);

    NSMutableArray* results = [[NSMutableArray alloc] init];

    for(int i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        void* baseaddr = (void*)_dyld_get_image_header(i);
        void* slide = (void*)_dyld_get_image_vmaddr_slide(i);

        NSLog(@"getRangesList[%d] %p %p %s", i, baseaddr, slide, name);

        BOOL matches = !filterString
            || (i == 0 && [filterString isEqual:@"0"])
            || [filterString isEqual:[NSString stringWithUTF8String:basename((char*)name)]];

        if(matches) {
            uint64_t size = getMachoVMSize(_targetpid, _targetport, (uint64_t)baseaddr);
            uint64_t end = size ? ((uint64_t)baseaddr + size) : 0;

            [results addObject:@{
                @"name": [NSString stringWithUTF8String:name],
                @"start": [NSString stringWithFormat:@"0x%llX", (uint64_t)baseaddr],
                @"end": [NSString stringWithFormat:@"0x%llX", end],
            }];

            if(i == 0 && [filterString isEqual:@"0"]) break;
        }
    }

    return results;
}

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getLocalScripts {
    NSMutableArray* results = [[NSMutableArray alloc] init];

    NSString* docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];

    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDir error:nil];

    for(NSString* file in files) {
        if([file.lowercaseString hasSuffix:@".js"] || [file.lowercaseString hasSuffix:@".html"])
            [results addObject:@{
                @"name": file,
                @"path": [NSString pathWithComponents:@[docDir, file]],
            }];
    }

    NSLog(@"scripts in Documents=%@ %@", docDir, files);

    NSString* appDir = [[NSBundle mainBundle] bundlePath];
    files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appDir error:nil];

    for(NSString* file in files) {
        if([file.lowercaseString hasSuffix:@".js"] || [file.lowercaseString hasSuffix:@".html"])
            [results addObject:@{
                @"name": file,
                @"path": [NSString pathWithComponents:@[appDir, file]],
            }];
    }

    NSLog(@"scripts in .app =%@ %@", appDir, files);

    return results;
}

-(void)threadcall:(void(^)())block {
    NSLog(@"threadcall=%p", block);
    block();
}

-(void)pickScriptFileWithTypes:(nullable id)types {
    NSNumber* callId = [floatH5 deferCurrentCall];
    NSArray* requestedTypes = nil;
    if([types isKindOfClass:NSArray.class]) {
        requestedTypes = types;
    } else if([types isKindOfClass:JSValue.class]) {
        JSValue* value = types;
        if(!value.isUndefined && !value.isNull) requestedTypes = value.toArray;
    }
    NSMutableArray<NSString*>* validTypes = [NSMutableArray array];
    for(id type in requestedTypes) {
        if([type isKindOfClass:NSString.class] && [type length] > 0) {
            [validTypes addObject:type];
        }
    }
    NSArray* resolvedTypes = validTypes.count ? validTypes : @[@"public.data"];

    [TopShow filePicker:resolvedTypes callback:^(NSString* path) {
        [floatH5 resolveCallId:callId result:path ?: NSNull.null error:nil];
    }];
}

-(NSString*)makeTweak:(NSString*)icon with:(NSString*)html {
    if(icon.length == 0 || html.length == 0) {
        return Localized(@"制作失败\n\n必须选择图标和H5文件");
    }
    NSString* result = makeDYLIB(icon, html);

    uint32_t g_csops_flags = 0;
    csops(getpid(), CS_OPS_STATUS, &g_csops_flags, 0);
    NSLog(@"csops=%x", g_csops_flags);

    uint32_t normalstate = CS_VALID | CS_HARD | CS_KILL;
    if((g_csops_flags & normalstate) == normalstate) {
        result = [result stringByAppendingString:Localized(@"\n\n你的设备未越狱, 你也可以将:\n悬浮按钮图标文件 H5Icon.png\n悬浮菜单H5文件  H5Menu.html\n打包进ipa中的.app目录中即可自动加载!")];
    }

    return result;
}

-(nullable id)loadPlugin:(NSString*)className path:(NSString*)dylib {
    if(className.length == 0 || dylib.length == 0) {
        return @{@"loaded": @NO, @"error": @"Class name and dylib path are required"};
    }
    if(![dylib hasPrefix:@"/"])
        dylib = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:dylib];

    if(access(dylib.UTF8String, F_OK) != 0) {
        NSLog(@"loadPlugin cannot find file!");
        return @{@"loaded": @NO, @"error": @"Plugin file was not found"};
    }

    chmod(dylib.UTF8String, 0755);

    if(!dlopen(dylib.UTF8String, RTLD_NOW)) {
        NSLog(@"loadPlugin dlerror:%s", dlerror());
        const char* error = dlerror();
        return @{
            @"loaded": @NO,
            @"error": error ? [NSString stringWithUTF8String:error] : @"Unable to load plugin",
        };
    }

    Class pluginClass = NSClassFromString(className);
    if(!pluginClass) {
        NSLog(@"loadPlugin cannot find NSClass!");
        return @{@"loaded": @NO, @"error": @"Plugin class was not found"};
    }

    id pluginObject = [pluginClass new];
    if(JSContext.currentContext) {
        return pluginObject;
    }
    if(![pluginObject conformsToProtocol:@protocol(H5GGPluginRPC)]) {
        return @{
            @"loaded": @NO,
            @"error": @"WK plugins must implement the H5GGPluginRPC protocol",
        };
    }

    NSString* pluginId = [NSString stringWithFormat:@"%@:%lX",
                          className, (unsigned long)dylib.hash];
    self.pluginObjects[pluginId] = pluginObject;
    return @{
        @"loaded": @YES,
        @"id": pluginId,
        @"className": className,
        @"rpc": @YES,
    };
}

-(NSDictionary<NSString*,id>*)callPlugin:(NSString*)pluginId method:(NSString*)method arguments:(NSArray*)arguments {
    id<H5GGPluginRPC> plugin = self.pluginObjects[pluginId];
    if(!plugin) return @{@"ok": @NO, @"error": @"Unknown plugin handle"};
    if(method.length == 0 || ![arguments isKindOfClass:NSArray.class]) {
        return @{@"ok": @NO, @"error": @"A method name and argument array are required"};
    }

    NSError* error = nil;
    id result = nil;
    @try {
        result = [plugin h5ggInvoke:method arguments:arguments error:&error];
    } @catch(NSException* exception) {
        return @{
            @"ok": @NO,
            @"error": exception.reason ?: exception.name,
        };
    }

    if(error) return @{@"ok": @NO, @"error": error.localizedDescription};
    id jsonResult = result ?: NSNull.null;
    if(![NSJSONSerialization isValidJSONObject:@[jsonResult]]) {
        return @{@"ok": @NO, @"error": @"Plugin result is not JSON serializable"};
    }
    return @{@"ok": @YES, @"result": jsonResult};
}

-(NSDictionary<NSString*,id>*)getPluginCapabilities {
    return @{
        @"transport": @"rpc",
        @"protocol": @"H5GGPluginRPC",
        @"legacyJavaScriptCoreObjects": @YES,
        @"wkNativeObjects": @NO,
        @"jsonArgumentsAndResultsOnly": @YES,
    };
}

#define MAX_HISTORY 20
#define HISTORY_KEY @"H5GGInputHistory"

-(NSArray<NSString*>*)getInputHistory {
    NSArray *history = [[NSUserDefaults standardUserDefaults] arrayForKey:HISTORY_KEY];
    return history ?: @[];
}

-(void)addInputHistory:(NSString*)value {
    if(!value || value.length == 0) return;
    NSMutableArray *history = [[[NSUserDefaults standardUserDefaults] arrayForKey:HISTORY_KEY] mutableCopy];
    if(!history) history = [NSMutableArray array];
    if(history.firstObject && [history.firstObject isEqualToString:value]) return;
    [history insertObject:value atIndex:0];
    if(history.count > MAX_HISTORY) [history removeObjectsInRange:NSMakeRange(MAX_HISTORY, history.count - MAX_HISTORY)];
    [[NSUserDefaults standardUserDefaults] setObject:history forKey:HISTORY_KEY];
}

-(void)clearInputHistory {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:HISTORY_KEY];
}

#define BOOKMARKS_KEY @"H5GGBookmarks"

-(BOOL)addBookmark:(NSString*)address name:(NSString*)name type:(NSString*)type {
    if(!address || !name || !type) return NO;
    NSMutableArray *bookmarks = [[[NSUserDefaults standardUserDefaults] arrayForKey:BOOKMARKS_KEY] mutableCopy];
    if(!bookmarks) bookmarks = [NSMutableArray array];

    for(NSDictionary *b in bookmarks) {
        if([b[@"address"] isEqualToString:address]) return NO;
    }

    [bookmarks addObject:@{@"address": address, @"name": name, @"type": type}];
    [[NSUserDefaults standardUserDefaults] setObject:bookmarks forKey:BOOKMARKS_KEY];
    return YES;
}

-(BOOL)removeBookmark:(NSString*)address {
    if(!address) return NO;
    NSMutableArray *bookmarks = [[[NSUserDefaults standardUserDefaults] arrayForKey:BOOKMARKS_KEY] mutableCopy];
    if(!bookmarks) return NO;

    NSInteger idx = -1;
    for(NSInteger i = 0; i < bookmarks.count; i++) {
        if([bookmarks[i][@"address"] isEqualToString:address]) { idx = i; break; }
    }
    if(idx < 0) return NO;

    [bookmarks removeObjectAtIndex:idx];
    [[NSUserDefaults standardUserDefaults] setObject:bookmarks forKey:BOOKMARKS_KEY];
    return YES;
}

-(NSArray<NSDictionary<NSString*,NSString*>*>*)getBookmarks {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:BOOKMARKS_KEY] ?: @[];
}

-(void)clearBookmarks {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:BOOKMARKS_KEY];
}

-(BOOL)freezeValue:(NSString*)address value:(NSString*)value type:(NSString*)type {
    if(!address || !value || !type || ![self _targetIsAvailable]) return NO;

    UInt64 parsedAddress = 0;
    int jjtype = [self ggtype2jjtype:type];
    uint8_t parsedValue[8] = {};
    if(!jjtype ||
       !JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10,
                       parsedAddress) ||
       !parsedAddress ||
       !JJParseValue(value.UTF8String, jjtype, parsedValue)) {
        return NO;
    }

    NSString* canonicalAddress = [NSString stringWithFormat:@"0x%llX", parsedAddress];
    _frozenValues[canonicalAddress] = [@{
        @"address": canonicalAddress,
        @"value": value,
        @"type": type,
        @"targetPid": @(_targetpid),
        @"status": @"active",
        @"failures": @0,
        @"lastError": NSNull.null,
    } mutableCopy];
    if(!_freezerTimer) {
        __weak __typeof(self) weakSelf = self;
        _freezerTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf _freezerTick];
        }];
    }
    return YES;
}

-(BOOL)unfreezeValue:(NSString*)address {
    UInt64 parsedAddress = 0;
    if(!address ||
       !JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10,
                       parsedAddress)) return NO;
    NSString* canonicalAddress = [NSString stringWithFormat:@"0x%llX", parsedAddress];
    if(!_frozenValues[canonicalAddress]) return NO;
    [_frozenValues removeObjectForKey:canonicalAddress];
    if(_frozenValues.count == 0) {
        [_freezerTimer invalidate];
        _freezerTimer = nil;
    }
    return YES;
}

-(NSArray<NSDictionary<NSString*,id>*>*)getFrozenValues {
    return [[_frozenValues allValues] sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary* left, NSDictionary* right) {
            return [left[@"address"] compare:right[@"address"]
                                      options:NSNumericSearch];
        }];
}

-(void)clearFrozenValues {
    [_frozenValues removeAllObjects];
    [_freezerTimer invalidate];
    _freezerTimer = nil;
}

-(void)_freezerTick {
    BOOL targetAvailable = [self _targetIsAvailable];
    for(NSMutableDictionary* entry in [_frozenValues allValues]) {
        if(![entry[@"targetPid"] isEqual:@(_targetpid)] || !targetAvailable) {
            entry[@"status"] = @"target-unavailable";
            entry[@"lastError"] = @"Target process is no longer available";
            continue;
        }

        UInt8 valuebuf[8];
        int jjtype = [self ggtype2jjtype:entry[@"type"]];
        if(!jjtype || !JJParseValue([entry[@"value"] UTF8String], jjtype, valuebuf)) {
            entry[@"status"] = @"invalid";
            entry[@"lastError"] = @"Stored value is invalid";
            continue;
        }
        UInt64 addr = 0;
        if(!JJParseAddress([entry[@"address"] UTF8String],
                           [entry[@"address"] hasPrefix:@"0x"] ? 16 : 10,
                           addr) || !addr) {
            entry[@"status"] = @"invalid";
            entry[@"lastError"] = @"Stored address is invalid";
            continue;
        }
        if(_engine->JJWriteMemory((void*)addr, valuebuf, jjtype)) {
            entry[@"status"] = @"active";
            entry[@"failures"] = @0;
            entry[@"lastError"] = NSNull.null;
        } else {
            entry[@"status"] = @"write-failed";
            entry[@"failures"] = @([entry[@"failures"] unsignedIntegerValue] + 1);
            entry[@"lastError"] = @"Memory write failed";
        }
    }
}

#define SEARCH_HISTORY_KEY @"H5GGSearchHistory"
#define MAX_SEARCH_HISTORY 50

-(NSArray<NSDictionary<NSString*,NSString*>*>*)getSearchHistory {
    return [[NSUserDefaults standardUserDefaults] arrayForKey:SEARCH_HISTORY_KEY] ?: @[];
}

-(void)addSearchHistory:(NSString*)value type:(NSString*)type count:(int)count {
    if(!value) return;
    NSMutableArray *history = [[[NSUserDefaults standardUserDefaults] arrayForKey:SEARCH_HISTORY_KEY] mutableCopy];
    if(!history) history = [NSMutableArray array];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";

    [history insertObject:@{
        @"value": value,
        @"type": type ?: @"",
        @"count": @(count),
        @"time": [fmt stringFromDate:[NSDate date]]
    } atIndex:0];

    if(history.count > MAX_SEARCH_HISTORY)
        [history removeObjectsInRange:NSMakeRange(MAX_SEARCH_HISTORY, history.count - MAX_SEARCH_HISTORY)];

    [[NSUserDefaults standardUserDefaults] setObject:history forKey:SEARCH_HISTORY_KEY];
}

-(void)clearSearchHistory {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEARCH_HISTORY_KEY];
}

-(void)searchHex:(NSString*)hex memoryFrom:(NSString*)memoryFrom memoryTo:(NSString*)memoryTo {
    if(!hex || !memoryFrom || !memoryTo) {
        [floatH5 alert:Localized(@"十六进制搜索:参数有误")];
        return;
    }

    if(![memoryFrom hasPrefix:@"0x"] || ![memoryTo hasPrefix:@"0x"]) {
        [floatH5 alert:Localized(@"搜索范围需以0x开头十六进制数")];
        return;
    }

    AddrRange range = {};
    if(!JJParseAddress([memoryFrom UTF8String], 16, range.start) ||
       !JJParseAddress([memoryTo UTF8String], 16, range.end) ||
       range.start >= range.end) {
        [floatH5 alert:Localized(@"内存搜索范围格式错误")];
        return;
    }

    JJHexPattern parsedPattern;
    if(!JJParseMaskedHexPattern(hex.UTF8String, parsedPattern)) {
        [floatH5 alert:Localized(@"十六进制格式错误")];
        return;
    }

    _engine->JJScanHexMemory(range, [hex UTF8String]);

    _firstSearchDone = YES;
    _lastSearchType = @"Hex";
}

-(BOOL)dumpMemory:(NSString*)start end:(NSString*)end filename:(NSString*)filename {
    NSString* outputPath = H5GGDocumentsPathForName(filename);
    if(!outputPath) return NO;

    UInt64 addr = 0;
    UInt64 endAddr = 0;
    if(!JJParseAddress([start UTF8String], [start hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !JJParseAddress([end UTF8String], [end hasPrefix:@"0x"] ? 16 : 10, endAddr) ||
       !addr || addr >= endAddr || endAddr - addr > SIZE_MAX) return NO;

    if([self.dumpStatus[@"state"] isEqualToString:@"running"]) return NO;

    task_port_t dumpPort = _targetport;
    if(dumpPort == MACH_PORT_NULL) return NO;
    BOOL ownsPortReference = dumpPort != mach_task_self();
    if(ownsPortReference &&
       mach_port_mod_refs(mach_task_self(), dumpPort, MACH_PORT_RIGHT_SEND, 1) != KERN_SUCCESS) {
        return NO;
    }

    NSNumber* callId = [floatH5 deferCurrentCall];
    if(!callId) {
        if(ownsPortReference) mach_port_deallocate(mach_task_self(), dumpPort);
        return NO;
    }

    size_t totalSize = (size_t)(endAddr - addr);
    self.dumpCancelled = NO;
    self.dumpStatus = @{
        @"state": @"running",
        @"progress": @0,
        @"written": @0,
        @"total": @(totalSize),
        @"path": outputPath,
    };

    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        BOOL success = NO;
        BOOL cancelled = NO;
        NSString* failure = nil;
        size_t totalWritten = 0;
        JJMemoryEngine dumpEngine(dumpPort);

        [[NSFileManager defaultManager] createFileAtPath:outputPath contents:nil attributes:nil];
        NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:outputPath];
        if(!handle) {
            failure = @"Unable to create dump file";
        } else {
            @try {
                JJMemoryDumpResult dumpResult = JJStreamMemoryDump(
                    addr, totalSize,
                    [&dumpEngine](void* output, uint64_t readAddress, size_t readLength) {
                        return dumpEngine.JJReadBytes(output, readAddress, readLength);
                    },
                    [handle](const void* bytes, size_t length) {
                        [handle writeData:[NSData dataWithBytes:bytes length:length]];
                        return YES;
                    },
                    [weakSelf]() {
                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                        return !strongSelf || strongSelf.dumpCancelled;
                    },
                    [weakSelf, outputPath](size_t written, size_t total) {
                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                        strongSelf.dumpStatus = @{
                            @"state": @"running",
                            @"progress": @((double)written / (double)total),
                            @"written": @(written),
                            @"total": @(total),
                            @"path": outputPath,
                        };
                    });
                totalWritten = dumpResult.bytesWritten;
                cancelled = dumpResult.status == JJMemoryDumpStatus::Cancelled;
                if(dumpResult.status == JJMemoryDumpStatus::ReadFailed) {
                    failure = [NSString stringWithFormat:
                        @"Unreadable memory at 0x%llX", dumpResult.failureAddress];
                } else if(dumpResult.status == JJMemoryDumpStatus::WriteFailed) {
                    failure = @"Unable to write dump file";
                } else if(dumpResult.status == JJMemoryDumpStatus::InvalidInput) {
                    failure = @"Invalid dump request";
                }
                success = dumpResult.status == JJMemoryDumpStatus::Completed;
            } @catch(NSException* exception) {
                failure = exception.reason ?: @"File write failed";
            }
            [handle closeFile];
        }

        if(ownsPortReference) {
            mach_port_deallocate(mach_task_self(), dumpPort);
        }
        if(!success) {
            [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            NSString* state = success ? @"completed" : (cancelled ? @"cancelled" : @"failed");
            strongSelf.dumpStatus = @{
                @"state": state,
                @"progress": @(success ? 1.0 : (totalSize ? (double)totalWritten / (double)totalSize : 0)),
                @"written": @(totalWritten),
                @"total": @(totalSize),
                @"path": outputPath,
                @"error": failure ?: NSNull.null,
            };
            [floatH5 resolveCallId:callId result:@(success) error:nil];
        });
    });
    return YES;
}

-(NSDictionary<NSString*,id>*)getDumpStatus {
    return self.dumpStatus ?: @{@"state": @"idle", @"progress": @0};
}

-(BOOL)cancelDump {
    if(![self.dumpStatus[@"state"] isEqualToString:@"running"]) return NO;
    self.dumpCancelled = YES;
    return YES;
}

-(void)appendLog:(NSString*)message {
    if(!message) return;
    NSString *path = [NSString stringWithFormat:@"%@/Documents/h5gg.log", NSHomeDirectory()];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if(!fh) {
        [message writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[[message stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

-(NSString*)readPointer:(NSString*)address {
    UInt64 addr = 0;
    if(!JJParseAddress([address UTF8String], [address hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !addr) return @"";

    UInt8 val[8] = {0};
    if(!_engine->JJReadMemory(val, addr, JJ_Search_Type_ULong))
        return @"";

    UInt64 ptr = *(UInt64*)val;
    if(!ptr) return @"";

    return [NSString stringWithFormat:@"0x%llX", ptr];
}

-(NSString*)readBytes:(NSString*)address length:(int)length {
    UInt64 addr = 0;
    if(!JJParseAddress([address UTF8String], [address hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !addr) return @"";
    if(length <= 0 || length > 4096) length = 256;

    NSMutableString *hex = [NSMutableString string];
    UInt8 buf[4096] = {0};
    size_t readLen = min((size_t)length, sizeof(buf));
    size_t bytesRead = _engine->JJReadBytes(buf, addr, readLen);

    for(int i = 0; i < (int)bytesRead; i++) {
        if(i > 0 && i % 16 == 0) [hex appendString:@"\n"];
        else if(i > 0 && i % 8 == 0) [hex appendString:@" "];
        [hex appendFormat:@"%02X ", buf[i]];
    }

    return hex;
}

-(NSDictionary<NSString*,id>*)readMemoryPage:(NSString*)address length:(int)length {
    UInt64 addr = 0;
    if(!JJParseAddress([address UTF8String], [address hasPrefix:@"0x"] ? 16 : 10, addr)) {
        return @{@"error": @"invalid-address"};
    }

    if(length <= 0) length = 256;
    length = MIN(length, 4096);
    if((uint64_t)(length - 1) > UINT64_MAX - addr) {
        return @{@"error": @"address-range-overflow"};
    }
    JJMemoryEngine* engine = _engine;
    JJMemoryPage page = JJReadMemoryPage(
        addr, (size_t)length,
        [engine](void* output, uint64_t readAddress, size_t readLength) {
            return engine->JJReadBytes(output, readAddress, readLength);
        });

    NSMutableArray* bytes = [NSMutableArray arrayWithCapacity:page.bytes.size()];
    for(int16_t byte : page.bytes) {
        [bytes addObject:byte < 0 ? NSNull.null : @(byte)];
    }

    return @{
        @"address": [NSString stringWithFormat:@"0x%llX", addr],
        @"length": @(page.bytes.size()),
        @"readable": @(page.readableCount()),
        @"complete": @(page.complete()),
        @"bytes": bytes,
    };
}

-(NSArray<NSDictionary<NSString*,NSString*>*>*)findPointers:(NSString*)address rangeStart:(NSString*)rangeStart rangeEnd:(NSString*)rangeEnd {
    UInt64 addr = 0;
    UInt64 start = 0;
    UInt64 endAddr = 0;
    if(!JJParseAddress([address UTF8String], [address hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !JJParseAddress([rangeStart UTF8String], 16, start) ||
       !JJParseAddress([rangeEnd UTF8String], 16, endAddr) ||
       !addr || start >= endAddr) return @[];

    AddrRange range = {start, endAddr};
    auto ptrs = _engine->JJFindPointers(addr, range);

    NSMutableArray *result = [NSMutableArray array];
    for(auto& p : ptrs) {
        [result addObject:@{
            @"address": [NSString stringWithFormat:@"0x%llX", p.first],
            @"value": [NSString stringWithFormat:@"0x%llX", p.second],
        }];
    }
    return result;
}

-(NSDictionary<NSString*,id>*)getPointerCapabilities {
    return @{
        @"pointerWidth": @64,
        @"alignment": @8,
        @"exactMatchesOnly": @YES,
        @"maxResults": @4096,
        @"maxScannedBytes": @(512ULL * 1024ULL * 1024ULL),
        @"maxChainDepth": @32,
    };
}

-(BOOL)saveScript:(NSString*)name content:(NSString*)content {
    self.lastFileError = nil;
    if(!name || !content) {
        self.lastFileError = @"A file name and content are required";
        return NO;
    }

    std::string normalized;
    if(!H5GGNormalizeScriptFileName(name.UTF8String, normalized)) {
        self.lastFileError = @"Use a single safe .js or .html file name";
        return NO;
    }

    NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if(!data || data.length > 2 * 1024 * 1024) {
        self.lastFileError = @"Scripts are limited to 2 MB";
        return NO;
    }

    NSString* normalizedName = [NSString stringWithUTF8String:normalized.c_str()];
    NSString* path = H5GGDocumentsPathForName(normalizedName);
    NSError* error = nil;
    BOOL saved = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if(!saved) self.lastFileError = error.localizedDescription ?: @"Unable to save script";
    return saved;
}

-(NSString*)loadScript:(NSString*)name {
    self.lastFileError = nil;
    std::string normalized;
    if(!name || !H5GGNormalizeScriptFileName(name.UTF8String, normalized)) {
        self.lastFileError = @"Use a single safe .js or .html file name";
        return nil;
    }
    NSString* path = H5GGDocumentsPathForName(
        [NSString stringWithUTF8String:normalized.c_str()]);
    NSError* error = nil;
    NSString* content = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if(!content) self.lastFileError = error.localizedDescription ?: @"Unable to load script";
    return content;
}

-(BOOL)deleteScript:(NSString*)name {
    self.lastFileError = nil;
    std::string normalized;
    if(!name || !H5GGNormalizeScriptFileName(name.UTF8String, normalized)) {
        self.lastFileError = @"Use a single safe .js or .html file name";
        return NO;
    }
    NSString* path = H5GGDocumentsPathForName(
        [NSString stringWithUTF8String:normalized.c_str()]);
    NSError* error = nil;
    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if(!removed) self.lastFileError = error.localizedDescription ?: @"Unable to delete script";
    return removed;
}

-(NSArray<NSString*>*)listScripts {
    self.lastFileError = nil;
    NSString* docDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSError* error = nil;
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDir error:&error];
    if(!files) {
        self.lastFileError = error.localizedDescription ?: @"Unable to list scripts";
        return @[];
    }
    NSMutableArray *scripts = [NSMutableArray array];
    for(NSString *f in files) {
        std::string normalized;
        if(H5GGNormalizeScriptFileName(f.UTF8String, normalized) &&
           normalized == f.UTF8String) {
            [scripts addObject:f];
        }
    }
    return [scripts sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

-(NSString*)getLastFileError {
    return self.lastFileError;
}

-(int)searchFilter:(NSString*)value type:(NSString*)type mode:(int)mode {
    if(!value || !type) return 0;
    if(_engine->getResultsCount() == 0) {
        [floatH5 alert:Localized(@"当前列表为空")];
        return 0;
    }
    int jjtype = [self ggtype2jjtype:type];
    if(!jjtype) return 0;
    uint8_t parsedValue[8] = {};
    if((mode != JJ_Filter_Equal && mode != JJ_Filter_Greater && mode != JJ_Filter_Less) ||
       !JJParseValue(value.UTF8String, jjtype, parsedValue)) {
        [floatH5 alert:Localized(@"数值格式错误或筛选模式无效")];
        return 0;
    }
    return (int)_engine->JJFilterResults([value UTF8String], jjtype, mode);
}

@end
