#include "makeDYLIB.h"
#include "DylibTemplate.h"
#include "Localized.h"
#import <UIKit/UIKit.h>
#define INCBIN_SILENCE_BITCODE_WARNING
#include "incbin.h"
#include <dlfcn.h>
#include <libgen.h>
#include <stdlib.h>
#include <cstring>

extern bool g_systemapp_runmode;
extern bool g_standalone_runmode;

int ldid_main(int argc, char *argv[]);

INCBIN(H5GGIconTemplate, "H5ICON_STUB_FILE");
INCBIN(H5GGMenuTemplate, "H5MENU_STUB_FILE");

static NSData* H5GGIconTemplateData(void) {
    return [NSData dataWithBytesNoCopy:(void*)gH5GGIconTemplateData
                                length:gH5GGIconTemplateSize
                          freeWhenDone:NO];
}

static NSData* H5GGMenuTemplateData(void) {
    return [NSData dataWithBytesNoCopy:(void*)gH5GGMenuTemplateData
                                length:gH5GGMenuTemplateSize
                          freeWhenDone:NO];
}

static BOOL H5GGDataHasPrefix(NSData* data, const char* prefix) {
    size_t prefixLength = strlen(prefix);
    return data.length >= prefixLength &&
           memcmp(data.bytes, prefix, prefixLength) == 0;
}

NSData* H5GGEmbeddedCustomIcon(void) {
    NSData* data = H5GGIconTemplateData();
    return H5GGDataHasPrefix(data, "H5ICON_STUB_FILE") ? nil : data;
}

NSString* H5GGEmbeddedCustomMenu(void) {
    NSData* data = H5GGMenuTemplateData();
    if(H5GGDataHasPrefix(data, "H5MENU_STUB_FILE")) return nil;
    size_t length = strnlen((const char*)data.bytes, data.length);
    return [[NSString alloc] initWithBytes:data.bytes
                                   length:length
                                 encoding:NSUTF8StringEncoding];
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
    if(![UIImage imageWithData:icon])
        return Localized(@"制作失败\n\n图标文件不是受支持的图片");

    NSData* html = [NSData dataWithContentsOfFile:htmlurl];
    if (!html)
        return [NSString stringWithFormat:Localized(@"制作失败\n\n无法读取文件:\n%@"), htmlurl];
    if(html.length == 0 ||
       memchr(html.bytes, 0, html.length) ||
       ![[NSString alloc] initWithData:html encoding:NSUTF8StringEncoding])
        return Localized(@"制作失败\n\nH5文件必须是UTF-8文本");

    NSData* iconStub = H5GGIconTemplateData();
    NSData* menuStub = H5GGMenuTemplateData();

    if (icon.length >= iconStub.length)
        return Localized(@"制作失败\n\n图标文件超过512KB");

    if (html.length >= menuStub.length)
        return Localized(@"制作失败\n\nH5文件超过2MB");

    std::vector<uint8_t> binaryBytes(
        (const uint8_t*)dylib.bytes,
        (const uint8_t*)dylib.bytes + dylib.length);
    std::vector<uint8_t> iconPlaceholder(
        (const uint8_t*)iconStub.bytes,
        (const uint8_t*)iconStub.bytes + iconStub.length);
    std::vector<uint8_t> menuPlaceholder(
        (const uint8_t*)menuStub.bytes,
        (const uint8_t*)menuStub.bytes + menuStub.length);
    std::vector<uint8_t> iconPayload(
        (const uint8_t*)icon.bytes,
        (const uint8_t*)icon.bytes + icon.length);
    std::vector<uint8_t> menuPayload(
        (const uint8_t*)html.bytes,
        (const uint8_t*)html.bytes + html.length);

    size_t iconReplacements =
        H5GGReplaceAllTemplates(binaryBytes, iconPlaceholder, iconPayload);
    size_t menuReplacements =
        H5GGReplaceAllTemplates(binaryBytes, menuPlaceholder, menuPayload);
    if(iconReplacements == 0 || menuReplacements == 0 ||
       iconReplacements != menuReplacements) {
        return Localized(@"制作失败\n\n当前已经是定制版本, 请使用原版H5GG制作插件");
    }
    dylib = [NSMutableData dataWithBytes:binaryBytes.data()
                                  length:binaryBytes.size()];

    NSString* savePath = [NSString stringWithFormat:@"%@/Documents/H5GG.dylib", NSHomeDirectory()];

    char* pathCopy = strdup(savePath.UTF8String);
    if (access(dirname(pathCopy), W_OK) != 0 && (g_systemapp_runmode || g_standalone_runmode))
        savePath = @"/var/tmp/H5GG.dylib";
    free(pathCopy);

    NSError* error = nil;
    if (![dylib writeToFile:savePath options:0 error:&error])
        return [NSString stringWithFormat:Localized(@"制作失败\n\n无法写入文件到%@\n\n%@"), savePath, error];

    const char* ldidargs[] = {"ldid", "-S", savePath.UTF8String};
    if(ldid_main(sizeof(ldidargs) / sizeof(ldidargs[0]), (char**)ldidargs) != 0) {
        [[NSFileManager defaultManager] removeItemAtPath:savePath error:nil];
        return Localized(@"制作失败\n\n代码签名失败");
    }

    return [NSString stringWithFormat:
            Localized(@"制作成功!\n\n专属H5GG.dylib已生成在当前App的Documents数据目录:\n%@"), savePath];
}
