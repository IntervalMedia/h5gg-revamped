# Phase 2 feature contracts

This document is the support boundary for the partially implemented v8
features completed in Phase 2. Device-dependent behavior remains experimental
until its row in `validation.md` has been recorded on supported hardware.

## Memory workflows

### Hex search

- The first `searchHex(pattern, start, end)` call scans writable regions.
- Subsequent calls refine the current result set and never silently restart it.
- Whitespace and mixed-case hex are accepted.
- `?` is a wildcard nibble, so `??` matches any byte and `E?` matches `E0`–`EF`.
- Odd nibbles and non-hex/non-wildcard characters are rejected without
  changing the current results.

The parser, wildcard matcher, and result-refinement adapter have host tests.
Mach region enumeration remains device-verified.

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
unsigned 64-bit address space.

### Memory dump

`dumpMemory` is asynchronous. It streams 64 KiB chunks directly to the output
file, exposes `getDumpStatus`, and accepts `cancelDump` while the original
Promise is pending. Failed and cancelled dumps remove the partial file. Output
names are confined to one entry in the app Documents directory.

The stream, partial-read, progress, cancellation, and failure behavior have
host tests. Reading another process and writing its complete output remain
device-verified.

## Target and freezer lifecycle

Target selection constructs a new engine before atomically replacing the old
task port. `getTargetStatus` detects a terminated target, invalidates its
engine, and clears target-bound frozen values. A dump retains its own task-port
right, so switching targets cannot invalidate an in-flight dump.

Frozen entries contain the selected PID, canonical address, status, failure
count, and last error. Invalid values are rejected before scheduling. Timer
teardown occurs when the last entry is removed or the engine is released.

## Files and extensions

The script store accepts only a single safe `.js` or `.html` file name. A name
without an extension receives `.js`; any other extension is rejected. Files are
limited to 2 MiB, writes are atomic, lists are sorted, and failures are exposed
through `getLastFileError`.

The editor uses explicit Save—there is no autosave. Only `.js` files can run or
auto-run; `.html` files can be edited and stored.

File-picker Promises settle once on selection or cancellation. Each picker
captures its own bridge call ID, tolerates an empty URL list, and stops its
security-scoped access after the imported path has been returned.

## Native plugin transport

WKWebView does not expose Objective-C instances to JavaScript. Plugins used
from WKWebView must implement `H5GGPluginRPC`:

```objc
-(id)h5ggInvoke:(NSString*)method
      arguments:(NSArray*)arguments
          error:(NSError**)error;
```

`loadPlugin` returns a JSON handle, and `callPlugin(handle, method, arguments)`
returns `{ok, result}` or `{ok: false, error}`. Arguments and results must be
JSON-compatible. Legacy JavaScriptCore callers may still receive the native
object. The custom-alert demo shows the RPC form.

## Dylib generation

The tweak embeds 512 KiB icon and 2 MiB menu replacement regions in every
architecture slice. Generation validates the image and UTF-8 menu, replaces
every slice without changing Mach-O offsets, writes the output, and requires
`ldid` signing to succeed. The generated tweak consumes the customized regions
before bundle or built-in resources.

`tests/check_dylib_generation.sh` transforms the built universal dylib with the
same replacement module, signs it, verifies the signature can be read, and
checks that it remains a universal Mach-O. Loading the generated dylib remains
experimental until the device validation row passes.

## Pointer tools

Pointers are unsigned 64-bit, exact, and 8-byte aligned. Pointer searches
enumerate the selected range and stop at 4,096 results or 512 MiB of mapped
memory scanned. UI pointer chains use `BigInt` and stop at 32 reads.
`getPointerCapabilities` exposes these limits to scripts.
