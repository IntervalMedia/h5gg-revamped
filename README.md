# H5GG-Revamped v8.1 - DEV BRANCH (Work in progress)

H5GG-Revamped is an iOS memory inspection and modification runtime with
Promise-based JavaScript APIs, custom HTML interfaces, and a dylib plugin
system. It supports injected, standalone, and floating GlobalView modes on
iOS 15 or newer.

Join the [Discord](https://discord.gg/CnwCJC5jak) and introduce yourself when
you arrive.

## Project design and status

- [Architecture baseline](docs/architecture.md)
- [Codebase review and issue register](docs/codebase-review.md)
- [Stabilization and feature roadmap](docs/roadmap.md)
- [Phase 2 feature contracts and limits](docs/phase-2-features.md)
- [Validation matrix](docs/validation.md)
- [JavaScript API reference](docs/javascript-api.md)

---

### What changed in v8.1

- **Reliable HTML interface** -- the English and Chinese menus now share tested search overlays, result actions, script editing, memory viewing, and window controls.
- **Jailbreak-aware paths** -- application paths are normalized for rootful, rootless, and roothide layouts before process matching.
- **Consistent release metadata** -- the runtime, Debian packages, standalone hosts, Xcode project, and release workflow now identify version 8.1.
- **Smaller source tree** -- obsolete h5frida examples, binaries, and the nested Dobby snapshot are no longer tracked or scanned by `make test`.
- **Current examples and docs** -- the HTML examples use the Promise-based bridge and the JavaScript reference is checked against the production method inventory.

### v8 foundation

- **WKWebView** -- UIWebView was replaced with WKWebView. The JavaScript bridge uses `WKScriptMessageHandler` instead of JavaScriptCore hooking.
- **Build target** -- all targets build for iOS 15.0+ with C++17 and without hardcoded Xcode paths.
- **Code split** -- implementation was moved out of monolithic headers into paired `.h`, `.m`, and `.mm` files, with nullability annotations and generics.
- **C++17 memory engine** -- the scanner uses templates and structured bindings instead of the old C++11 `ext/hash_map` implementation.

### Features

- memory search, read, and write through the [JavaScript API](docs/javascript-api.md)
- fully custom HTML5 UI
- load scripts (.js or .html) from local storage or network
- JSON-RPC dylib plugin system ([demo](/pluginDemo/customAlert))
- auto pointer chain search ([example](/examples-JavaScript/AutoSearchPointerChains.js))
- one-click dylib generation

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
