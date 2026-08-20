# H5GG-Revamped v8.0 - DEV BRANCH (Work in progress)

Fully revamped and actively maintained. Complete rewrite of the original H5GG codebase after years of inactivity. All code modernized for current iOS versions.

**Join the [Discord](https://discord.gg/CnwCJC5jak)** -- please introduce yourself when you join!

iOS mod engine with JavaScript APIs and HTML5 UI. Think GameGuardian for iOS but with custom HTML interfaces and a dylib plugin system.

## Project design and status

New GUI for new features implemented 
New javascript API for new h5gg engine capabilities ([API DOCS](/docs/javascript-api.md)) 

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

- memory search/read/write with a new ([API DOCS](/docs/javascript-api.md)) written in JavaScript
- fully custom HTML5 UI
- load scripts (.js or .html) from local storage or network
- JSON-RPC dylib plugin system ([demo](/pluginDemo/customAlert))

## Build (Theos)

- Minimum deployment target is iOS 15.0. The root, standalone, and GlobalView
  builds share this baseline.
- Run the host verification suite:
  - `make test`
- Compile the rootful tweak without packaging:
  - `make clean all`
- Build one release package directly through the Makefile:
  - `make package-normal FINALPACKAGE=1`
  - `make package-rootless FINALPACKAGE=1`
  - `make package-roothide FINALPACKAGE=1`
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
