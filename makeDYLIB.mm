#include "makeDYLIB.h"
#include "Localized.h"
#include <dlfcn.h>
#include <libgen.h>
#include <stdlib.h>

extern bool g_systemapp_runmode;
extern bool g_standalone_runmode;

int ldid_main(int argc, char *argv[]);

static NSData* _stubData(NSString* filename) {
    // Try from bundle first, then from absolute path
    NSString *path = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
    if(!path) path = filename;
    NSData *d = [NSData dataWithContentsOfFile:path];
    if(!d) {
        // Fallback, create a distinctive placeholder string
        NSString *placeholder = [NSString stringWithFormat:@"__H5GG_STUB_%@__", filename];
        d = [placeholder dataUsingEncoding:NSUTF8StringEncoding];
    }
    return d;
}

NSString* makeDYLIB(NSString* iconfile, NSString* htmlurl)
{
    struct dl_info di = {0};
    dladdr((void*)makeDYLIB, &di);

    NSString* libpath = [NSString stringWithUTF8String:di.dli_fname];

    NSMutableData* dylib = [NSMutableData dataWithContentsOfFile:libpath];
    if (!dylib)
        return [NSString stringWithFormat:Localized(@"制作失败\n\n无法读取文件:\n%@"), libpath];

    NSData* icon = [NSData dataWithContentsOfFile:iconfile];
    if (!icon)
        return [NSString stringWithFormat:Localized(@"制作失败\n\n无法读取文件:\n%@"), iconfile];

    NSData* html = [NSData dataWithContentsOfFile:htmlurl];
    if (!html)
        return [NSString stringWithFormat:Localized(@"制作失败\n\n无法读取文件:\n%@"), htmlurl];

    NSData* iconStub = _stubData(@"H5ICON_STUB_FILE");
    NSData* menuStub = _stubData(@"H5MENU_STUB_FILE");

    if (icon.length > iconStub.length)
        return Localized(@"制作失败\n\n图标文件超过512KB");

    if (html.length > menuStub.length)
        return Localized(@"制作失败\n\nH5文件超过2MB");

    // Build UTF8 string pattern from stub and search the dylib binary
    NSString *iconPatternStr = [[NSString alloc] initWithData:iconStub encoding:NSUTF8StringEncoding];
    NSString *menuPatternStr = [[NSString alloc] initWithData:menuStub encoding:NSUTF8StringEncoding];

    BOOL isCustom = (iconPatternStr == nil || menuPatternStr == nil);
    if(isCustom) {
        // If stub data isn't a valid UTF-8 string, the dylib is already custom
        return Localized(@"制作失败\n\n当前已经是定制版本, 请使用原版H5GG制作插件");
    }

    NSData *pattern = [iconPatternStr dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [dylib rangeOfData:pattern options:0 range:NSMakeRange(0, dylib.length)];
    if (range.location == NSNotFound)
        return Localized(@"制作失败\n\n当前已经是定制版本, 请使用原版H5GG制作插件");

    [dylib replaceBytesInRange:NSMakeRange(range.location, icon.length) withBytes:icon.bytes];

    NSData *pattern2 = [menuPatternStr dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range2 = [dylib rangeOfData:pattern2 options:0 range:NSMakeRange(0, dylib.length)];
    if (range2.location == NSNotFound)
        return Localized(@"制作失败\n\n当前已经是定制版本, 请使用原版H5GG制作插件");

    [dylib replaceBytesInRange:NSMakeRange(range2.location, html.length) withBytes:html.bytes];

    NSString* savePath = [NSString stringWithFormat:@"%@/Documents/H5GG.dylib", NSHomeDirectory()];

    char* pathCopy = strdup(savePath.UTF8String);
    if (access(dirname(pathCopy), W_OK) != 0 && (g_systemapp_runmode || g_standalone_runmode))
        savePath = @"/var/tmp/H5GG.dylib";
    free(pathCopy);

    NSError* error = nil;
    if (![dylib writeToFile:savePath options:0 error:&error])
        return [NSString stringWithFormat:Localized(@"制作失败\n\n无法写入文件到%@\n\n%@"), savePath, error];

    const char* ldidargs[] = {"ldid", "-S", savePath.UTF8String};
    ldid_main(sizeof(ldidargs) / sizeof(ldidargs[0]), (char**)ldidargs);

    return [NSString stringWithFormat:
            Localized(@"制作成功!\n\n专属H5GG.dylib已生成在当前App的Documents数据目录:\n%@"), savePath];
}
