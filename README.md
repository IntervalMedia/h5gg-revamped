# H5GG-Revamped v8.0

Fully revamped and actively maintained. Complete rewrite of the original H5GG codebase after years of inactivity. All code modernized for current iOS versions.

**Join the [Discord](https://discord.gg/CnwCJC5jak)** -- please introduce yourself when you join!

iOS mod engine with JavaScript APIs and HTML5 UI. Think GameGuardian for iOS but with custom HTML interfaces and a dylib plugin system.

---

### What changed in v8.0

- **WKWebView** -- old UIWebView replaced with WKWebView. JS bridge uses `WKScriptMessageHandler` instead of JavaScriptCore hooking.
- **Build target** -- now builds for iOS 15.0+ with C++17. No more hardcoded Xcode paths.
- **Code split** -- all the old monolithic .h files that had implementations inside them were split into proper .h/.m/.mm files. Nullability annotations and generics added.
- **C++17 memory engine** -- scanner uses templates and structured bindings instead of the old C++11 ext/hash_map.
- **Actively maintained** -- issues and PRs welcome.

### Features

- memory search/read/write [APIs](/examples-JavaScript/) from JavaScript
- fully custom HTML5 UI
- load scripts (.js or .html) from local storage or network
- dylib plugin system ([demo](/pluginDemo/customAlert))
- auto pointer chain search ([example](/examples-JavaScript/AutoSearchPointerChains.js))
- one-click dylib generation
- [h5frida](/examples-h5frida) plugin for C/C++/ObjC hooking

## Running modes

1. [inject H5GG.dylib into ipa for non-jailbroken devices](/packages/)
2. [tweak (deb) auto-loads into all apps for jailbroken devices](/packages/)
3. [standalone app for jailbroken devices (iPad SlideOver+SplitView compatible)](/appstand/packages/)
4. [Float On Screen for jailbroken devices (iOS 15+ tested)](/globalview/packages/)

Also a [TrollStore version](/appstand/packages/).

## h5frida plugin

1. invoke C/C++/Objective-C functions (non-jailbroken)
2. hook Objective-C methods (non-jailbroken)
3. hook C/C++ exported functions (non-jailbroken)
4. hook C/C++ internal functions/instructions (jailbroken only)
5. MSHookFunction for C/C++ (non-jailbroken)
6. code-patch with bytes dynamically (non-jailbroken)

## Screenshots

![text](/pictures/h5gg1.png)
![text](/pictures/h5gg2.png)
![text](/pictures/h5gg3.png)
![text](/pictures/h5gg4.PNG)

## Designing HTML menu UI

Use any text editor. Previously EasyHtml on the AppStore was popular but may need sideloading now.

![text](/pictures/easyhtml.png)

## Debugging JS/HTML via macOS Safari

Requires `get-task-allow` entitlement (jailbroken or signed with Developer Certificate).

![text](/pictures/macos.png)

## Dependencies (GlobalView / Float On Screen)

- [BackgrounderAction2](https://github.com/akusio): libH5GG.B.dylib (jp.akusio.backgrounderaction13) for iOS 15+
- [libAPAppView](https://github.com/Baw-Appie/libAPAppView): libH5GG.A.dylib (com.rpgfarm.libapappview) for iOS 15+

## [JavaScript API docs](/h5gg-js-doc-en.js)

Free and open source.
