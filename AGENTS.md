# Repository Guidelines

## Project Structure & Module Organization

The root Theos tweak builds `H5GG.dylib`. Its primary entry point is `Tweak.mm`; memory, process, and UI behavior live in files such as `MemScan.mm`, `crossproc.mm`, `FloatMenu.mm`, and paired `.h` interfaces. `globalview/` packages the floating-on-screen variant, while `appstand/` packages the standalone/TrollStore app. The Xcode source for that app is in `h5ggapp-src/`. Keep JavaScript, HTML, and Frida examples in their respective `examples-JavaScript/`, `examples-HTML5/`, and `examples-h5frida/` directories. `pluginDemo/` contains independently buildable plugin examples.

## Build, Test, and Development Commands

Install and configure Theos first; builds require `THEOS` and iOS SDK support. From the repository root:

- `./build.sh all` builds normal, rootless, and roothide packages and collects them in `packages/release-artifacts/`.
- `./build.sh normal` (or `rootless`, `roothide`) builds one jailbreak variant.
- `make clean package FINALPACKAGE=1` creates the rootful tweak package directly.
- `make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless` builds the rootless package.
- `make -C globalview clean package` or `make -C appstand clean package` builds those distribution variants.

There is no automated test target. Validate changes by building the affected package and exercising the relevant UI/API on a compatible iOS 15+ device or test environment.

## Coding Style & Naming Conventions

Follow the surrounding style: four-space indentation, braces on the same line as control statements, and Objective-C method names in lower camel case. Use `PascalCase` for Objective-C classes (`ContextHostManager`) and meaningful paired names for interfaces (`FloatWindow.h` / `FloatWindow.m`). Keep Objective-C++ code in `.mm`, pure Objective-C in `.m`, and C/C++ interfaces in `.h`. Preserve ARC and C++17 compiler settings; avoid unrelated reformatting or regenerated binary/package changes.

## Commit & Pull Request Guidelines

Recent commits use brief imperative subjects, commonly scoped by intent: `Fix manual release workflow yaml`, `Add multi-variant Theos build system`, or `fix abort() crash`. Keep commits focused and describe user-visible behavior or build variants affected. PRs should explain the change, list the package(s) built and device/runtime validation performed, link related issues, and include screenshots or short recordings for UI changes. Do not commit temporary `.deb` artifacts unless the release update explicitly requires them.

## Security & Configuration

Do not commit signing credentials, device addresses, or local Theos paths. Treat entitlements and package control files as release-sensitive: review `app.entitlements`, `control`, and variant packaging changes carefully.
