#include "Localized.h"
#include "h5gg.h"
#include "TopShow.h"
#include "FloatMenu.h"
#include "crossproc.h"
#include "version.h"

#include <libgen.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>

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
    }
    return self;
}

-(BOOL)require:(double)minver {
    if(H5GG_VERSION < minver) {
        JSContext.currentContext.exception = [JSValue valueWithNewErrorFromMessage:Localized(@"当前H5GG版本过低") inContext:JSContext.currentContext];
        return NO;
    }
    return YES;
}

-(JSValue*)getProcList:(nullable JSValue*)filter {
    NSArray* allproc = getRunningProcess();
    if(!allproc)
        return [JSValue valueWithNullInContext:JSContext.currentContext];

    NSMutableArray* newarr = [[NSMutableArray alloc] init];

    for(NSDictionary* proc in allproc) {
        char path[PATH_MAX] = {0};

        if(!proc_pidpath([proc[@"pid"] intValue], path, sizeof(path)))
            continue;

        if(strstr(path, "/private/var/") != path && strstr(path, "/var/") != path)
            continue;

        if(strstr(path, "/Application/") == NULL)
            continue;

        NSLog(@"allproc=%@, %@, %s", proc[@"pid"], proc[@"name"], path);

        if([filter isUndefined] || [[filter toString] isEqualToString:proc[@"name"]])
            [newarr addObject:proc];
    }
    return [JSValue valueWithObject:newarr inContext:JSContext.currentContext];
}

-(BOOL)setTargetProc:(pid_t)pid {
    if(pid == _targetpid && _targetport != MACH_PORT_NULL)
        return YES;

    if(_targetport != MACH_PORT_NULL && _targetport != mach_task_self())
        mach_port_deallocate(mach_task_self(), _targetport);

    _targetpid = 0;
    _targetport = MACH_PORT_NULL;
    [self clearResults];

    task_port_t targetTask = 0;
    kern_return_t ret = task_for_pid(mach_task_self(), pid, &targetTask);
    NSLog(@"task_for_pid=%d %d %d %s!", pid, ret, targetTask, mach_error_string(ret));
    if(ret == KERN_SUCCESS) {
        _targetpid = pid;
        _targetport = targetTask;
        return YES;
    }

    return NO;
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
    char* pvaluerr = NULL;
    int JJType = 0;

    if([type isEqualToString:@"I8"]) {
        *(int8_t*)valuebuf = (int8_t)strtol(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_SByte;
    } else if([type isEqualToString:@"U8"]) {
        *(UInt8*)valuebuf = (UInt8)strtoul(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_UByte;
    } else if([type isEqualToString:@"I16"]) {
        *(int16_t*)valuebuf = (int16_t)strtol(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_SShort;
    } else if([type isEqualToString:@"U16"]) {
        *(UInt16*)valuebuf = (UInt16)strtoul(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_UShort;
    } else if([type isEqualToString:@"I32"]) {
        *(int32_t*)valuebuf = (int32_t)strtol(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_SInt;
    } else if([type isEqualToString:@"U32"]) {
        *(UInt32*)valuebuf = (UInt32)strtoul(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_UInt;
    } else if([type isEqualToString:@"I64"]) {
        *(int64_t*)valuebuf = strtoll(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_SLong;
    } else if([type isEqualToString:@"U64"]) {
        *(UInt64*)valuebuf = strtoull(value.UTF8String, &pvaluerr, 10);
        JJType = JJ_Search_Type_ULong;
    } else if([type isEqualToString:@"F32"]) {
        *(float*)valuebuf = strtof(value.UTF8String, &pvaluerr);
        JJType = JJ_Search_Type_Float;
    } else if([type isEqualToString:@"F64"]) {
        *(double*)valuebuf = strtod(value.UTF8String, &pvaluerr);
        JJType = JJ_Search_Type_Double;
    } else {
        [floatH5 alert:Localized(@"不支持的数值类型")];
        return 0;
    }

    if(pvaluerr && pvaluerr[0]) {
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

    char* pvaluerr = NULL;
    AddrRange range = {
        strtoul(memoryFrom.UTF8String, &pvaluerr, 16),
        strtoul(memoryTo.UTF8String, &pvaluerr, 16)
    };

    if((pvaluerr && pvaluerr[0]) || !range.end) {
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

    char* pvaluerr = NULL;
    size_t searchRange = strtoul(range.UTF8String, &pvaluerr, 16);

    if((pvaluerr && pvaluerr[0]) || !searchRange) {
        [floatH5 alert:Localized(@"邻近范围格式错误")];
        return;
    }

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

    char* pvaluerr = NULL;
    UInt64 addr = strtoul(address.UTF8String, &pvaluerr, [address hasPrefix:@"0x"] ? 16 : 10);

    if((pvaluerr && pvaluerr[0]) || !addr) {
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

    char* pvaluerr = NULL;
    UInt64 addr = strtoul(address.UTF8String, &pvaluerr, [address hasPrefix:@"0x"] ? 16 : 10);

    if((pvaluerr && pvaluerr[0]) || !addr) {
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

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getRangesList:(nullable JSValue*)filter {
    if(_targetpid != getpid())
        return getRangesList2(_targetpid, _targetport, [filter isUndefined] ? nil : [filter toString]);

    NSMutableArray* results = [[NSMutableArray alloc] init];

    for(int i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        void* baseaddr = (void*)_dyld_get_image_header(i);
        void* slide = (void*)_dyld_get_image_vmaddr_slide(i);

        NSLog(@"getRangesList[%d] %p %p %s", i, baseaddr, slide, name);

        BOOL matches = [filter isUndefined]
            || (i == 0 && [[filter toString] isEqual:@"0"])
            || [[filter toString] isEqual:[NSString stringWithUTF8String:basename((char*)name)]];

        if(matches) {
            uint64_t size = getMachoVMSize(_targetpid, _targetport, (uint64_t)baseaddr);
            uint64_t end = size ? ((uint64_t)baseaddr + size) : 0;

            [results addObject:@{
                @"name": [NSString stringWithUTF8String:name],
                @"start": [NSString stringWithFormat:@"0x%llX", (uint64_t)baseaddr],
                @"end": [NSString stringWithFormat:@"0x%llX", end],
            }];

            if(i == 0 && [[filter toString] isEqual:@"0"]) break;
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

-(void)pickScriptFile:(JSValue*)callback withTypes:(nullable JSValue*)types {
    NSLog(@"pickScriptFile=%@ %@", types, callback);

    NSArray* _types = types.isUndefined ? @[@"public.executable", @"public.html"] : types.toArray;

    NSThread* webThread = NSThread.currentThread;

    [TopShow filePicker:_types callback:^(NSString* path) {
        [self performSelector:@selector(threadcall:) onThread:webThread withObject:^{
            [callback callWithArguments:@[path ?: NSNull.null]];
        } waitUntilDone:NO];
    }];
}

-(NSString*)makeTweak:(NSString*)icon with:(NSString*)html {
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
    if(![dylib hasPrefix:@"/"])
        dylib = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:dylib];

    if(access(dylib.UTF8String, F_OK) != 0) {
        NSLog(@"loadPlugin cannot find file!");
        return nil;
    }

    chmod(dylib.UTF8String, 0755);

    if(!dlopen(dylib.UTF8String, RTLD_NOW)) {
        NSLog(@"loadPlugin dlerror:%s", dlerror());
        return nil;
    }

    static NSMutableDictionary* cache = [[NSMutableDictionary alloc] init];

    id pluginObject = cache[className];
    if(pluginObject) return pluginObject;

    Class pluginClass = NSClassFromString(className);
    if(!pluginClass) {
        NSLog(@"loadPlugin cannot find NSClass!");
        return nil;
    }

    pluginObject = [pluginClass new];
    cache[className] = pluginObject;

    return pluginObject;
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
    if(!address || !value || !type) return NO;
    _frozenValues[address] = @{@"address": address, @"value": value, @"type": type};
    if(!_freezerTimer) {
        _freezerTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
            [self _freezerTick];
        }];
    }
    return YES;
}

-(BOOL)unfreezeValue:(NSString*)address {
    if(!address || !_frozenValues[address]) return NO;
    [_frozenValues removeObjectForKey:address];
    if(_frozenValues.count == 0) {
        [_freezerTimer invalidate];
        _freezerTimer = nil;
    }
    return YES;
}

-(NSArray<NSDictionary<NSString*,NSString*>*>*)getFrozenValues {
    return [_frozenValues allValues];
}

-(void)clearFrozenValues {
    [_frozenValues removeAllObjects];
    [_freezerTimer invalidate];
    _freezerTimer = nil;
}

-(void)_freezerTick {
    for(NSDictionary* entry in [_frozenValues allValues]) {
        UInt8 valuebuf[8];
        int jjtype = [self parseValue:valuebuf from:entry[@"value"] byType:entry[@"type"]];
        if(!jjtype) continue;
        char* end = NULL;
        UInt64 addr = strtoull([entry[@"address"] UTF8String], &end, [entry[@"address"] hasPrefix:@"0x"] ? 16 : 10);
        if(end && *end) continue;
        _engine->JJWriteMemory((void*)addr, valuebuf, jjtype);
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

    char* end = NULL;
    AddrRange range = {
        strtoull([memoryFrom UTF8String], &end, 16),
        strtoull([memoryTo UTF8String], &end, 16)
    };

    if(!range.end) {
        [floatH5 alert:Localized(@"内存搜索范围格式错误")];
        return;
    }

    if(_firstSearchDone && _engine->getResultsCount() == 0) {
        [floatH5 alert:Localized(@"改善搜索失败: 当前列表为空")];
        return;
    }

    if(!_firstSearchDone) {
        _engine->JJScanHexMemory(range, [hex UTF8String]);
    } else {
        _engine = new JJMemoryEngine(_targetport);
        _engine->JJScanHexMemory(range, [hex UTF8String]);
    }

    _firstSearchDone = YES;
    _lastSearchType = @"Hex";
}

-(BOOL)dumpMemory:(NSString*)start end:(NSString*)end filename:(NSString*)filename {
    char* endPtr = NULL;
    UInt64 addr = strtoull([start UTF8String], &endPtr, [start hasPrefix:@"0x"] ? 16 : 10);
    if(endPtr && *endPtr) return NO;
    UInt64 endAddr = strtoull([end UTF8String], &endPtr, [end hasPrefix:@"0x"] ? 16 : 10);
    if(endPtr && *endPtr) return NO;
    if(addr >= endAddr) return NO;

    size_t size = (size_t)(endAddr - addr);
    NSMutableData *data = [NSMutableData dataWithLength:size];

    if(!_engine->JJReadMemory([data mutableBytes], addr, (int)size)) {
        uint8_t* buf = (uint8_t*)[data mutableBytes];
        size_t totalRead = 0;
        while(totalRead < size) {
            size_t chunk = MIN(size - totalRead, (size_t)4096);
            if(!_engine->JJReadMemory(buf + totalRead, addr + totalRead, (int)chunk))
                break;
            totalRead += chunk;
        }
        if(totalRead == 0) return NO;
        [data setLength:totalRead];
    }

    NSString *docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    NSString *path = [NSString stringWithFormat:@"%@/%@", docDir, filename];
    return [data writeToFile:path atomically:YES];
}

-(NSString*)readPointer:(NSString*)address {
    char* end = NULL;
    UInt64 addr = strtoull([address UTF8String], &end, [address hasPrefix:@"0x"] ? 16 : 10);
    if(end && *end) return @"";

    UInt8 val[8] = {0};
    if(!_engine->JJReadMemory(val, addr, JJ_Search_Type_ULong))
        return @"";

    UInt64 ptr = *(UInt64*)val;
    if(!ptr) return @"";

    return [NSString stringWithFormat:@"0x%llX", ptr];
}

-(NSArray<NSDictionary<NSString*,NSString*>*>*)findPointers:(NSString*)address rangeStart:(NSString*)rangeStart rangeEnd:(NSString*)rangeEnd {
    char* end = NULL;
    UInt64 addr = strtoull([address UTF8String], &end, [address hasPrefix:@"0x"] ? 16 : 10);
    if(end && *end) return @[];

    UInt64 start = strtoull([rangeStart UTF8String], &end, 16);
    UInt64 endAddr = strtoull([rangeEnd UTF8String], &end, 16);

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

-(BOOL)saveScript:(NSString*)name content:(NSString*)content {
    if(!name || !content) return NO;
    NSString *docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    NSString *path = [NSString stringWithFormat:@"%@/%@", docDir, name];
    if(![name hasSuffix:@".js"]) path = [path stringByAppendingPathExtension:@"js"];
    return [[content dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES];
}

-(NSString*)loadScript:(NSString*)name {
    if(!name) return nil;
    NSString *docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    NSString *path = [NSString stringWithFormat:@"%@/%@", docDir, name];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

-(BOOL)deleteScript:(NSString*)name {
    if(!name) return NO;
    NSString *docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    NSString *path = [NSString stringWithFormat:@"%@/%@", docDir, name];
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

-(NSArray<NSString*>*)listScripts {
    NSString *docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:docDir error:nil];
    NSMutableArray *scripts = [NSMutableArray array];
    for(NSString *f in files) {
        if([f hasSuffix:@".js"]) [scripts addObject:f];
    }
    return scripts;
}

@end
