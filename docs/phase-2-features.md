# Phase 2 feature contracts

This document is the support boundary for the version 8.1 features implemented
through Phase 2. "Implemented" describes the current source contract; it does not imply
device verification. The per-capability completion status is maintained in
[roadmap.md](roadmap.md), and device-dependent behavior remains experimental
until its row in [validation.md](validation.md) is recorded on supported
hardware.

For repeatable hardware checks, an opt-in fixed-layout fixture can be compiled
with `H5GG_DEVICE_VALIDATION=1` and exercised through the public Promise bridge
by `examples-JavaScript/h5ggV8/phase2DeviceValidation.js`. Default builds do not
contain the fixture. Exact build, execution, evidence, and remaining interactive
steps are defined in [validation.md](validation.md). A mocked Promise bridge
executes all 15 runner checks in the host suite so report orchestration is
verified independently from the still-pending native device evidence.

## Memory workflows

### Numeric search

- `searchNumber` accepts one exact value, an inclusive `a~b` range, or a
  comma-separated group containing either form.
- A group is one OR query: a location is retained when it matches any member.
  It is not implemented as a sequence of refinements.
- The full expression is parsed before scanning. Empty members, invalid values,
  repeated range separators, and inverted ranges are rejected without changing
  the current results.
- Float tolerance applies consistently to every exact value and range member.

Expression parsing and match-any comparison have host tests. Mach region
enumeration and result mutation remain pending device verification.

### Hex search

- The first `searchHex(pattern, start, end)` call scans writable regions.
- Subsequent calls refine the current result set and never silently restart it.
- Whitespace and mixed-case hex are accepted.
- `?` is a wildcard nibble, so `??` matches any byte and `E?` matches `E0`–`EF`.
- Odd nibbles and non-hex/non-wildcard characters are rejected without
  changing the current results.

The parser, wildcard matcher, and result-refinement adapter have host tests.
Mach region enumeration remains pending device verification.

### Search within results

`searchFilter(value, type, mode)` supports every numeric type (`I8`, `U8`,
`I16`, `U16`, `I32`, `U32`, `I64`, `U64`, `F32`, and `F64`) and these modes:

| Mode | Value | Meaning |
|---|---:|---|
| Equal | `0` | current value equals the supplied value |
| Greater | `2` | current value is greater |
| Less | `3` | current value is less |

Invalid values or modes are rejected before the result set is mutated.

### Memory viewer

The UI requests fixed 256-byte pages through `readMemoryPage`. The native API
accepts 1–4096 bytes, reports each byte as a number or `null`, and returns
`complete` plus the readable-byte count. The viewer renders unreadable bytes as
`??`, uses 64-bit `BigInt` address arithmetic, and clamps page navigation to the
unsigned 64-bit address space. Page reads and typed result reads use the same
`MemoryReader` interface as filters, snapshots, and dumps.

### Memory dump

`dumpMemory` is asynchronous. It streams 64 KiB chunks directly to the output
file, exposes `getDumpStatus`, and accepts `cancelDump` while the original
Promise is pending. Failed and cancelled dumps remove the partial file. Output
names are confined to one entry in the app Documents directory.

The stream, partial-read, progress, cancellation, failure, adapter
over-reporting, and address-overflow behavior have host tests through the same
reader interface used by the Mach-backed engine. Reading another process and
writing its complete output remain pending device verification.
`DumpController` adds host coverage for request validation, one-running-job
enforcement, reader-lease release, real-file publication, originating Promise
completion, and partial file removal after read failure or cancellation.

## Target and freezer lifecycle

Target selection constructs a new engine before atomically replacing the old
task port. A failed selection preserves the current target. A successful
selection resets search state and frozen values before releasing the previous
engine and non-self port. `getTargetStatus` detects a terminated target,
invalidates its engine, and clears target-bound frozen values. A dump retains
its own task-port right, so switching targets cannot invalidate an in-flight
dump.

Frozen entries contain the selected PID, canonical address, status, failure
count, and last error. Invalid values are rejected before scheduling. Timer
teardown occurs when the last entry is removed or the engine is released.
`FreezerController` owns those rules behind injected target, memory-writer, and
scheduler adapters. Its Foundation contract test covers validation, numeric
address sorting, replacement, target changes, write failure/recovery, and
exactly-one timer start/stop without relying on run-loop timing.

## Files and extensions

The script store accepts only a single safe `.js` or `.html` file name. A name
without an extension receives `.js`; any other extension is rejected. Files are
limited to 2 MiB and valid UTF-8, writes use a same-directory temporary file and
atomic rename, reads reject symlinks and non-regular files, lists are sorted,
and failures are exposed through `getLastFileError`. Host tests exercise the
same `ScriptStore` used by the Objective-C bridge.

The editor uses explicit Save—there is no autosave. Only `.js` files can run or
auto-run; `.html` files can be edited and stored.

File-picker Promises settle once on selection or cancellation.
`FilePickerRequest` captures the originating menu's bridge call ID, normalizes
and deduplicates document types, defaults to `public.data`, and rejects racing
duplicate completions. The UIKit adapter tolerates an empty URL list and stops
its security-scoped access after the imported path has been returned.

## Native plugin transport

WKWebView does not expose Objective-C instances to JavaScript. Plugins used
from WKWebView must implement `H5GGPluginRPC`:

```objc
-(id)h5ggInvoke:(NSString*)method
      arguments:(NSArray*)arguments
          error:(NSError**)error;
```

`loadPlugin` returns a JSON-compatible descriptor containing `loaded`, `id`,
`className`, and `rpc` when loading succeeds. `callPlugin(id, method, arguments)`
returns `{ok, result}` or `{ok: false, error}`. Arguments and results must be
JSON-compatible. `PluginLoader` resolves relative paths against the app bundle,
loads each image once, retains Objective-C images for process lifetime, creates
an independent opaque ID for each WK plugin object, and converts loader, plugin,
and serialization failures to result dictionaries. Legacy JavaScriptCore
callers may still receive the native object. The custom-alert demo shows the RPC
form. Older examples that expect a synchronous native object are not part of
this WK contract and carry an explicit `LEGACY-JAVASCRIPTCORE-ONLY` marker. A
macOS Foundation contract test covers loading, caching, modes, JSON checks,
errors, exceptions, and handle lifecycle. The documentation check rejects
unknown bridge calls, unawaited WK examples, and unlabelled legacy samples.

## Dylib generation

The tweak embeds 512 KiB icon and 2 MiB menu replacement regions in every
architecture slice. Generation validates the image and UTF-8 menu, replaces
every slice without changing Mach-O offsets, signs a same-directory temporary
file, and atomically publishes only after `ldid` succeeds. A failed build
removes its temporary file and preserves any existing output. The generated
tweak consumes the customized regions before bundle or built-in resources.

When a built universal dylib and `ldid` are available,
`tests/check_dylib_generation.sh` transforms and signs the dylib through the
same `DylibBuilder` interface used by production, verifies the signature can be
read, and checks that it remains a universal Mach-O. Unit coverage also checks
invalid icons, UTF-8/NUL rejection, payload limits, architecture-count
mismatches, and preservation of existing output after signing failure. The
integration check reports a skip when either prerequisite is missing. Loading
the generated dylib remains experimental until the device validation row
passes.

## Pointer tools

Pointers are unsigned 64-bit, exact, and 8-byte aligned. Pointer searches
enumerate the selected range and stop at 4,096 results or 512 MiB of mapped
memory scanned. UI pointer chains use `BigInt` and stop at 32 reads.
`getPointerCapabilities` exposes these limits to scripts. `PointerSearch`
enforces range, alignment, result, byte, and chunk limits through the same
`MemoryReader` interface used in production and host tests. Mach region
enumeration and real target reads remain device-gated.

## Floating presentation

In injected dylib mode, the 50-point floating button starts with its frame 35
points from the left edge and centered vertically in the active window. The
first observed window frame establishes the resize baseline without rescaling
the initial position. Later window-size changes scale and clamp its origin.

This behavior is source-checked and compiles for arm64/arm64e. Orientation and
window-lifecycle behavior remain part of the injected and GlobalView device
matrix.

GlobalView state uses a fixed-width versioned header with explicit capabilities
and fails closed when `SetGlobalViewV2` or a compatible mapping is unavailable.
Button images cross a separate 512 KiB maximum single-slot transfer instead of
being embedded in `GVData`. Header rejection and payload bounds are host-tested;
cross-process remapping and presentation remain device-gated.
