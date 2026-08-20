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
Tweak.mm — process bootstrap and floating-window orchestration
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
          ├── MemoryResults / MemoryFilter / MemoryValue
          ├── MemoryPage / MemoryDump
          ├── FileNames — filename policy
          ├── crossproc — process and Mach-O discovery
          ├── NSUserDefaults / Documents — persistence
          ├── dlopen + H5GGPluginRPC — native plugin transport
          └── makeDYLIB / DylibTemplate / ldid — customized dylib generation
```

## Modules and responsibilities

### Distribution adapters

The root `Makefile` builds `H5GG.dylib`. `appstand/` and `globalview/` adapt the
runtime for different launch and presentation environments. Package layout,
signing, path translation, and host integration belong in these adapters;
memory-search behavior does not.

The compile-time variant (`normal`, `rootless`, or `roothide`) is a working
build-time seam. Each root and GlobalView compile receives exactly one
`H5GG_BUILD_*` definition. Content-level verification of the produced packages
is still required.

### Bootstrap and presentation

`Tweak.mm` detects the run mode, creates the floating button/window, owns the
application-side `GVData` mapping, and connects UI actions to the web view.
`FloatButton`, `FloatWindow`, `TopShow`, `ModalShow`, and `makeWindow` provide
UIKit behavior. `ModalRequestQueue` provides the platform-independent FIFO
lifecycle for synchronous modal requests.

The floating button preserves its initial position when its first window frame
arrives. In injected dylib mode its default origin is 35 points from the left,
with its center at the vertical midpoint of the active window.

This area still relies on process-wide globals and timers. The intended deeper
module is a runtime coordinator with an explicit lifecycle interface:

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

Asynchronous file-picker calls capture their own numeric call ID. Selection and
cancellation settle that ID once; later bridge calls do not replace it.

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
- `MemoryFilter` performs typed result refinement through a reader callback;
- `MemoryPage` and `MemoryDump` implement bounded raw-read workflows through
  reader callbacks;
- `FileNames` contains filename confinement and script-extension policy;
- `BridgeMethods` owns the callable native method inventory and argument rules;
- `DylibTemplate` performs fixed-size template replacement.

The façade owns one `MemorySession` and still implements plugin, persistence,
freezer, file, and dump orchestration. Proposed deeper modules remain:

- `ScriptStore`: owns the Documents root, atomic I/O, and filename policy;
- `PluginLoader`: owns loaded handles and the WK RPC contract;
- `DylibBuilder`: owns validation, replacement, output, and signing.

These are proposed internal modules, not new JavaScript concepts.

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

The read interfaces are deliberately distinct:

- `JJReadMemory` performs a typed read whose validated value type determines
  byte width;
- `JJReadBytes` performs a raw read with an explicit byte length;
- `MemoryPage` and `MemoryDump` layer partial-read behavior on a reader
  callback so they can be host-tested without a Mach task.

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
shares `GVData` with the application through a remapped page. The struct layout
is a cross-process binary interface, but it currently has no magic, schema
version, total size, or capability fields. Its 512 KiB inline image buffer also
makes every mapping large.

The layout must not change until both readers validate a versioned header or a
compatible migration strategy is implemented.

## Data ownership

| State | Current owner | Required lifetime |
|---|---|---|
| Target PID/task port | `TargetProcess` inside `MemorySession` | One selected process |
| Search engine/type/state | `MemorySession` | One target and search session |
| Regions/results/snapshot | `JJMemoryEngine` and `Result` | One memory session |
| Floating UI objects | Globals in `Tweak.mm` | Injected runtime |
| Current bridge invocation | `FloatMenu` | Synchronous native dispatch |
| Deferred bridge call ID | Operation callback closure | Until that Promise settles |
| Bookmarks/history | `NSUserDefaults` | App installation |
| Frozen values | `h5ggEngine` and weak-capturing timer | One target process |
| Scripts/dumps/log | Documents directory | App installation |
| Plugin handles | `h5ggEngine` | Engine lifetime |
| GlobalView state | Remapped `GVData` | Host/application pair |

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
8. Do not change `GVData` layout without version negotiation.
9. Package variants differ only in platform paths and bootstrap integration.

## Verification seams

Run the host suite with:

```sh
bash tests/run_tests.sh
```

The suite exercises the same internal seams used by production target/session
ownership, modal request serialization, grouped/ranged search parsing and
matching, results, raw reads, dumps, filenames, bridge schemas, and dylib
templates. It also checks JavaScript reference coverage and variant compile
definitions. The suite is not yet a required CI job.

Device tests remain necessary for Mach ports, `vm_remap`, protected writes,
SpringBoard hosting, UIKit lifecycle/orientation, generated-dylib loading, and
all three jailbreak package layouts. Record those results in
[validation.md](validation.md).
