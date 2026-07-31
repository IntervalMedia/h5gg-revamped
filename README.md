# H5GG-Revamped v8.0 - DEV BRANCH (Work in progress)

Fully revamped and actively maintained. Complete rewrite of the original H5GG codebase after years of inactivity. All code modernized for current iOS versions.

**Join the [Discord](https://discord.gg/CnwCJC5jak)** -- please introduce yourself when you join!

iOS mod engine with JavaScript APIs and HTML5 UI. Think GameGuardian for iOS but with custom HTML interfaces and a dylib plugin system.

## Project design and status

- [Architecture baseline](docs/architecture.md)
- [Codebase review and issue register](docs/codebase-review.md)
- [Stabilization and feature roadmap](docs/roadmap.md)
- [Phase 2 feature contracts and limits](docs/phase-2-features.md)
- [Validation matrix](docs/validation.md)

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
- JSON-RPC dylib plugin system ([demo](/pluginDemo/customAlert))
- auto pointer chain search ([example](/examples-JavaScript/AutoSearchPointerChains.js))
- one-click dylib generation
- [h5frida](/examples-h5frida) plugin for C/C++/ObjC hooking

## Build (Theos)

- Minimum deployment target is iOS 15.0. The root, standalone, and GlobalView
  builds share this baseline.
- Build all jailbreak variants with compile-time flags:
  - `./build.sh all`
- Build a single variant:
  - `./build.sh normal`
  - `./build.sh rootless`
  - `./build.sh roothide`

Compile-time flags exposed to source:
- `H5GG_BUILD_NORMAL`
- `H5GG_BUILD_ROOTLESS`
- `H5GG_BUILD_ROOTHIDE`

Build outputs are collected in `packages/release-artifacts/` so CI/manual release workflows can publish all generated `.deb` files.

## Running modes

1. [inject H5GG.dylib into ipa for non-jailbroken devices](/packages/)
2. [tweak (deb) auto-loads into all apps for jailbroken devices](/packages/)
3. [standalone app for jailbroken devices (iPad SlideOver+SplitView compatible)](/appstand/packages/)
4. [Float On Screen for jailbroken devices (iOS 15+ tested)](/globalview/packages/)

## Dependencies (GlobalView / Float On Screen)

- [BackgrounderAction2](https://github.com/akusio): libH5GG.B.dylib (jp.akusio.backgrounderaction13) for iOS 15+
- [libAPAppView](https://github.com/Baw-Appie/libAPAppView): libH5GG.A.dylib (com.rpgfarm.libapappview) for iOS 15+
