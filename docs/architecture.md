# H5GG architecture

Status: design baseline from the code at `5049f71` on 2026-07-31.

This document describes the architecture that exists today and the intended
module seams to preserve while the codebase is stabilized. It is descriptive,
not a claim that every path is currently working. Known failures are tracked in
[codebase-review.md](codebase-review.md).

## System purpose

H5GG is an iOS memory-inspection and modification runtime with an HTML/JavaScript
user interface. The same core dylib is used in three environments:

1. injected into an application;
2. embedded in a standalone/TrollStore application;
3. hosted as a SpringBoard-level floating view.

The public product interface is the `window.h5gg` JavaScript object. Compatibility
at that interface matters more than the shape of the Objective-C implementation
behind it.

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
FloatMenu — WKWebView and JavaScript message bridge
          │
          ▼
h5ggEngine — JavaScript-facing use cases and process selection
          │
          ├── JJMemoryEngine — scan/result/snapshot implementation
          ├── crossproc — process and Mach-O discovery
          ├── NSUserDefaults — bookmarks and histories
          ├── Documents — scripts, logs, and memory dumps
          ├── dlopen — native plugins
          └── makeDYLIB/ldid — customized dylib generation
```

## Modules and responsibilities

### Distribution adapters

The root `Makefile` builds `H5GG.dylib`. `appstand/` and `globalview/` package
that runtime for different launch and presentation environments. These should
remain adapters: package layout, signing, path translation, and host integration
belong here; memory-search behavior does not.

The compile-time variant (`normal`, `rootless`, or `roothide`) is intended to be
a build-time seam. Each adapter should receive one explicit variant value and
resolve paths through a single variant-aware path module.

### Bootstrap and presentation

`Tweak.mm` detects the run mode, creates the floating button/window, owns the
global `GVData` mapping used by GlobalView, and connects UI actions to the web
view. `FloatButton`, `FloatWindow`, `TopShow`, `ModalShow`, and `makeWindow`
provide UIKit behavior.

This area currently relies on process-wide globals and timers. The desired
interface is a single runtime coordinator with explicit lifecycle states:

```text
not started → waiting for application window → button ready → menu ready
                                                  │
                                                  └→ globally hosted
```

Callers should not need to know which globals or timers implement those states.

### Web interface

`FloatMenu` owns the `WKWebView`, installs `window.h5gg`, receives
`WKScriptMessage` values, invokes native operations, and resolves JavaScript
Promises.

Its external interface consists of:

- the documented `window.h5gg` method names;
- argument and result schemas;
- Promise completion and error behavior;
- rules for file, network, and plugin access.

The allowed method table is the security seam. JavaScript must not be able to
derive arbitrary Objective-C selectors.

### Engine façade

`h5ggEngine` translates strings and JavaScript values into native types and
coordinates process selection, searches, reads/writes, persistence, plugins,
and files.

The façade is currently broad. It should remain the compatibility adapter for
JavaScript while delegating to deeper internal modules:

- `TargetProcess`: owns a PID, Mach task port, and its lifetime;
- `MemorySession`: owns search results and snapshots for exactly one target;
- `ValueCodec`: validates and converts H5GG value/address/type strings;
- `ScriptStore`: contains all Documents-path resolution and filename policy;
- `PluginLoader`: defines what can cross the WK bridge;
- `DylibBuilder`: validates stubs, writes, signs, and reports errors.

These are proposed internal modules, not additional public JavaScript concepts.

### Memory engine

`JJMemoryEngine` owns a Mach task port, enumerated regions, current results,
result types, and value snapshots. Its public methods currently cover numeric
search, nearby search, change refinement, hex search, pointer search, typed
read/write, and result enumeration.

The critical invariant is:

```text
for every result:
address = region_base + slides[i]
types is either empty for the whole region, or types.size == slides.size
Result.count == the sum of every region's slides.size
snapshot entries use the same type as the corresponding result
```

Every operation which mutates results must preserve that invariant. The current
interface does not enforce it, which is the source of several defects.

The engine needs two distinct read interfaces:

- typed read/write, where a validated value type determines byte width;
- raw byte read, where an explicit bounded length determines byte width.

Passing a byte count through a typed interface is invalid.

### Process and Mach-O discovery

`crossproc` lists processes, obtains Mach task ports through the engine façade,
reads dyld image metadata, and calculates mapped Mach-O sizes. It is an adapter
over private/low-level platform interfaces and should return validated native
records rather than dictionaries where practical.

### GlobalView

`globalview/` runs in SpringBoard, hosts the standalone application view, and
shares `GVData` with the application through a remapped page. The struct layout
is therefore a cross-process binary interface. Field order, size, alignment, and
versioning are compatibility concerns.

A future revision should add a magic value, schema version, total size, and
capability flags before changing the struct.

## Data ownership

| State | Current owner | Required lifetime |
|---|---|---|
| Target PID/task port | `h5ggEngine` | One selected process |
| Regions/results/snapshot | `JJMemoryEngine` | One target and search session |
| Floating UI objects | Globals in `Tweak.mm` | Injected runtime |
| Bridge callbacks | `FloatMenu` | One call ID until settled |
| Bookmarks/history | `NSUserDefaults` | App installation |
| Frozen values | `h5ggEngine` and timer | One target process |
| Scripts/dumps/log | Documents directory | App installation |
| GlobalView state | Remapped `GVData` | Host/application pair |

Changing the target process must atomically replace the task port, memory
session, pending frozen writes, and any target-relative results.

## Compatibility rules

1. Keep `window.h5gg` method names stable or version them explicitly.
2. JavaScript methods always return Promises in the WKWebView implementation.
3. Every Promise settles once, including cancellation and native failure.
4. Addresses are parsed as unsigned 64-bit values with complete input
   consumption and checked ranges.
5. Search results have a single documented schema for numeric and byte results.
6. A memory session never survives a target-process change.
7. GlobalView's shared struct is versioned before its layout changes.
8. Package variants are behaviorally equivalent except for platform paths and
   bootstrap integration.

## Verification seams

There is no automated test target today. The proposed seams allow most behavior
to be tested without a jailbroken device:

- `ValueCodec`: table-driven host tests for every type and invalid input;
- result operations: an in-memory memory adapter with deterministic regions;
- bridge dispatch: message/response contract tests using a fake engine;
- script paths: temporary-directory tests;
- package variants: dry-run assertions on compiler flags and package paths.

Device tests remain necessary for Mach ports, `vm_remap`, protected writes,
SpringBoard hosting, orientation, signing, and all three jailbreak layouts.
