#include "makeDYLIB.h"
#include "DylibBuilder.h"
#include "Localized.h"
#include "RuntimeCoordinator.h"
#import <UIKit/UIKit.h>
#define INCBIN_SILENCE_BITCODE_WARNING
#include "incbin.h"
#include <dlfcn.h>
#include <cstring>

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

static std::vector<uint8_t> H5GGBytes(NSData* data) {
    if(data.length == 0) return {};
    const uint8_t* begin = static_cast<const uint8_t*>(data.bytes);
    return std::vector<uint8_t>(begin, begin + data.length);
}

static std::string H5GGUTF8String(NSString* value) {
    const char* utf8 = value.UTF8String;
    return utf8 ? utf8 : "";
}

static NSString* H5GGDylibBuildMessage(const H5GGDylibBuildResult& result,
                                       NSString* sourcePath,
                                       NSString* iconPath,
                                       NSString* menuPath,
                                       NSString* outputPath) {
    NSString* detail = result.detail.empty()
        ? @""
        : [NSString stringWithUTF8String:result.detail.c_str()];
    switch(result.status) {
        case H5GGDylibBuildStatus::Completed:
            return [NSString stringWithFormat:
                Localized(@"制作成功!\n\n专属H5GG.dylib已生成在当前App的Documents数据目录:\n%@"),
                [NSString stringWithUTF8String:result.outputPath.c_str()]];
        case H5GGDylibBuildStatus::InvalidRequest:
            return Localized(@"制作失败\n\n必须选择图标和H5文件");
        case H5GGDylibBuildStatus::UnableToReadSource:
            return [NSString stringWithFormat:Localized(@"制作失败\n\n无法读取文件:\n%@"),
                                              sourcePath ?: @""];
        case H5GGDylibBuildStatus::UnableToReadIcon:
            return [NSString stringWithFormat:Localized(@"制作失败\n\n无法读取文件:\n%@"),
                                              iconPath ?: @""];
        case H5GGDylibBuildStatus::InvalidIcon:
            return Localized(@"制作失败\n\n图标文件不是受支持的图片");
        case H5GGDylibBuildStatus::UnableToReadMenu:
            return [NSString stringWithFormat:Localized(@"制作失败\n\n无法读取文件:\n%@"),
                                              menuPath ?: @""];
        case H5GGDylibBuildStatus::InvalidMenu:
            return Localized(@"制作失败\n\nH5文件必须是UTF-8文本");
        case H5GGDylibBuildStatus::IconTooLarge:
            return Localized(@"制作失败\n\n图标文件超过512KB");
        case H5GGDylibBuildStatus::MenuTooLarge:
            return Localized(@"制作失败\n\nH5文件超过2MB");
        case H5GGDylibBuildStatus::TemplateMismatch:
            return Localized(@"制作失败\n\n当前已经是定制版本, 请使用原版H5GG制作插件");
        case H5GGDylibBuildStatus::UnableToWriteOutput:
            return [NSString stringWithFormat:
                Localized(@"制作失败\n\n无法写入文件到%@\n\n%@"),
                outputPath ?: @"", detail];
        case H5GGDylibBuildStatus::SigningFailed:
            return detail.length
                ? [NSString stringWithFormat:Localized(@"制作失败\n\n代码签名失败\n\n%@"),
                                                   detail]
                : Localized(@"制作失败\n\n代码签名失败");
    }
    return Localized(@"制作失败");
}

NSString* makeDYLIB(NSString* iconfile, NSString* htmlurl)
{
    struct dl_info di = {0};
    dladdr((void*)makeDYLIB, &di);
    NSString* libpath = di.dli_fname
        ? [NSString stringWithUTF8String:di.dli_fname]
        : nil;

    NSString* documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString* savePath = [documents stringByAppendingPathComponent:@"H5GG.dylib"];
    if(![[NSFileManager defaultManager] isWritableFileAtPath:documents] &&
       (H5GGRuntimeHasMode(H5GGRuntimeModeSystemApp) ||
        H5GGRuntimeHasMode(H5GGRuntimeModeStandalone))) {
        savePath = @"/var/tmp/H5GG.dylib";
    }

    DylibBuilder builder(
        H5GGBytes(H5GGIconTemplateData()),
        H5GGBytes(H5GGMenuTemplateData()),
        [](const std::vector<uint8_t>& bytes, std::string& error) {
            NSData* data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
            if([UIImage imageWithData:data]) return true;
            error = "The icon payload is not a supported image";
            return false;
        },
        [](const std::string& path, std::string& error) {
            char* arguments[] = {
                const_cast<char*>("ldid"),
                const_cast<char*>("-S"),
                const_cast<char*>(path.c_str()),
            };
            if(ldid_main(3, arguments) == 0) return true;
            error = "ldid returned a non-zero exit status";
            return false;
        });

    H5GGDylibBuildRequest request = {
        H5GGUTF8String(libpath),
        H5GGUTF8String(iconfile),
        H5GGUTF8String(htmlurl),
        H5GGUTF8String(savePath),
    };
    H5GGDylibBuildResult result = builder.build(request);
    return H5GGDylibBuildMessage(result, libpath, iconfile, htmlurl, savePath);
}
