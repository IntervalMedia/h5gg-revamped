# Codebase review

Reviewed at `5049f71` on 2026-07-31. The working tree already contained a user
change in `Tweak.mm`; it was inspected but not modified.

## Executive finding

The v8 rewrite has a coherent direction—WKWebView, a JavaScript-facing engine
façade, a C++ memory engine, and multi-variant packaging—but it is not ready to
describe all advertised features as complete. The numeric in-process path is
the most mature. Cross-process selection, hex/filter/raw-memory features,
native plugins through the WK bridge, customized dylib generation, and package
variant selection all have blocking defects.

The immediate priority is to stabilize interfaces and add a deterministic test
harness before adding more UI features.

## Evidence and validation

- `bash -n build.sh`: passed.
- Six plist/entitlement files checked with `plutil -lint`: passed.
- A clean `make -j2` in an isolated worktree produced `H5GG.dylib` for arm64
  and arm64e.
- The build emitted only the obsolete `-multiply_defined` linker warning.
- Dry runs for normal, rootless, and roothide contained none of the documented
  `H5GG_BUILD_*` compiler definitions.
- No automated test target exists, so runtime findings below are static unless
  explicitly described as build evidence.
- Device behavior was not validated.

## Issue register

Severity meanings:

- **P0**: corrupts core behavior, exposes an unsafe capability, or blocks a
  primary advertised mode;
- **P1**: advertised feature is broken or lifecycle behavior is unreliable;
- **P2**: maintainability, performance, packaging, or documentation debt.

### P0 — Fix before feature work

#### H5-001: Target-process selection leaves the scanner on a null task port

`setTargetProc` clears results while `_targetport` is `MACH_PORT_NULL`, which
constructs the replacement `JJMemoryEngine`; it then stores the successful task
port without rebuilding the engine
([h5gg.mm](../h5gg.mm#L92), [h5gg.mm](../h5gg.mm#L127)).

Impact: standalone cross-process reads/searches can report successful process
selection while all memory operations use the wrong port.

Acceptance: acquire the new port first; atomically create a new session for it;
only then release the old port. Failure must preserve or explicitly clear the
old target according to a documented rule.

#### H5-002: Raw reads pass byte counts to a typed-read interface

`dumpMemory` and `readBytes` pass lengths such as 4096 or 8 as the `type`
argument to `JJReadMemory`; that method accepts only `JJ_Search_Type` values and
maps them back to type widths
([h5gg.mm](../h5gg.mm#L810), [h5gg.mm](../h5gg.mm#L867),
[MemScan.mm](../MemScan.mm#L670)).

Impact: dumps usually fail immediately; the memory viewer reads the wrong
number of bytes and can format uninitialized stack data.

Acceptance: add a bounded raw-byte read interface, return the actual byte count,
and cover zero, partial-page, unreadable-page, and maximum-size cases.

#### H5-003: JavaScript messages can derive arbitrary Objective-C selectors

The bridge advertises a method list in JavaScript, but native dispatch falls
back to constructing selectors from any `method` string supplied in a posted
message
([FloatMenu.mm](../FloatMenu.mm#L317),
[FloatMenu.mm](../FloatMenu.mm#L374), [FloatMenu.mm](../FloatMenu.mm#L431)).

Impact: any loaded page can probe or invoke selectors outside the intended
`window.h5gg` interface. This is especially dangerous because pages may be
loaded from local files or the network and the engine exposes memory, file, and
plugin operations.

Acceptance: reject every method not in one native allowlist; validate argument
count/types; return structured errors; add negative dispatch tests.

#### H5-004: Memory result invariants are violated by filter/hex paths

`JJFilterResults` parses most enum values as floats due to ordinal comparisons,
supports greater/less only for signed integers, indexes `region->types[i]` even
when the vector is empty, and never updates `Result.count`
([MemScan.mm](../MemScan.mm#L814)).

`JJScanHexMemory` scans `regions`, but a fresh engine has no enumerated regions.
The façade creates a fresh engine for repeat hex searches without deleting the
old one
([MemScan.mm](../MemScan.mm#L329), [h5gg.mm](../h5gg.mm#L772)).

Impact: search-within-results can crash or return inconsistent counts; hex
search commonly returns no results and leaks a memory engine on subsequent use.

Acceptance: centralize region enumeration, preserve the documented result
invariant after every mutation, validate hex syntax, define numeric-to-byte
refinement behavior, and test all value types and filter modes.

#### H5-005: Build variants do not receive their advertised compile definitions

The Makefiles assign `*_ADDITIONAL_CCFLAGS`, but Theos dry runs for all three
schemes include no `H5GG_BUILD_NORMAL`, `H5GG_BUILD_ROOTLESS`, or
`H5GG_BUILD_ROOTHIDE` definition
([Makefile](../Makefile#L23),
[globalview/Makefile](../globalview/Makefile#L19)).

Impact: roothide/rootless source branches and path handling are not selected,
even though `build.sh` publishes separately named artifacts.

Acceptance: each scheme's compile command contains exactly one variant
definition; CI asserts this and inspects final package paths/dependencies.

### P1 — Broken or incomplete advertised capabilities

#### H5-006: WK bridge cannot return a native plugin object

`loadPlugin` returns an Objective-C instance, but bridge results are serialized
with `NSJSONSerialization`. Arbitrary plugin instances are not JSON values, so
the Promise resolves to `null`; the existing WebUDID example still treats
`loadPlugin` as synchronous
([h5gg.mm](../h5gg.mm#L600), [FloatMenu.mm](../FloatMenu.mm#L331),
[h5ggWebUDID.js](../examples-HTML5/get-device-UDID/h5ggWebUDID.js#L3)).

Acceptance: choose and document either a plugin RPC/proxy protocol that can
cross WKWebView or remove object-returning plugins from the WK interface. Update
examples and compatibility/version behavior.

#### H5-007: Customized dylib generation no longer embeds its replacement stubs

`makeDYLIB` loads `H5ICON_STUB_FILE` and `H5MENU_STUB_FILE` from the host bundle
or process working directory, but the root build neither embeds nor packages
them. Its fallback placeholder is not present in the produced dylib
([makeDYLIB.mm](../makeDYLIB.mm#L12), [Makefile](../Makefile#L22)).

Acceptance: restore compile-time embedding or package the exact stubs; verify
offset, capacity, zero-fill, output signature, and a second customization
failure in an integration test.

#### H5-008: File-picker Promises can remain pending or resolve the wrong call

Cancellation dismisses the picker without invoking the callback. `FloatMenu`
stores only one global `pendingCallId`, so overlapping calls overwrite each
other
([TopShow.m](../TopShow.m#L67), [h5gg.mm](../h5gg.mm#L573),
[FloatMenu.h](../FloatMenu.h#L18)).

Acceptance: callbacks are keyed by call ID, cancellation settles with a defined
result/error, and every completion removes its entry.

#### H5-009: Script and dump filenames are not confined to Documents

String concatenation accepts absolute-looking components and `../` traversal
for save/load/delete/dump operations
([h5gg.mm](../h5gg.mm#L834), [h5gg.mm](../h5gg.mm#L920)).

Acceptance: a single `ScriptStore` resolves standardized filenames under an
explicit root, rejects traversal/separators, handles extensions consistently,
and has temporary-directory tests.

#### H5-010: Engine and freezer lifetimes are incomplete

`h5ggEngine` owns a C++ pointer but has no `dealloc`; the repeating freezer timer
captures `self` strongly. Target changes also leave frozen target-relative
addresses active
([h5gg.h](../h5gg.h#L112), [h5gg.mm](../h5gg.mm#L697)).

Acceptance: explicit teardown deletes the memory session, invalidates timers,
and deallocates non-self task ports. Target changes clear or namespace frozen
values.

#### H5-011: GlobalView writes through immutable `NSString.UTF8String`

Both constructors turn a dylib path into an `NSString`, cast its UTF-8 buffer to
mutable memory, and overwrite the suffix with `strcpy`
([Tweak.mm](../Tweak.mm#L568),
[globalview.mm](../globalview/globalview.mm#L479)).

Impact: undefined behavior and a launch-time crash in GlobalView paths.

Acceptance: derive the plist path with NSString path operations and cover paths
with unexpected extensions.

#### H5-012: Dialog synchronization is process-global and non-reentrant

`ModalShow` uses one static semaphore for all presentations. A second dialog can
replace it while the first caller is waiting
([ModalShow.m](../ModalShow.m#L7)).

Acceptance: use per-presentation state and serialize/queue presentations; every
dismissal resolves the correct request exactly once.

#### H5-013: Floating button can jump on first layout tick and short icon data can throw

The first resize calculation divides by zero-sized `lastFrame`; `setIconWithData`
reads three bytes without checking the data length
([FloatButton.m](../FloatButton.m#L48),
[FloatButton.m](../FloatButton.m#L119)).

Acceptance: initialize the baseline before scaling and safely reject invalid or
short image data.

### P2 — Architecture, delivery, and documentation debt

#### H5-014: Core behavior has no automated tests

There is no test target despite recent changes to scanning, bridge dispatch,
packaging, and file behavior.

Acceptance: host-runnable tests cover codecs/result transforms/bridge dispatch;
CI includes package smoke assertions; device validation has a checked matrix.

#### H5-015: `h5ggEngine` and bootstrap are shallow, high-coupling modules

The engine façade owns unrelated persistence, filesystem, plugin, process, and
memory behavior. `Tweak.mm` coordinates lifecycle through global variables,
shared mutable structs, and polling timers.

Acceptance: introduce the internal modules described in
[architecture.md](architecture.md) behind the unchanged JavaScript interface.

#### H5-016: GlobalView shared memory has no version or size guard

`GVData` is used as a cross-process binary interface but has no magic/version
field and contains a 512 KiB inline image buffer
([globalview.h](../globalview/globalview.h#L4)).

Acceptance: validate a versioned header before use; move large payload transfer
behind an explicit mechanism or capability.

#### H5-017: Build/package metadata contradicts the documented platform baseline

The README says iOS 15+, the root and GlobalView targets specify iOS 15.6, the
standalone target specifies 15.0, and GlobalView's control description says it
was tested on iOS 11–14
([README.md](../README.md#L29), [Makefile](../Makefile#L3),
[appstand/Makefile](../appstand/Makefile#L5),
[globalview/control](../globalview/control#L5)).

Acceptance: select one support matrix and make targets, package metadata,
dead compatibility branches, and validation devices agree.

#### H5-018: Release artifacts and IDE user state are tracked

The repository includes generated `.deb`/`.tipa` files, prebuilt app bundles,
Xcode `xcuserdata`, large vendored binaries, and an entire nested Dobby source
tree. Tracked content is roughly 347 MB and obscures first-party review.

Acceptance: document which binaries are legally/operationally required,
checksum/version external dependencies, remove regenerated user state and
ordinary release outputs, and publish release artifacts outside source control.

#### H5-019: Documentation does not cover the expanded JavaScript interface

`h5gg-js-doc-en.js` documents the original core operations but not bookmarks,
freezing, hex/filter, scripts, dumps, bytes, histories, or Promise error
semantics. Some examples still use the pre-WK synchronous contract.

Acceptance: generate or validate docs from one native method schema and run
examples as bridge contract fixtures.

#### H5-020: Debug logging is unconditional and may expose target details

Process paths, addresses, mapped regions, values, and UI state are logged
throughout release builds while `DEBUG=0`.

Acceptance: centralize log levels, compile verbose region/value logging out of
release packages, and document the user-controlled diagnostics path.

## Positive findings

- First-party implementation files are now separated from headers.
- ARC and C++17 are applied consistently enough for the main target to compile.
- Mach-O load-command parsing includes useful bounds checks.
- Process enumeration correctly handles `realloc` failure without losing the
  original allocation.
- The WK bridge has moved the built-in UI to Promise-based calls.
- Plists and entitlements are syntactically valid.
- `build.sh` uses strict shell options, isolated artifact collection, and fails
  when expected artifacts are absent.

## Review limits

This was an overall static/design review, not an exploit audit of vendored
Frida/Dobby/ldid code. Those trees and prebuilt binaries were treated as
dependencies. Private iOS interfaces and SpringBoard hosting require device
validation on the selected support matrix.
