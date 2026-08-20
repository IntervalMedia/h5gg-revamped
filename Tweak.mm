#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <pthread.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>

#include "Localized.h"
#include "RuntimeCoordinator.h"

#ifdef H5GG_BUILD_ROOTHIDE
#import <roothide.h>
#endif

#ifdef H5GG_BUILD_ROOTLESS
#import <rootless.h>
#endif

#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#include "globalview/globalview.h"
#include "globalview/ContextHostManager.h"

GVData StaticGVSharedData = GVDataDefaultMake();
GVData* PGVSharedData = &StaticGVSharedData;
GVImageTransfer StaticGVSharedImage = GVImageTransferDefaultMake();
GVImageTransfer* PGVSharedImage = &StaticGVSharedImage;

#define INCBIN_SILENCE_BITCODE_WARNING
#include "incbin.h"

#include "makeDYLIB.h"

#include "makeWindow.h"

#include "FloatWindow.h"

//引入悬浮按钮头文件
#include "FloatButton.h"
//引入悬浮菜单头文件
#include "FloatMenu.h"

//引入h5gg的JS引擎头文件
#include "h5gg.h"

//嵌入图标文件
INCBIN(Icon, "icon.png");
//嵌入菜单H5文件
INCTXT(Menu, "Index.html");
INCTXT(MenuEn, "Index-en.html");

INCTXT(H5GG_JQUERY_FILE, "jquery.min.js");
INCTXT(H5GG_UI_RELIABILITY_FILE, "UIReliability.js");

void onScreenLayoutChange(CGSize size)
{
    NSLog(@"onScreenLayoutChange=%@", NSStringFromCGSize(size));
    FloatMenu* menu = H5GGCurrentMenu();
    if(menu) {
        NSString *js = [NSString stringWithFormat:@"if(window.h5gg_onLayoutChange)h5gg_onLayoutChange(%f,%f);", size.width, size.height];
        [menu evalJS:js];
    }
}

#define NotificationDisplayStatus CFSTR("com.apple.iokit.hid.displayStatus")

static BOOL H5GGPublishButtonImage(NSData* data) {
    if(!data || data.length == 0 || data.length > GV_IMAGE_MAX_PAYLOAD) {
        return NO;
    }
    return GVImageTransferPublish(PGVSharedImage,
                                  data.bytes,
                                  (uint32_t)data.length);
}

static void screenLockStateChanged(CFNotificationCenterRef center,void* observer,CFStringRef name, const void*object, CFDictionaryRef userInfo)
{
    NSLog(@"SetGlobalView=lock state changed. %@ %@", name, userInfo);
    NSString* lockstate = (__bridge NSString*)name;
    if ([lockstate isEqualToString:(__bridge  NSString*)NotificationDisplayStatus]) {
        NSLog(@"SetGlobalView=locked.");
        if(PGVSharedData->viewHosted) {
            NSLog(@"SetGlobalView=locked.exit");
            exit(0);
        }
    }
}

typedef struct {
    vm_address_t mapping;
    vm_size_t mappingSize;
    void* value;
} H5GGRemappedValue;

static BOOL H5GGRemapGlobal(task_port_t task,
                            UInt64 moduleBase,
                            UInt64 offset,
                            size_t valueSize,
                            H5GGRemappedValue* output) {
    if(!output || valueSize == 0 || moduleBase > UINT64_MAX - offset) return NO;

    UInt64 address = moduleBase + offset;
    if(address > UINT64_MAX - valueSize) return NO;

    UInt64 mapBase = address & ~((UInt64)PAGE_MASK);
    UInt64 bytesFromBase = address + valueSize - mapBase;
    if(bytesFromBase > UINT64_MAX - PAGE_MASK) return NO;
    UInt64 roundedSize = (bytesFromBase + PAGE_MASK) & ~((UInt64)PAGE_MASK);
    if(roundedSize == 0 || roundedSize > SIZE_MAX) return NO;

    vm_prot_t currentProtection = 0;
    vm_prot_t maximumProtection = 0;
    vm_address_t buffer = 0;
    kern_return_t result = vm_remap(mach_task_self(),
                                    &buffer,
                                    (vm_size_t)roundedSize,
                                    0,
                                    VM_FLAGS_ANYWHERE,
                                    task,
                                    (vm_address_t)mapBase,
                                    false,
                                    &currentProtection,
                                    &maximumProtection,
                                    VM_INHERIT_NONE);
    if(result != KERN_SUCCESS) {
        NSLog(@"SetGlobalView: vm_remap failed: %d %s", result, mach_error_string(result));
        return NO;
    }

    output->mapping = buffer;
    output->mappingSize = (vm_size_t)roundedSize;
    output->value = (void*)(buffer + (address - mapBase));
    return YES;
}

static void H5GGReleaseRemapping(H5GGRemappedValue value) {
    if(value.mapping && value.mappingSize) {
        vm_deallocate(mach_task_self(), value.mapping, value.mappingSize);
    }
}

static void H5GGSetGlobalView(char* dylib,
                              UInt64 GVDataOffset,
                              UInt64 GVImageOffset) {
    if(!dylib || !dylib[0]) return;
    NSLog(@"SetGlobalView=%llx, %s", (unsigned long long)GVDataOffset, dylib);
    
    pid_t sbpid = pid_for_name("SpringBoard");
    NSLog(@"SetGlobalView=sbpid=%d", sbpid);
    if(!sbpid) return;
    
    task_port_t sbtask=0;
    kern_return_t ret = task_for_pid(mach_task_self(), sbpid, &sbtask);
    NSLog(@"SetGlobalView=task_for_pid=%d %d %d %s!", sbpid, ret, sbtask, mach_error_string(ret));
    if(ret!=KERN_SUCCESS) return;
    
    NSString* dylibPath = [NSString stringWithUTF8String:dylib];
    NSArray* modules = getRangesList2(sbpid, sbtask, dylibPath.lastPathComponent);
    NSLog(@"SetGlobalView=modules=%@", modules);
    if(modules.count!=1) {
        mach_port_deallocate(mach_task_self(), sbtask);
        return;
    }
    
    UInt64 modulebase = 0;
    [[NSScanner scannerWithString:modules[0][@"start"]] scanHexLongLong:&modulebase];
    
    NSLog(@"SetGlobalView=dylib=%llu:%@, %@", (unsigned long long)modulebase, modules[0][@"start"], modules[0][@"name"]);
    
    H5GGRemappedValue dataMapping = {};
    H5GGRemappedValue imageMapping = {};
    BOOL mappedData = H5GGRemapGlobal(sbtask,
                                     modulebase,
                                     GVDataOffset,
                                     sizeof(GVData),
                                     &dataMapping);
    BOOL mappedImage = H5GGRemapGlobal(sbtask,
                                       modulebase,
                                       GVImageOffset,
                                       sizeof(GVImageTransfer),
                                       &imageMapping);
    mach_port_deallocate(mach_task_self(), sbtask);

    if(!mappedData || !mappedImage) {
        H5GGReleaseRemapping(dataMapping);
        H5GGReleaseRemapping(imageMapping);
        return;
    }

    GVData* candidateData = (GVData*)dataMapping.value;
    GVImageTransfer* candidateImage = (GVImageTransfer*)imageMapping.value;

    if(!GVDataIsCompatible(candidateData, sizeof(GVData), GV_CAPABILITY_ALL) ||
       !GVImageTransferIsCompatible(candidateImage, sizeof(GVImageTransfer))) {
        NSLog(@"SetGlobalView: incompatible protocol header (expected v%u)",
              (unsigned)GV_PROTOCOL_VERSION);
        H5GGReleaseRemapping(dataMapping);
        H5GGReleaseRemapping(imageMapping);
        return;
    }

    PGVSharedData = candidateData;
    PGVSharedImage = candidateImage;
    NSLog(@"SetGlobalView=%p image=%p version=%u capabilities=0x%llx",
          PGVSharedData,
          PGVSharedImage,
          (unsigned)PGVSharedData->header.version,
          (unsigned long long)PGVSharedData->header.capabilities);
    
    PGVSharedData->enable = YES;
    
    
    NSData* iconData = H5GGEmbeddedCustomIcon();
    if(!iconData && gIconSize <= GV_IMAGE_MAX_PAYLOAD) {
        iconData = [NSData dataWithBytesNoCopy:(void*)gIconData
                                       length:gIconSize
                                 freeWhenDone:NO];
    }
    if(iconData && !H5GGPublishButtonImage(iconData)) {
        NSLog(@"SetGlobalView: icon is too large or another update is pending (%lu bytes)",
              (unsigned long)iconData.length);
    }
    
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, screenLockStateChanged, NotificationDisplayStatus, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    dispatch_async(dispatch_get_main_queue(), ^{
        H5GGRuntimeCoordinator* runtime = H5GGRuntimeCoordinator.sharedCoordinator;
        __block BOOL appWindowHandled = NO;
        __block long long lastOrientation = 0;
        [runtime startGlobalViewMonitorWithInterval:0.1 tick:^{
            
            if(PGVSharedData->enable && PGVSharedData->customButtonAction && PGVSharedData->floatBtnClick)
            {
                NSLog(@"SetGlobalView=customButtonAction=%d", PGVSharedData->floatBtnClick);
                
                PGVSharedData->floatBtnClick = NO;
                
                [runtime.floatingMenu evalJS:@"if(window.h5gg_onButtonClick)h5gg_onButtonClick();"];
            }
            
            UIWindow* appWindow = runtime.applicationWindow;
            if(!appWindowHandled && PGVSharedData->viewHosted && appWindow)
            {
                appWindowHandled = YES;
                
                void showFloatWindow(bool show);
                showFloatWindow(true);//悬浮之后强制显示H5
                
                NSLog(@"SetGlobalView=appWindow=%@\n delegateWindow=%@\n windows=%@\n keyWindow=%@", appWindow, UIApplication.sharedApplication.delegate.window, UIApplication.sharedApplication.windows, UIApplication.sharedApplication.keyWindow);
                
                NSMutableArray* appWindows = [@[appWindow] mutableCopy];
                
                //适配定制版APP会创建一个新窗口, 默认的会被隐藏, 但是app的自动旋转是跟随默认的那个窗口
                //但是这里怎么保证那个新的窗口已经创建出来了???这个时机问题不好把握
                UIWindow* firstWin = UIApplication.sharedApplication.windows[0];
                if(firstWin!=appWindow && firstWin.isHidden
                   && [NSStringFromClass(firstWin.class) isEqualToString:@"UIWindow"]
                   && [NSStringFromClass(firstWin.rootViewController.class) isEqualToString:@"ViewController"])
                    [appWindows addObject:firstWin];

                for(UIWindow* win in appWindows)
                {
                    win.alpha = 0; //works fine
                    win.opaque = NO; //no effect
                    win.backgroundColor = [UIColor clearColor]; //no effect
                    //[win setHidden:YES]; //不可见不会自动旋转, FloatWindow无法跟随
                    
                    win.rootViewController = [[AppWinController alloc] initWithBind:win.rootViewController];
                }
            }
            
            if(
               //floatWindow && 这里不判断, 让无网络提示的TopShow也可以自动旋转, 反正后面floatWindow出来的时候已经开始跟着globalview转了
               PGVSharedData->viewHosted && lastOrientation!=PGVSharedData->curOrientation) {
                NSLog(@"SetGlobalView=rotate=%lld=>%ld", lastOrientation, (long)PGVSharedData->curOrientation);
                lastOrientation=PGVSharedData->curOrientation;
                
                for(UIWindow* win in UIApplication.sharedApplication.windows) {
                    win.layer.masksToBounds = YES;
                    [win private_updateToInterfaceOrientation:(UIInterfaceOrientation)PGVSharedData->curOrientation animated:NO];
                }
            }
            
            if(appWindowHandled && !PGVSharedData->appLoaded && UIApplication.sharedApplication.statusBarOrientation==PGVSharedData->curOrientation)
            {
                NSLog(@"SetGlobalView=appLoaded");
                PGVSharedData->appLoaded = YES;
            }
        }];
    });
}

extern "C" __attribute__ ((visibility ("default")))
void SetGlobalView(char* dylib, UInt64 GVDataOffset) {
    (void)dylib;
    (void)GVDataOffset;
    NSLog(@"SetGlobalView: legacy unversioned mapping rejected; protocol v%u requires SetGlobalViewV2",
          (unsigned)GV_PROTOCOL_VERSION);
}

extern "C" __attribute__ ((visibility ("default")))
void SetGlobalViewV2(char* dylib, UInt64 GVDataOffset, UInt64 GVImageOffset) {
    H5GGSetGlobalView(dylib, GVDataOffset, GVImageOffset);
}

FloatMenu* initFloatMenu(UIWindow* win)
{
    // Use roughly half of the available screen while preserving safe margins on phones.
    CGSize availableSize = win.bounds.size;
    CGFloat menuWidth = MIN(availableSize.width - 32.0, MAX(370.0, availableSize.width * 0.55));
    CGFloat menuHeight = MIN(availableSize.height - 32.0, MAX(370.0, availableSize.height * 0.55));
    menuWidth = MAX(320.0, menuWidth);
    menuHeight = MAX(320.0, menuHeight);

    CGRect MenuRect = CGRectMake(0, 0, menuWidth, menuHeight);
    MenuRect.origin.x = (win.frame.size.width-MenuRect.size.width)/2;
    MenuRect.origin.y = (win.frame.size.height-MenuRect.size.height)/2;
    
    FloatMenu* menu = [[FloatMenu alloc] initWithFrame:MenuRect];
    
    PGVSharedData->floatMenuRect = GVRectFromCGRect(menu.frame);
        
    //创建并初始化h5gg内存搜索引擎
    h5ggEngine* h5gg = [[h5ggEngine alloc] init];
    //将h5gg内存搜索引擎添加到H5的JS环境中以便JS可以调用
    [menu setAction:@"h5gg" callback:h5gg];
    [H5GGRuntimeCoordinator.sharedCoordinator retainFloatingWindow:win
                                                               menu:menu
                                                             engine:h5gg];
    
    __weak __typeof(menu) weakMenu = menu;
    //隐藏悬浮菜单, 已废弃, 保持旧版API兼容
    [menu setAction:@"closeMenu" callback:^{
        [weakMenu alert:@"closeMenu已废弃请勿调用"];
    }];
    //设置网络图标, 已废弃, 保持旧版API兼容
    [menu setAction:@"setFloatButton" callback:^{
        [weakMenu alert:@"setFloatButton已废弃请勿调用"];
    }];
    //设置悬浮窗位置尺寸, 已废弃, 保持旧版API兼容性
    [menu setAction:@"setFloatWindow" callback:^{
        [weakMenu alert:@"setFloatWindow已废弃请勿调用"];
    }];
    
    //给H5菜单添加一个JS函数setButtonImage用于设置网络图标
    [menu setAction:@"setButtonImage" callback:^(NSString* url) {
        FloatMenu* activeMenu = weakMenu;
        NSNumber* callId = [activeMenu deferCurrentCall];
        if(!callId) return;

        NSURL* imageUrl = [NSURL URLWithString:url];
        if(!imageUrl || imageUrl.scheme.length == 0) {
            [activeMenu resolveCallId:callId result:@NO error:nil];
            return;
        }

        void (^complete)(NSData*) = ^(NSData* data) {
            BOOL valid = data.length > 0 &&
                data.length <= GV_IMAGE_MAX_PAYLOAD &&
                [UIImage imageWithData:data] != nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                FloatMenu* resolvedMenu = weakMenu;
                FloatButton* floatBtn = H5GGRuntimeCoordinator.sharedCoordinator.floatingButton;
                BOOL applied = valid && floatBtn;
                if(applied && PGVSharedData->enable) {
                    applied = H5GGPublishButtonImage(data);
                }
                if(applied) {
                    [floatBtn setIconWithData:data];
                }
                [resolvedMenu resolveCallId:callId result:@(applied) error:nil];
            });
        };

        if([imageUrl.scheme.lowercaseString isEqualToString:@"http"] ||
           [imageUrl.scheme.lowercaseString isEqualToString:@"https"]) {
            NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:imageUrl];
            request.timeoutInterval = 15.0;
            NSURLSessionDataTask* task = [NSURLSession.sharedSession
                dataTaskWithRequest:request
                completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                    NSHTTPURLResponse* httpResponse = [response isKindOfClass:NSHTTPURLResponse.class] ?
                        (NSHTTPURLResponse*)response : nil;
                    BOOL succeeded = !error && (!httpResponse ||
                        (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300));
                    complete(succeeded ? data : nil);
                }];
            [task resume];
        } else {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                complete([NSData dataWithContentsOfURL:imageUrl]);
            });
        }
    }];
    
    [menu setAction:@"setButtonAction" callback:^{
        PGVSharedData->customButtonAction = YES;
    }];
    
    //给H5菜单添加一个JS函数setFloatWindow用于设置悬浮窗位置尺寸
    [menu setAction:@"setWindowRect" callback:^(int x, int y, int w, int h) {
        //通过主线程执行下面的代码
        FloatMenu* activeMenu = weakMenu;
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!activeMenu) return;
            CGFloat tx = x==-1&&y==-1 ? activeMenu.frame.origin.x : x;
            CGFloat ty = x==-1&&y==-1 ? activeMenu.frame.origin.y : y;
            activeMenu.frame = CGRectMake(tx,ty,w,h);
            PGVSharedData->floatMenuRect = GVRectFromCGRect(activeMenu.frame);
        });
    }];
    
    [menu setAction:@"setWindowDrag" callback:^(int x, int y, int w, int h) {
        FloatMenu* activeMenu = weakMenu;
        dispatch_async(dispatch_get_main_queue(), ^{
            [activeMenu setDragRect: CGRectMake(x,y,w,h)];
        });
    }];
    
    [menu setAction:@"setWindowTouch" callback:^(int x, int y, int w, int h) {
        FloatMenu* activeMenu = weakMenu;
        if(!activeMenu) return;
        NSLog(@"setWindowTouch %d %d %d %d", x, y, w, h);
        if((y==0&&w==0&&h==0) && (x==0||x==1)) {
            activeMenu.touchableAll = x==1;
            activeMenu.touchableRect = CGRectZero;
        } else {
            activeMenu.touchableAll = NO;
            activeMenu.touchableRect = CGRectMake(x,y,w,h);
        }
        PGVSharedData->touchableAll = activeMenu.touchableAll;
        PGVSharedData->touchableRect = GVRectFromCGRect(activeMenu.touchableRect);
        dispatch_async(dispatch_get_main_queue(), ^{
            activeMenu.userInteractionEnabled = YES;
        });
    }];
    
    void showFloatWindow(bool show);
    [menu setAction:@"setWindowVisible" callback:^(bool visible) {
        NSLog(@"setWindowVisible=%d", visible);
        if(PGVSharedData->enable && PGVSharedData->viewHosted) {
            PGVSharedData->setWindowVisible = YES;
            PGVSharedData->windowVisibleState = visible;
            return;
        }
        //通过主线程执行下面的代码
        dispatch_async(dispatch_get_main_queue(), ^{
            showFloatWindow(visible);
        });
    }];
    
    [menu setAction:@"setLayoutAction" callback:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            onScreenLayoutChange(win.frame.size);
        });
    }];
    
    // Store load info - actual loading happens after view is added to window.
    menu.rawHTML = H5GGEmbeddedCustomMenu();
    if(!menu.rawHTML) {
        NSString* bundledMenu = [NSBundle.mainBundle pathForResource:@"H5Menu" ofType:@"html"];
        if(bundledMenu) {
            menu.rawHTML = [NSString stringWithContentsOfFile:bundledMenu
                                                     encoding:NSUTF8StringEncoding
                                                        error:nil];
        }
    }
    if(!menu.rawHTML) {
        menu.rawHTML = [getLLCode() isEqualToString:@"zh"] ?
            [NSString stringWithUTF8String:gMenuData] :
            [NSString stringWithUTF8String:gMenuEnData];
    }
    NSString* jquery = [NSString stringWithUTF8String:gH5GG_JQUERY_FILEData];
    menu.rawHTML = [menu.rawHTML stringByReplacingOccurrencesOfString:@"var h5gg_jquery_stub;" withString:jquery];
    NSString* uiReliability = [NSString stringWithUTF8String:gH5GG_UI_RELIABILITY_FILEData];
    NSString* embeddedUIReliability = [NSString stringWithFormat:@"<script>%@</script>", uiReliability];
    menu.rawHTML = [menu.rawHTML stringByReplacingOccurrencesOfString:@"<script src=\"UIReliability.js\"></script>"
                                                           withString:embeddedUIReliability];
    
    return menu;
}

void showFloatWindow(bool show)
{
    H5GGRuntimeCoordinator* runtime = H5GGRuntimeCoordinator.sharedCoordinator;
    UIWindow* floatWindow = runtime.floatingWindow;
    FloatButton* floatBtn = runtime.floatingButton;
    FloatMenu* floatH5 = runtime.floatingMenu;
    if(!floatWindow) {
        
        FloatController* rootVC = [[FloatController alloc] init];
        
        rootVC.onResizeCallback = ^(CGSize size) {
            UIWindow* activeWindow = runtime.floatingWindow;
            NSLog(@"FloatWindow onSizeChange=%@ => %@", NSStringFromCGSize(activeWindow.frame.size), NSStringFromCGSize(size));
            //if(!CGRectEqualToRect(newRect, floatWindow.frame))
                onScreenLayoutChange(size);
        };
        
        //获取窗口
        floatWindow = makeWindow(NSStringFromClass(FloatWindow.class));
        floatWindow.windowLevel = UIWindowLevelAlert - 1; //比Alert低一级, 防止UIWebView的alert显示到下层去了
        floatWindow.rootViewController = rootVC;
        
        NSLog(@"FloatWindow=size=%@, %@, %@", NSStringFromCGRect(floatWindow.frame), NSStringFromCGRect(UIScreen.mainScreen.bounds), NSStringFromCGRect(UIScreen.mainScreen.nativeBounds));
        
        
        floatH5 = initFloatMenu(floatWindow);
        [runtime retainFloatingWindow:floatWindow menu:floatH5 engine:runtime.engine];
        
        //添加H5悬浮菜单到窗口上
        [floatWindow addSubview:floatH5];
        
        // Load HTML after view is in window hierarchy (WKWebView needs this)
        if(floatH5.rawHTML) {
            [floatH5 loadHTMLString:floatH5.rawHTML baseURL:[NSURL URLWithString:@"https://localhost/"]];
        }
    }
    
    if(show)
    {
        [floatWindow addSubview:floatBtn];
        [floatWindow setHidden:NO];
        //[floatWindow makeKeyAndVisible]; //makeKeyAndVisible会影响APP本身的窗口层级,容易引发BUG
        //floatBtn.keepFront = NO; //floatWindow可能会被APP不可预料的覆盖, 如果悬浮按钮依然不能点击....
        [floatH5 setHidden:NO];
        
        static dispatch_once_t predicate;
         dispatch_once(&predicate, ^{
             //因为在makeKeyAndVisible之前就addSubView了, 所以需要加view移到前台才有响应
             [floatWindow bringSubviewToFront:floatH5];
             //第一次如果悬浮窗口全屏会遮挡按钮无响应, 重置一次前台
             [floatWindow bringSubviewToFront:floatBtn];
         });
    } else {
        [floatWindow setHidden:YES]; //floatWindow可能已经成为keyWindow, hidden之后系统会指定新的keyWindow
        [UIApplication.sharedApplication.keyWindow addSubview:floatBtn]; //floatWindow hidden之后再调用否则图标闪烁
        //floatBtn.keepFront = YES;
    }
}

void initFloatButton(void (^callback)(void))
{
    //获取窗口
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    
    //创建悬浮按钮
    FloatButton* floatBtn = [[FloatButton alloc] init];
    [H5GGRuntimeCoordinator.sharedCoordinator retainFloatingButton:floatBtn];

    if(H5GGRuntimeHasMode(H5GGRuntimeModeDylib)) {
        CGRect buttonFrame = floatBtn.frame;
        buttonFrame.origin.x = 35.0;
        buttonFrame.origin.y = CGRectGetMidY(window.bounds) - CGRectGetHeight(buttonFrame) / 2.0;
        floatBtn.frame = buttonFrame;
    }
    
    NSData* customIcon = H5GGEmbeddedCustomIcon();
    UIImage* iconImage = customIcon ? [[UIImage alloc] initWithData:customIcon] : nil;
    if(!iconImage) {
        NSString* bundledIcon = [NSBundle.mainBundle pathForResource:@"H5Icon" ofType:@"png"];
        if(bundledIcon) iconImage = [UIImage imageWithContentsOfFile:bundledIcon];
    }
    if(!iconImage) {
        NSData* iconData = [[NSData alloc] initWithBytes:gIconData length:gIconSize];
        iconImage = [[UIImage alloc] initWithData:iconData];
    }
    
    //设置悬浮按钮图标
    [floatBtn setIcon:iconImage];
    
    //设置悬浮按钮点击处理, 点击时反转显示隐藏的状态
    [floatBtn setAction:callback];
    
    //将悬浮按钮添加到窗口上
    [window addSubview:floatBtn];
}

void initload()
{
    H5GGRuntimeCoordinator* runtime = H5GGRuntimeCoordinator.sharedCoordinator;
    if([runtime hasMode:H5GGRuntimeModeStandalone])
    {
        [runtime retainApplicationWindow:UIApplication.sharedApplication.keyWindow];
    }
    
    NSString* app_package = [[NSBundle mainBundle] bundleIdentifier];
    if(app_package.hash==0xa8f1ac9df8696cea || app_package.hash==0xa8f1aca37f747aea)
        return; //UIWebView冲突
    
    // Always create the floating button so the user has something to tap
    initFloatButton(^(void) {
        if(PGVSharedData->customButtonAction) {
            [runtime.floatingMenu evalJS:@"if(window.h5gg_onButtonClick)h5gg_onButtonClick();"];
        } else {
            UIWindow* floatWindow = runtime.floatingWindow;
            bool show = floatWindow ? floatWindow.isHidden : YES;
            NSLog(@"ButtonShowWindow=%d", show);
            showFloatWindow(show);
        }
    });
    
    if([runtime hasMode:H5GGRuntimeModeStandalone]) {
        // In standalone mode, also trigger menu directly
        showFloatWindow(true);
        
        if(NSBundle.mainBundle.infoDictionary[@"UIRequiresFullScreen"])
        {
            if(!PGVSharedData->enable)
                [TopShow alert:Localized(@"悬浮模块加载失败") message:Localized(@"请检查你的越狱基板是否安装并启用, 也可能被其他插件禁用或干扰!")];
        }
    }
}


//初始化函数, 插件加载后系统自动调用
static void __attribute__((constructor)) _init_()
{
    struct dl_info di={0};
    dladdr((void*)_init_, &di);

    NSString* app_path = [[NSBundle mainBundle] bundlePath];
    NSString* app_package = [[NSBundle mainBundle] bundleIdentifier];
    H5GGRuntimeMode modes = H5GGRuntimeModeNone;
    
    NSLog(@"H5GGLoad:%d %d %d %d hash:%lu app_path=%@\nfirst module header=%p slide=%p current=%p\nmodule=%s\n",
          getuid(), geteuid(), getgid(), getegid(), (unsigned long)[app_package hash], app_path,
          _dyld_get_image_header(0), (void*)_dyld_get_image_vmaddr_slide(0),
          di.dli_fbase, di.dli_fname);
    
    //判断是APP程序加载插件(排除后台程序和APP扩展)
    if(![app_path hasSuffix:@".app"]) return;
    
    task_port_t task=0;
    if(task_for_pid(mach_task_self(), getpid(), &task)==KERN_SUCCESS) {
        modes |= H5GGRuntimeModeStandalone;
        if(task != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), task);
        }
    }

    
    if([app_package isEqualToString:@"com.test.h5gg"])
        modes |= H5GGRuntimeModeTestApp;
    
    if([[NSString stringWithUTF8String:di.dli_fname] hasSuffix:@".dylib"])
        modes |= H5GGRuntimeModeDylib;
    
    if([app_path containsString:@"/var/"]||[app_path containsString:@"/Application/"])
        modes |= H5GGRuntimeModeCommonApp;
    
    if((modes & H5GGRuntimeModeTestApp) && (modes & H5GGRuntimeModeDylib))
        return;
    
    //判断是普通版还是跨进程版, 防止混用
    if((modes & H5GGRuntimeModeStandalone) && (modes & H5GGRuntimeModeDylib))
    {
        NSString* dylibPath = [NSString stringWithUTF8String:di.dli_fname];
        NSString* plistPath = [[dylibPath stringByDeletingPathExtension]
            stringByAppendingPathExtension:@"plist"];
        
        NSDictionary* plist = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
        NSLog(@"plist=%@\n%@\n%@\n%@", plistPath, plist, plist[@"Filter"], plist[@"Filter"][@"Bundles"]);
        if(plist) {
            for(NSString* bundleId in plist[@"Filter"][@"Bundles"]) {
                if([bundleId isEqualToString:app_package]) {
                    modes |= H5GGRuntimeModeSystemApp;
                    break;
                }
            }
            
            if(!(modes & H5GGRuntimeModeSystemApp)) for(NSString* bundleId in plist[@"Filter"][@"Bundles"]) {
                NSBundle* test = [NSBundle bundleWithIdentifier:bundleId];
                NSLog(@"filter bundle id=%@, %@, %d", bundleId, test, [test isLoaded]);
                if(test && ![bundleId isEqualToString:app_package]) {
                    NSLog(@"found common bundle inject! this deb is not a crossproc version!");
                    return;
                }
            }

        }
    }
    
    H5GGRuntimeCoordinator* runtime = H5GGRuntimeCoordinator.sharedCoordinator;
    [runtime configureModes:modes];

    if((modes & H5GGRuntimeModeStandalone) || (modes & H5GGRuntimeModeCommonApp)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [runtime startWhenReady:^BOOL {
                return UIApplication.sharedApplication &&
                    UIApplication.sharedApplication.keyWindow;
            } interval:0.5 initialize:^{
                initload();
            }];
        });
    }
}
