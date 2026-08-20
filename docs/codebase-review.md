# Codebase review

Verified against `0571a44` plus the current working tree on 2026-08-20.

## Executive finding

The stabilization and Phase 2 implementation work is present. Target and
session ownership is move-only and atomically replaceable, grouped numeric
searches use OR semantics through one scan, typed and raw reads are separate,
result mutations are centralized, bridge method names are allowlisted, file
names are confined, freezer/picker lifecycle and pointer matching use tested
modules, plugin images/handles and JSON RPC use one loader, and
customized dylib validation, replacement, signing, cleanup, and atomic output
are owned and host-tested behind one builder interface. Bootstrap modes,
readiness timers, and floating UI retention use one runtime coordinator, while
GlobalView mappings negotiate a fixed-width versioned protocol and separate
bounded image-transfer slot.

The code is not device-verified. Hardware-dependent behavior is still pending
in [validation.md](validation.md), while host contracts and generated package
contents are enforced in CI. Several architecture and repository-health items
remain open.

## Evidence and validation

- `bash tests/run_tests.sh`: passed on 2026-08-20.
- The host suite covers target/session lifetime, modal request serialization,
  result invariants, value and grouped-search parsing/matching, numeric filtering,
  masked hex matching, partial raw reads, dump streaming, filename confinement,
  bridge allowlisting/argument schemas, generated JavaScript argument-reference
  coverage, freezer and file-picker lifecycle, pointer matching/limits, plugin
  loader/RPC behavior, runtime lifecycle, GlobalView protocol rejection/
  transfer behavior, build-variant definitions, and dylib build/sign/publish
  behavior when a built dylib and `ldid` are available.
- The normal, rootless, and roothide root tweaks compile for arm64 and arm64e.
- Normal, rootless, and roothide `.deb` files pass exact control metadata,
  installed-path, dylib/plist, executable-script, and Mach-O slice assertions
  before `build.sh` publishes them.
- Every device row remains outstanding.
- This review does not treat an unrecorded device behavior as complete.

## Active issue register

Severity meanings:

- **P1**: runtime correctness, safety, or lifecycle behavior is incomplete;
- **P2**: verification, maintainability, delivery, or documentation debt.

Resolved findings are removed from this active register. Roadmap completion and
remaining verification are tracked in [roadmap.md](roadmap.md).

### P2 — Verification, architecture, and delivery debt

#### H5-018: Generated artifacts, IDE state, and large dependencies are tracked

The repository still tracks `.deb`/`.tipa` outputs, prebuilt application and
plugin binaries, Xcode `xcuserdata`, and the nested Dobby source snapshot. The
ignore rules prevent some new outputs but do not remove existing tracked files
or document dependency provenance.

Acceptance: classify required binaries, record versions/checksums and licenses,
remove regenerable outputs and user state from source history, and choose an
explicit policy for the Dobby snapshot.

#### H5-020: Debug logging is unconditional and may expose target details

Release builds still emit process paths, addresses, mapped regions, values, and
UI state through unconditional `NSLog` calls while `DEBUG=0`.

Acceptance: centralize log levels, compile verbose region/value logging out of
release packages, redact sensitive fields, and document an opt-in diagnostics
path.

## Positive current state

- `Result` owns count/type invariants and is exercised by host tests.
- Bridge names, counts, JSON kinds, integer rules, numeric ranges, and filter
  modes are rejected centrally before native invocation; the same structures
  generate the checked native argument table in `javascript-api.md`.
- `MemoryValue` owns type-name mapping and strict tolerance/value/address
  parsing, typed formatting, and atomic grouped/ranged search expressions
  instead of duplicating those rules in the Objective-C façade.
- `TargetProcess` and `MemorySession` make task-port, engine, and search-state
  lifetime explicit; host tests cover moves, replacement, and exactly-once
  release.
- `ModalRequestQueue` serializes overlapping synchronous dialogs with
  request-scoped, exactly-once completion; FIFO, cancellation, and blocking
  waits are host-tested.
- One `MemoryReader` interface derives exact and typed reads from a clamped
  partial-byte primitive. Engine, filter, page, dump, façade, buffer, and
  fault-injecting adapters cross the same seam, including overflow behavior.
- `PointerSearch` uses that reader seam for exact aligned 64-bit matches and
  enforces range/result/byte limits with host coverage; only Mach region
  enumeration remains device-specific.
- `FreezerController` owns canonical target-bound entries, status/failure
  recovery, and one timer through injected writer/scheduler adapters.
- `FilePickerRequest` binds completion to the originating menu/call ID and
  rejects duplicate or racing selection/cancellation callbacks.
- `PreferencesStore` owns capped input/search histories and unique bookmarks,
  filters malformed persisted values, and is tested with isolated defaults and
  an injected timestamp provider.
- `DumpController` owns validation, one-running-job state, cancellation,
  progress, target-reader lease release, file cleanup/publication, and deferred
  completion; injected executors/readers and real temporary files cover its
  production interface.
- `RuntimeCoordinator` replaces bootstrap mode/UI globals and detached-thread
  polling with exactly-once readiness and owned monitoring timers; the same
  interface has Foundation host coverage.
- `GVData` and `GVImageTransfer` carry validated magic/version/size/capability
  headers. Mixed protocol versions fail closed, and image handoff is separate,
  bounded, and single-slot.
- Package targets run as fresh top-level Theos invocations, so scheme staging
  and control metadata cannot leak between variants. `build.sh` unpacks and
  validates every artifact before collection, and CI runs the host suite first.
- Target replacement clears results and frozen values and releases old ports.
- File-picker callbacks capture independent call IDs and settle cancellation.
- Script persistence is confined to one Documents root and uses regular-file,
  UTF-8, size, atomic-write, and deterministic-listing rules behind a tested
  `ScriptStore`; dump names use the same single-entry filename policy.
- `DylibBuilder` validates regular-file inputs and bounded payloads, replaces
  every matching architecture template, signs temporary output, removes
  failures, and only then atomically publishes; host tests use the same
  interface as production.
- `PluginLoader` caches each loaded image, preserves legacy JavaScriptCore
  object returns, owns opaque WK RPC handles, and rejects non-JSON arguments or
  results; loader, resolver, error, exception, and lifecycle paths are tested.
- Example bridge calls are checked against the production inventory: WK samples
  await Promise methods, synchronous native-object samples carry an explicit
  `LEGACY-JAVASCRIPTCORE-ONLY` marker, and the RPC demo is fixture-checked.
- The floating button establishes its first layout baseline before rescaling;
  injected dylibs default to 35 points from the left and vertical center.
- All build adapters use an iOS 15.0 deployment baseline and explicit variant
  definitions.

## Review limits

This is a source, host-test, and build-evidence review, not an exploit audit of
vendored Frida/Dobby/ldid code. Private iOS interfaces, Mach task operations,
SpringBoard hosting, orientation, signing acceptance, and jailbreak layouts
still require the device evidence listed in [validation.md](validation.md).
