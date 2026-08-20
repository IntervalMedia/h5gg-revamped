#include "Localized.h"
#include "h5gg.h"
#include "TopShow.h"
#include "FloatMenu.h"
#include "crossproc.h"
#include "version.h"
#include "FileNames.h"
#include "MemoryPage.h"
#include "MemoryDump.h"
#include "MemScan.h"
#include "TargetSession.h"
#include "ScriptStore.h"
#include "PluginLoader.h"
#include "RuntimeCoordinator.h"
#include "FreezerController.h"
#include "FilePickerRequest.h"
#include "PreferencesStore.h"

#include <libgen.h>
#include <mach-o/dyld.h>
#include <new>
#include <utility>
#import <UIKit/UIKit.h>

#define CS_VALID                    0x00000001
#define CS_HARD                     0x00000100
#define CS_KILL                     0x00000200
#define CS_OPS_STATUS               0

extern "C" int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

NSString* makeDYLIB(NSString* iconfile, NSString* htmlfile);

@interface FloatMenu (H5GGEngine)
-(void)alert:(NSString*)message;
@end

@interface h5ggEngine ()
@property MemorySession* session;
@property ScriptStore* scriptStore;
@property (nonatomic, strong) H5GGPluginLoader* pluginLoader;
@property (nonatomic, strong) H5GGFreezerController* freezer;
@property (nonatomic, strong) H5GGPreferencesStore* preferences;
-(NSString*)formatValue:(void*)value byType:(int)type;
-(int)parseValue:(void*)valuebuf from:(NSString*)value byType:(NSString*)type;
-(void)threadcall:(void(^)())block;
-(BOOL)_targetIsAvailable;
-(void)_invalidateTargetSession;
@end

static void H5GGReleaseTaskPort(mach_port_t port) {
    mach_port_deallocate(mach_task_self(), port);
}

static void H5GGDeleteMemoryEngine(JJMemoryEngine* engine) {
    delete engine;
}

static MemorySession* H5GGCreateMemorySession(TargetProcess target) {
    JJMemoryEngine* engine = new(std::nothrow) JJMemoryEngine(target.port());
    if(!engine) return nullptr;

    MemorySession* session = new(std::nothrow) MemorySession(
        std::move(target), engine, H5GGDeleteMemoryEngine);
    if(!session) delete engine;
    return session;
}

@implementation h5ggEngine

-(instancetype)init {
    if (self = [super init]) {
        TargetProcess target = H5GGRuntimeHasMode(H5GGRuntimeModeStandalone)
            ? TargetProcess()
            : TargetProcess(getpid(), mach_task_self());
        _session = H5GGCreateMemorySession(std::move(target));
        if(!_session) return nil;
        NSString* documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        _scriptStore = new(std::nothrow) ScriptStore(documents.UTF8String);
        if(!_scriptStore) {
            delete _session;
            _session = nullptr;
            return nil;
        }
        _preferences = [[H5GGPreferencesStore alloc]
            initWithUserDefaults:NSUserDefaults.standardUserDefaults];
        if(!_preferences) {
            delete _scriptStore;
            _scriptStore = nullptr;
            delete _session;
            _session = nullptr;
            return nil;
        }
        _pluginLoader = [[H5GGPluginLoader alloc]
            initWithBundlePath:NSBundle.mainBundle.bundlePath];
        if(!_pluginLoader) {
            _preferences = nil;
            delete _scriptStore;
            _scriptStore = nullptr;
            delete _session;
            _session = nullptr;
            return nil;
        }
        __weak __typeof(self) weakSelf = self;
        _freezer = [[H5GGFreezerController alloc]
            initWithTargetPIDProvider:^pid_t {
                __strong __typeof(weakSelf) strongSelf = weakSelf;
                return strongSelf && strongSelf.session
                    ? strongSelf.session->target().pid()
                    : 0;
            }
            targetAvailabilityProvider:^BOOL {
                __strong __typeof(weakSelf) strongSelf = weakSelf;
                return strongSelf ? [strongSelf _targetIsAvailable] : NO;
            }
            writer:^BOOL(uint64_t address, const void* bytes, int valueType) {
                __strong __typeof(weakSelf) strongSelf = weakSelf;
                return strongSelf && strongSelf.session &&
                    strongSelf.session->engine()->JJWriteMemory(
                        (void*)address, (void*)bytes, valueType);
            }];
        if(!_freezer) {
            _pluginLoader = nil;
            _preferences = nil;
            delete _scriptStore;
            _scriptStore = nullptr;
            delete _session;
            _session = nullptr;
            return nil;
        }
        _dumpStatus = @{@"state": @"idle", @"progress": @0};
    }
    return self;
}

-(void)dealloc {
    self.dumpCancelled = YES;
    [_freezer clear];
    _freezer = nil;
    _preferences = nil;

    delete _session;
    _session = nullptr;
    delete _scriptStore;
    _scriptStore = nullptr;
}

-(BOOL)require:(double)minver {
    if(H5GG_VERSION < minver) {
        JSContext.currentContext.exception = [JSValue valueWithNewErrorFromMessage:Localized(@"当前H5GG版本过低") inContext:JSContext.currentContext];
        return NO;
    }
    return YES;
}

-(BOOL)copyText:(NSString*)text {
    if(!text) return NO;
    UIPasteboard.generalPasteboard.string = text;
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
    if(pid == _session->target().pid() && _session->target().valid()) {
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

    TargetProcess target(pid, targetTask, H5GGReleaseTaskPort);
    MemorySession* newSession = H5GGCreateMemorySession(std::move(target));
    if(!newSession) {
        [H5GGCurrentMenu() alert:Localized(@"错误:内存不足!")];
        return NO;
    }

    MemorySession* previousSession = _session;
    _session = newSession;
    [self clearFrozenValues];
    delete previousSession;
    return YES;
}

-(BOOL)_targetIsAvailable {
    const TargetProcess& target = _session->target();
    if(!target.valid()) return NO;
    if(target.pid() == getpid()) return YES;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {};
    return proc_pidpath(target.pid(), path, sizeof(path)) > 0;
}

-(void)_invalidateTargetSession {
    MemorySession* emptySession = H5GGCreateMemorySession(TargetProcess());
    if(!emptySession) return;
    MemorySession* previousSession = _session;
    _session = emptySession;
    [self clearFrozenValues];
    delete previousSession;
}

-(NSDictionary<NSString*,id>*)getTargetStatus {
    BOOL available = [self _targetIsAvailable];
    pid_t pid = _session->target().pid();
    if(!available && _session->target().port() != MACH_PORT_NULL) {
        [self _invalidateTargetSession];
    }
    return @{
        @"available": @(available),
        @"pid": @(pid),
        @"selected": @(pid > 0),
    };
}

-(void)setFloatTolerance:(NSString*)value {
    float d = 0;
    if(!JJParseNonnegativeFloat(value.UTF8String, d)) {
        [H5GGCurrentMenu() alert:Localized(@"浮点误差格式错误")];
        return;
    }
    NSLog(@"SetFloatTolerance=%f", d);
    _session->engine()->SetFloatTolerance(d);
}

-(void)clearResults {
    JJMemoryEngine* engine = new(std::nothrow) JJMemoryEngine(_session->target().port());
    if(!engine) {
        [H5GGCurrentMenu() alert:Localized(@"错误:内存不足!")];
        return;
    }
    _session->replaceEngine(engine, H5GGDeleteMemoryEngine);
}

-(void)searchChange:(NSString*)type {
    int changeType = 0;
    if([type isEqualToString:@"Unchanged"]) changeType = JJ_Change_Unchanged;
    else if([type isEqualToString:@"Changed"]) changeType = JJ_Change_Changed;
    else if([type isEqualToString:@"Increased"]) changeType = JJ_Change_Increased;
    else if([type isEqualToString:@"Decreased"]) changeType = JJ_Change_Decreased;
    else {
        [H5GGCurrentMenu() alert:Localized(@"无效的变更类型, 请使用: Unchanged/Changed/Increased/Decreased")];
        return;
    }

    if(_session->engine()->getResultsCount() == 0) {
        [H5GGCurrentMenu() alert:Localized(@"当前列表为空, 请先执行搜索")];
        return;
    }

    _session->engine()->JJRefineByChange(changeType);
    _session->markSearchDone(_session->lastSearchType());
}

-(long)getResultsCount {
    return _session->engine()->getResultsCount();
}

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getResults:(int)maxCount param1:(int)skipCount {
    NSMutableArray<NSDictionary<NSString*,NSString*>*>* resultArr = [[NSMutableArray alloc] init];

    map<void*, int8_t> results;

    try {
        results = _session->engine()->getResultsAndTypes(maxCount, skipCount);
    } catch(std::bad_alloc) {
        [H5GGCurrentMenu() alert:Localized(@"错误:内存不足!")];
    }

    for(const auto& [address, jjtype] : results) {
        int8_t resolvedType = jjtype;
        if(resolvedType == 0)
            resolvedType = _session->lastSearchType();

        NSString* ggtype = [NSString stringWithUTF8String:JJTypeName(resolvedType)];

        UInt8 valuebuf[8] = {0};
        _session->engine()->readValue(valuebuf, (UInt64)address, resolvedType);

        [resultArr addObject:@{
            @"address": [NSString stringWithFormat:@"0x%llX", (uint64_t)address],
            @"value": [self formatValue:valuebuf byType:resolvedType],
            @"type": ggtype,
        }];
    }

    return resultArr;
}

- (NSString*)formatValue:(void*)value byType:(int)type {
    std::string formatted;
    if(!JJFormatValue((const uint8_t*)value, type, formatted)) {
        [H5GGCurrentMenu() alert:Localized(@"不支持的数值类型")];
        return nil;
    }
    return [NSString stringWithUTF8String:formatted.c_str()];
}

-(int)parseValue:(void*)valuebuf from:(NSString*)value byType:(NSString*)type {
    int JJType = JJTypeFromName(type.UTF8String);
    if(!JJType) {
        [H5GGCurrentMenu() alert:Localized(@"不支持的数值类型")];
        return 0;
    }

    if(!JJParseValue(value.UTF8String, JJType, (uint8_t*)valuebuf)) {
        [H5GGCurrentMenu() alert:Localized(@"数值格式错误或与类型不匹配")];
        return 0;
    }

    return JJType;
}

-(void)searchNumber:(NSString*)value param2:(NSString*)type param3:(NSString*)memoryFrom param4:(NSString*)memoryTo {
    NSLog(@"searchNumber=%@:%@ [%@:%@]", type, value, memoryFrom, memoryTo);

    if(!(value.length && type.length && memoryFrom.length && memoryTo.length)) {
        [H5GGCurrentMenu() alert:Localized(@"数值搜索:参数有误")];
        return;
    }

    int jjtype = JJTypeFromName(type.UTF8String);
    if(!jjtype) {
        [H5GGCurrentMenu() alert:Localized(@"不支持的数值类型")];
        return;
    }

    vector<JJSearchValue> values;
    if(!JJParseSearchExpression(value.UTF8String, jjtype, values)) {
        [H5GGCurrentMenu() alert:Localized(@"数值格式错误或与类型不匹配")];
        return;
    }

    if(![memoryFrom hasPrefix:@"0x"] || ![memoryTo hasPrefix:@"0x"]) {
        [H5GGCurrentMenu() alert:Localized(@"搜索范围需以0x开头十六进制数")];
        return;
    }

    AddrRange range = {};
    if(!JJParseAddress(memoryFrom.UTF8String, 16, range.start) ||
       !JJParseAddress(memoryTo.UTF8String, 16, range.end) ||
       range.start >= range.end) {
        [H5GGCurrentMenu() alert:Localized(@"内存搜索范围格式错误")];
        return;
    }

    if(_session->firstSearchDone() && _session->engine()->getResultsCount() == 0) {
        [H5GGCurrentMenu() alert:Localized(@"改善搜索失败: 当前列表为空, 请清除后再重新开始搜索")];
        return;
    }

    NSLog(@"searchNumber=%d [%p:%p]", jjtype, (void*)range.start, (void*)range.end);

    try {
        _session->engine()->JJScanMemoryAny(range, values, jjtype);
    } catch(std::bad_alloc) {
        [H5GGCurrentMenu() alert:Localized(@"错误:内存不足!")];
    }

    [self addSearchHistory:value type:type count:(int)_session->engine()->getResultsCount()];
    _session->markSearchDone(jjtype);
}

-(void)searchNearby:(NSString*)value param2:(NSString*)type param3:(NSString*)range {
    NSLog(@"searchNearby=%@:%@ [%@]", type, value, range);

    if(!(value.length && type.length && range.length)) {
        [H5GGCurrentMenu() alert:Localized(@"邻近搜索:参数有误")];
        return;
    }

    if(![range hasPrefix:@"0x"]) {
        [H5GGCurrentMenu() alert:Localized(@"邻近范围需以0x开头十六进制数")];
        return;
    }

    int jjtype = JJTypeFromName(type.UTF8String);
    if(!jjtype) {
        [H5GGCurrentMenu() alert:Localized(@"不支持的数值类型")];
        return;
    }

    vector<JJSearchValue> values;
    if(!JJParseSearchExpression(value.UTF8String, jjtype, values) ||
       values.size() != 1) {
        [H5GGCurrentMenu() alert:Localized(@"数值格式错误或与类型不匹配")];
        return;
    }

    uint64_t parsedSearchRange = 0;
    if(!JJParseAddress(range.UTF8String, 16, parsedSearchRange) ||
       parsedSearchRange > SIZE_MAX) {
        [H5GGCurrentMenu() alert:Localized(@"邻近范围格式错误")];
        return;
    }
    size_t searchRange = (size_t)parsedSearchRange;

    if(searchRange < 2 || searchRange > 4096) {
        [H5GGCurrentMenu() alert:Localized(@"邻近范围只能在2~4096之间")];
        return;
    }

    if(_session->engine()->getResultsCount() == 0) {
        [H5GGCurrentMenu() alert:Localized(@"邻近搜索错误: 当前列表为空, 请清除后再重新开始搜索")];
        return;
    }

    try {
        _session->engine()->JJNearBySearch(searchRange, values[0].data(), jjtype);
    } catch(std::bad_alloc) {
        [H5GGCurrentMenu() alert:Localized(@"错误:内存不足!")];
    }

    _session->markSearchDone(jjtype);
}

-(nullable NSString*)getValue:(NSString*)address param2:(NSString*)type {
    NSLog(@"getValue %@ %@", address, type);

    int jjtype = JJTypeFromName(type.UTF8String);
    if(!jjtype) return @"";

    UInt64 addr = 0;
    if(!JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !addr) {
        [H5GGCurrentMenu() alert:Localized(@"读取失败:地址格式有误!")];
        return @"";
    }

    UInt8 valuebuf[8];
    if(!_session->engine()->readValue(valuebuf, addr, jjtype))
        return @"";

    return [self formatValue:valuebuf byType:jjtype];
}

-(BOOL)setValue:(NSString*)address param2:(NSString*)value param3:(NSString*)type {
    UInt8 valuebuf[8];

    int jjtype = [self parseValue:valuebuf from:value byType:type];
    if(!jjtype) return NO;

    UInt64 addr = 0;
    if(!JJParseAddress(address.UTF8String, [address hasPrefix:@"0x"] ? 16 : 10, addr) ||
       !addr) {
        [H5GGCurrentMenu() alert:Localized(@"修改失败:地址格式有误!")];
        return NO;
    }

    return _session->engine()->JJWriteMemory((void*)addr, valuebuf, jjtype);
}

-(int)editAll:(NSString*)value param3:(NSString*)type {
    UInt8 valuebuf[8];

    int jjtype = [self parseValue:valuebuf from:value byType:type];
    if(!jjtype) return 0;

    if(_session->engine()->getResultsCount() == 0) {
        [H5GGCurrentMenu() alert:Localized(@"修改全部: 结果列表为空!")];
        return 0;
    }

    return _session->engine()->JJWriteAll(valuebuf, jjtype);
}

-(nullable NSArray<NSDictionary<NSString*,NSString*>*>*)getRangesList:(nullable id)filter {
    NSString* filterString = H5GGStringArgument(filter);
    const TargetProcess& target = _session->target();
    if(target.pid() != getpid())
        return getRangesList2(target.pid(), target.port(), filterString);

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
            uint64_t size = getMachoVMSize(target.pid(), target.port(), (uint64_t)baseaddr);
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
    std::vector<std::string> storedScripts = _scriptStore->list();
    for(const std::string& storedName : storedScripts) {
        NSString* file = [NSString stringWithUTF8String:storedName.c_str()];
        [results addObject:@{
            @"name": file,
            @"path": [NSString pathWithComponents:@[docDir, file]],
        }];
    }

    NSLog(@"scripts in Documents=%@ %zu", docDir, storedScripts.size());

    NSString* appDir = [[NSBundle mainBundle] bundlePath];
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appDir error:nil];

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
    FloatMenu* sourceMenu = H5GGCurrentMenu();
    NSNumber* callId = [sourceMenu deferCurrentCall];
    if(!callId) return;

    NSArray* requestedTypes = nil;
    if([types isKindOfClass:NSArray.class]) {
        requestedTypes = types;
    } else if([types isKindOfClass:JSValue.class]) {
        JSValue* value = types;
        if(!value.isUndefined && !value.isNull) requestedTypes = value.toArray;
    }

    __weak FloatMenu* weakSourceMenu = sourceMenu;
    H5GGFilePickerRequest* request = [[H5GGFilePickerRequest alloc]
        initWithCallId:callId
        requestedTypes:requestedTypes
        resolver:^(NSNumber* resolvedCallId, NSString* path) {
            [weakSourceMenu resolveCallId:resolvedCallId
                                  result:path ?: NSNull.null
                                   error:nil];
        }];
    if(!request) {
        [sourceMenu resolveCallId:callId result:nil error:@"Unable to create file picker request"];
        return;
    }

    [TopShow filePicker:request.documentTypes callback:^(NSString* path) {
        [request completeWithPath:path];
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
    H5GGPluginLoadMode mode = JSContext.currentContext
        ? H5GGPluginLoadModeLegacyObject
        : H5GGPluginLoadModeJSONRPC;
    return [_pluginLoader loadPluginClass:className path:dylib mode:mode];
}

-(NSDictionary<NSString*,id>*)callPlugin:(NSString*)pluginId method:(NSString*)method arguments:(NSArray*)arguments {
    return [_pluginLoader callPlugin:pluginId method:method arguments:arguments];
}

-(NSDictionary<NSString*,id>*)getPluginCapabilities {
    return _pluginLoader.capabilities;
}

-(NSArray<NSString*>*)getInputHistory {
    return _preferences.inputHistory;
}

-(void)addInputHistory:(NSString*)value {
    [_preferences addInputHistoryValue:value];
}

-(void)clearInputHistory {
    [_preferences clearInputHistory];
}

-(BOOL)addBookmark:(NSString*)address name:(NSString*)name type:(NSString*)type {
    return [_preferences addBookmarkAtAddress:address name:name type:type];
}

-(BOOL)removeBookmark:(NSString*)address {
    return [_preferences removeBookmarkAtAddress:address];
}

-(NSArray<NSDictionary<NSString*,NSString*>*>*)getBookmarks {
    return _preferences.bookmarks;
}

-(void)clearBookmarks {
    [_preferences clearBookmarks];
}

-(BOOL)freezeValue:(NSString*)address value:(NSString*)value type:(NSString*)type {
    return [_freezer freezeAddress:address value:value type:type];
}

-(BOOL)unfreezeValue:(NSString*)address {
    return [_freezer unfreezeAddress:address];
}

-(NSArray<NSDictionary<NSString*,id>*>*)getFrozenValues {
    return [_freezer frozenValues];
}

-(void)clearFrozenValues {
    [_freezer clear];
}

-(NSArray<NSDictionary<NSString*,id>*>*)getSearchHistory {
    return _preferences.searchHistory;
}

-(void)addSearchHistory:(NSString*)value type:(NSString*)type count:(int)count {
    [_preferences addSearchHistoryValue:value type:type count:count];
}

-(void)clearSearchHistory {
    [_preferences clearSearchHistory];
}

-(void)searchHex:(NSString*)hex memoryFrom:(NSString*)memoryFrom memoryTo:(NSString*)memoryTo {
    if(!hex || !memoryFrom || !memoryTo) {
        [H5GGCurrentMenu() alert:Localized(@"十六进制搜索:参数有误")];
        return;
    }

    if(![memoryFrom hasPrefix:@"0x"] || ![memoryTo hasPrefix:@"0x"]) {
        [H5GGCurrentMenu() alert:Localized(@"搜索范围需以0x开头十六进制数")];
        return;
    }

    AddrRange range = {};
    if(!JJParseAddress([memoryFrom UTF8String], 16, range.start) ||
       !JJParseAddress([memoryTo UTF8String], 16, range.end) ||
       range.start >= range.end) {
        [H5GGCurrentMenu() alert:Localized(@"内存搜索范围格式错误")];
        return;
    }

    JJHexPattern parsedPattern;
    if(!JJParseMaskedHexPattern(hex.UTF8String, parsedPattern)) {
        [H5GGCurrentMenu() alert:Localized(@"十六进制格式错误")];
        return;
    }

    _session->engine()->JJScanHexMemory(range, [hex UTF8String]);
    _session->markSearchDone(JJ_Search_Type_UByte);
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

    task_port_t dumpPort = _session->target().port();
    if(dumpPort == MACH_PORT_NULL) return NO;
    BOOL ownsPortReference = dumpPort != mach_task_self();
    if(ownsPortReference &&
       mach_port_mod_refs(mach_task_self(), dumpPort, MACH_PORT_RIGHT_SEND, 1) != KERN_SUCCESS) {
        return NO;
    }

    NSNumber* callId = [H5GGCurrentMenu() deferCurrentCall];
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
                    addr, totalSize, dumpEngine,
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
            [H5GGCurrentMenu() resolveCallId:callId result:@(success) error:nil];
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
    if(!_session->engine()->readValue(val, addr, JJ_Search_Type_ULong))
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
    size_t bytesRead = _session->engine()->readBytes(buf, addr, readLen);

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
    JJMemoryPage page = JJReadMemoryPage(
        addr, (size_t)length, *_session->engine());

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
    auto ptrs = _session->engine()->JJFindPointers(addr, range);

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
    if(!name || !content) {
        return _scriptStore->save(name.UTF8String, std::nullopt);
    }

    NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if(!data) return _scriptStore->save(name.UTF8String, std::nullopt);
    std::string bytes((const char*)data.bytes, data.length);
    return _scriptStore->save(name.UTF8String, bytes);
}

-(NSString*)loadScript:(NSString*)name {
    std::string content;
    if(!_scriptStore->load(name.UTF8String, content)) return nil;
    return [[NSString alloc] initWithBytes:content.data()
                                   length:content.size()
                                 encoding:NSUTF8StringEncoding];
}

-(BOOL)deleteScript:(NSString*)name {
    return _scriptStore->remove(name.UTF8String);
}

-(NSArray<NSString*>*)listScripts {
    std::vector<std::string> storedScripts = _scriptStore->list();
    NSMutableArray<NSString*>* scripts = [NSMutableArray arrayWithCapacity:storedScripts.size()];
    for(const std::string& name : storedScripts) {
        [scripts addObject:[NSString stringWithUTF8String:name.c_str()]];
    }
    return scripts;
}

-(NSString*)getLastFileError {
    std::string error = _scriptStore->lastError();
    return error.empty() ? nil : [NSString stringWithUTF8String:error.c_str()];
}

-(int)searchFilter:(NSString*)value type:(NSString*)type mode:(int)mode {
    if(!value || !type) return 0;
    if(_session->engine()->getResultsCount() == 0) {
        [H5GGCurrentMenu() alert:Localized(@"当前列表为空")];
        return 0;
    }
    int jjtype = JJTypeFromName(type.UTF8String);
    if(!jjtype) return 0;
    uint8_t parsedValue[8] = {};
    if((mode != JJ_Filter_Equal && mode != JJ_Filter_Greater && mode != JJ_Filter_Less) ||
       !JJParseValue(value.UTF8String, jjtype, parsedValue)) {
        [H5GGCurrentMenu() alert:Localized(@"数值格式错误或筛选模式无效")];
        return 0;
    }
    return (int)_session->engine()->JJFilterResults([value UTF8String], jjtype, mode);
}

@end
