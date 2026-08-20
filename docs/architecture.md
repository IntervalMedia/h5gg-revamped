# H5GG architecture

Status: current implementation baseline verified on 2026-08-20. Active defects
and debt are tracked in [codebase-review.md](codebase-review.md); implementation
status is tracked in [roadmap.md](roadmap.md).

## System purpose

H5GG is an iOS memory-inspection and modification runtime with an HTML/JavaScript
user interface. The same core dylib is used in three environments:

1. injected into an application;
2. embedded in a standalone/TrollStore application;
3. hosted as a SpringBoard-level floating view.

The public product interface is the Promise-based `window.h5gg` JavaScript
object under WKWebView. Compatibility at that interface matters more than the
shape of the Objective-C implementation behind it.

## Runtime map

```text
Distribution adapters
├── rootful/rootless/roothide tweak package
├── standalone/TrollStore app
└── SpringBoard GlobalView host
          │
          ▼
Tweak.mm — process/environment discovery
          │
          ▼
RuntimeCoordinator — run modes, readiness, timers, and floating UI ownership
          │
          ├── FloatButton / FloatWindow / TopShow / ModalShow
          │
          ▼
FloatMenu — WKWebView and allowlisted JavaScript message dispatch
          │
          ├── BridgeMethods — names, selectors, and argument schemas
          │
          ▼
h5ggEngine — JavaScript-facing use-case coordination
          │
          ├── TargetProcess / MemorySession — target and search lifetime
          ├── JJMemoryEngine — scan and target-memory operations
          ├── MemoryResults / MemoryFilter / MemoryValue / MemoryReader
          ├── MemoryPage / MemoryDump / DumpController / PointerSearch
          ├── FreezerController / FilePickerRequest — deferred lifecycle ownership
          ├── ScriptStore / FileNames — confined script persistence and policy
          ├── crossproc — process and Mach-O discovery
          ├── PreferencesStore / NSUserDefaults — histories and bookmarks
          ├── PluginLoader / H5GGPluginRPC — native plugin transport
          └── DylibBuilder / makeDYLIB / ldid — customized dylib generation
```

## Modules and responsibilities

### Distribution adapters

The root `Makefile` builds `H5GG.dylib`. `appstand/` and `globalview/` adapt the
runtime for different launch and presentation environments. Package layout,
signing, path translation, and host integration belong in these adapters;
memory-search behavior does not.

The compile-time variant (`normal`, `rootless`, or `roothide`) is a working
build-time seam. Each root and GlobalView compile receives exactly one
`H5GG_BUILD_*` definition. Each package build starts a fresh top-level Theos
stage, then `check_package_contents.sh` validates control metadata, the
variant-specific install root, dylib/plist pairing, executable maintainer
script, valid filter plist, and both Mach-O slices before publication.

### Bootstrap and presentation

`Tweak.mm` detects the run mode and maps the application side of the GlobalView
protocol. `RuntimeCoordinator` owns the run-mode state, readiness and
GlobalView timers, application/floating windows, button, menu, and engine. It
starts initialization once after a key window becomes available and prevents
duplicate GlobalView monitors.
`FloatButton`, `FloatWindow`, `TopShow`, `ModalShow`, and `makeWindow` provide
UIKit behavior. `ModalRequestQueue` provides the platform-independent FIFO
lifecycle for synchronous modal requests.

The floating button preserves its initial position when its first window frame
arrives. In injected dylib mode its default origin is 35 points from the left,
with its center at the vertical midpoint of the active window.

The coordinator exposes this lifecycle through one interface used by the tweak
and its Foundation host tests:

```text
not started → waiting for application window → button ready → menu ready
                                                  │
                                                  └→ globally hosted
```

`ModalShow` adapts that queue to UIKit. Every alert, confirmation, or prompt has
its own completion state; only the active request is presented, completion is
accepted once, and cancelling an abandoned request promotes the next request.
Main-thread callers continue servicing their run loop while queued or waiting,
while background callers use the same queue's condition-variable seam.

### Web interface

`FloatMenu` owns the `WKWebView`, installs `window.h5gg`, receives
`WKScriptMessage` values, invokes native operations, and settles JavaScript
Promises.

Its external interface consists of:

- documented `window.h5gg` method names;
- argument and result schemas;
- Promise completion and error behavior;
- rules for file, network, and plugin access.

The complete frontend contract, including global window controls, callbacks,
injected values, schemas, and examples, is defined in
[javascript-api.md](javascript-api.md).

`BridgeMethods` is the allowed-method seam used for JavaScript injection and
native lookup. It prevents arbitrary selector derivation and validates argument
counts, JSON value kinds, integer requirements, numeric ranges, and enumerated
numeric values before `NSInvocation`. The method inventory and native argument
table in `javascript-api.md` are generated and checked by linking against that
same production schema; operation semantics and examples remain curated prose.

`FilePickerRequest` captures the originating menu's numeric call ID, normalizes
and deduplicates document types, and accepts selection or cancellation exactly
once. The UIKit picker is only the presentation adapter, so later bridge calls
or a different current menu cannot receive the result.

### Engine façade

`h5ggEngine` is the compatibility adapter for JavaScript. It translates values
and coordinates process selection, searches, reads/writes, persistence,
freezing, plugins, files, dumps, and dylib generation.

Several internal implementation modules now provide locality:

- `MemoryValue` owns H5GG type-name mapping and validates values, addresses,
  non-negative float tolerance, grouped/ranged numeric search expressions, and
  masked-hex text; it also formats typed result values;
- `TargetProcess` is the move-only owner of an acquired non-self Mach task port;
- `MemorySession` owns the target, memory engine, and façade-visible search
  metadata as one replaceable unit;
- `MemoryResults` owns result regions, counts, and type-vector invariants;
- `MemoryReader` defines one partial-byte primitive with exact and typed helpers;
  `JJMemoryEngine` is the Mach adapter, while buffer/callback adapters drive
  host verification;
- `MemoryFilter`, `MemoryPage`, and `MemoryDump` implement refinement and
  bounded raw-read workflows through that same interface;
- `PointerSearch` performs exact aligned 64-bit matching and enforces result,
  byte, range, and chunk limits through the same reader interface; Mach region
  enumeration remains in `JJMemoryEngine`;
- `FreezerController` owns validated canonical entries, target binding,
  failure/recovery status, and exactly one repeating timer through injected
  target, writer, and scheduler adapters;
- `FilePickerRequest` owns normalized types, the originating bridge call ID,
  and thread-safe exactly-once selection/cancellation;
- `PreferencesStore` owns input/search history caps, bookmark uniqueness,
  malformed persisted-value filtering, and timestamp creation over an injected
  `NSUserDefaults` adapter;
- `DumpController` owns request/range/path validation, one-running-job state,
  progress, cancellation, partial-file cleanup, target-reader lease release,
  and deferred completion; `MemoryDump` remains its streaming implementation;
- `ScriptStore` owns the Documents root, confined regular-file access, strict
  UTF-8 and size validation, atomic writes, deterministic listing, and errors;
- `FileNames` contains the shared filename and script-extension policy;
- `TextEncoding` contains strict UTF-8 validation shared by stored scripts and
  embedded menus;
- `BridgeMethods` owns the callable native method inventory and argument rules;
- `PluginLoader` owns resolved dylib images, legacy-object compatibility,
  opaque WK handles, JSON RPC validation, invocation, and error conversion;
- `DylibBuilder` owns regular-file input, bounded payload validation, fixed-size
  replacement, temporary output, signing, cleanup, and atomic publication;
- `DylibTemplate` is the builder's fixed-size replacement helper.
- `RuntimeCoordinator` owns bootstrap modes, exactly-once UI readiness,
  monitoring timers, and retained floating UI resources;
- `GVProtocol` owns the fixed-width GlobalView header, capability negotiation,
  compatibility checks, and bounded single-slot image transfer.

The façade owns one `MemorySession`, `ScriptStore`, `PluginLoader`,
`FreezerController`, `PreferencesStore`, and `DumpController`. Its remaining
role is JavaScript compatibility, argument/result translation, and routing
search/process use cases to their owners. The `makeDYLIB` adapter supplies UIKit
image validation, the embedded templates, and the linked `ldid` signer to
`DylibBuilder`.

These are internal modules, not new JavaScript concepts.

### Memory engine

`JJMemoryEngine` owns a Mach task port, enumerated regions, current `Result`,
result types, and value snapshots. It supports numeric search, nearby search,
change refinement, hex search, pointer search, typed read/write, raw reads, and
result enumeration.

The enforced result invariant is:

```text
for every result:
address = region_base + slides[i]
types is either empty for the whole region, or types.size == slides.size
Result.count == the sum of every region's slides.size
snapshot entries use the same type as the corresponding result
```

`Result` centralizes add, replace, removal, recounting, and invariant checks.
`MemoryFilter` and masked-hex refinement mutate results through that module.
Host tests cover typed/untyped regions, counts, filters, and hex refinement.

`JJMemoryReader::readBytes` is the partial-read primitive. Its implementation
clamps adapter results to the requested length; `readExact` requires full
completion, and `readValue` validates the H5GG type before deriving its width.
Engine snapshots, change refinement, numeric/hex result filtering, façade
typed/raw reads, memory pages, dumps, and pointer matching all cross this
interface. Numeric/hex bulk-scan mapping and region enumeration remain
Mach-specific operations.

Mach region enumeration and protected target-memory operations still require a
device.

### Process and Mach-O discovery

`crossproc` lists processes, reads dyld image metadata, and calculates mapped
Mach-O sizes. It is an adapter over private and low-level platform interfaces.
Target selection is coordinated by `h5ggEngine`: it acquires a new port and
constructs a complete `MemorySession` before swapping state, then clears
target-bound frozen values. Destruction releases the old engine first and its
owned non-self port exactly once; the self task port is represented as borrowed.

### GlobalView

`globalview/` runs in SpringBoard, hosts the standalone application view, and
shares `GVData` with the application through a remapped page. `GVData` begins
with a fixed-width header containing magic, schema version, header size, total
size, and explicit capability bits. Both processes validate that header before
enabling the mapping. A new client resolves `SetGlobalViewV2`; a missing symbol
or incompatible header disables hosting instead of interpreting another layout.

The 512 KiB image payload is no longer inline in `GVData`. It uses a separately
mapped `GVImageTransfer` with its own validated header, fixed upper bound, and
atomic idle/writing/ready state. This keeps the frequently accessed state
mapping small while retaining a bounded icon handoff.

## Data ownership

| State | Current owner | Required lifetime |
|---|---|---|
| Target PID/task port | `TargetProcess` inside `MemorySession` | One selected process |
| Search engine/type/state | `MemorySession` | One target and search session |
| Regions/results/snapshot | `JJMemoryEngine` and `Result` | One memory session |
| Runtime modes, timers, and floating UI objects | `RuntimeCoordinator` | Injected runtime |
| Current bridge invocation | `FloatMenu` | Synchronous native dispatch |
| Deferred file-picker call ID | `FilePickerRequest` | Until selection/cancellation settles once |
| Bookmarks/history | `PreferencesStore` over `NSUserDefaults` | App installation |
| Frozen values and timer | `FreezerController` | One selected target process |
| Scripts | `ScriptStore` over the Documents directory | App installation |
| Active dump job and status | `DumpController` with one target-reader lease | Until completion/cancellation settles |
| Dump/log files | Documents directory | App installation |
| Generated dylib build | `DylibBuilder` request | One atomic build attempt |
| Plugin RPC objects/handles | `PluginLoader` | Loader lifetime |
| Dynamically loaded plugin images | `PluginLoader` production adapter | Process lifetime; Objective-C images are not unloaded |
| GlobalView state | Validated remapped `GVData` | Host/application pair |
| GlobalView image handoff | Validated remapped `GVImageTransfer` | One pending bounded payload |

Changing the target process atomically replaces the task port and memory engine,
clears search state and target-bound frozen values, and releases the prior port.
An in-flight dump retains its own task-port right.

## Compatibility rules

1. Keep `window.h5gg` method names stable or version them explicitly.
2. JavaScript methods return Promises in the WKWebView implementation.
3. Every Promise settles once, including cancellation and native failure.
4. Addresses use unsigned 64-bit parsing with complete input consumption and
   checked ranges.
5. Numeric and byte results preserve the `Result` invariant.
6. A memory session never survives a target-process change.
7. WK plugins exchange only JSON-compatible values through `H5GGPluginRPC`;
   native object compatibility is limited to legacy JavaScriptCore callers.
8. Change `GVData` only by introducing a negotiated protocol version and
   capability set; incompatible peers must fail closed.
9. Package variants differ only in platform paths and bootstrap integration.

## Verification seams

Run the host suite with:

```sh
bash tests/run_tests.sh
```

The suite exercises the same internal seams used by production target/session
ownership, modal request serialization, grouped/ranged search parsing and
matching, results, raw reads, dump streaming/orchestration, pointer matching,
freezer and file-picker lifecycle, filenames, script/preference persistence, bridge schemas, plugin
loading/RPC, dylib building, runtime lifecycle, and the GlobalView binary contract. Raw,
exact, typed, partial, filter, page, dump, and pointer reads use buffer/callback
adapters to the production reader interface. Freezer tests inject target,
writer, and scheduler adapters; picker tests exercise request IDs and racing
completion through the production request interface. Dump tests inject reader
leases and executors while using real temporary files. The plugin contract test
uses injected image/class adapters with macOS Foundation; the dylib integration
uses the production builder interface with real temporary files and host
`ldid`.
The suite also checks JavaScript reference coverage and variant compile
definitions. Both build workflows require it before package generation.

Device tests remain necessary for Mach ports, `vm_remap`, protected writes,
SpringBoard hosting, UIKit lifecycle/orientation, generated-dylib loading, and
installation/runtime behavior of all three jailbreak package variants. Record
those results in [validation.md](validation.md).
