# Codebase review

Verified against `02b818d` plus the working-tree floating-button fix on
2026-08-19.

## Executive finding

The stabilization and Phase 2 implementation work is present. Target changes
replace the memory session atomically, typed and raw reads are separate, result
mutations are centralized, bridge method names are allowlisted, file names are
confined, plugins use a JSON RPC contract under WKWebView, and customized dylib
templates are embedded and host-tested.

The code is not release-verified. Hardware-dependent behavior is still pending
in [validation.md](validation.md), bridge schemas validate argument counts but
not argument kinds, package contents are not asserted, and several architecture
and repository-health items remain open.

## Evidence and validation

- `bash tests/run_tests.sh`: passed on 2026-08-19.
- The host suite covers result invariants, value parsing, numeric filtering,
  masked hex matching, partial raw reads, dump streaming, filename confinement,
  bridge allowlisting/counts, JavaScript documentation coverage, build-variant
  definitions, and dylib template replacement/signing when a built dylib and
  `ldid` are available.
- The root tweak currently compiles for arm64 and arm64e. The rootful package
  step passes when run after compilation.
- Build/package validation for all three jailbreak layouts and every device row
  remains outstanding.
- This review does not treat an unrecorded device behavior as complete.

## Active issue register

Severity meanings:

- **P1**: runtime correctness, safety, or lifecycle behavior is incomplete;
- **P2**: verification, maintainability, delivery, or documentation debt.

Resolved findings are removed from this active register. Roadmap completion and
remaining verification are tracked in [roadmap.md](roadmap.md).

### P1 — Runtime correctness and lifecycle

#### H5-003: Bridge argument kinds are not declared or validated centrally

`BridgeMethods` is now the native allowlist and validates argument counts, so a
posted message can no longer derive an arbitrary Objective-C selector. The
table does not describe argument kinds or ranges, however, and `FloatMenu`
still converts values according to the Objective-C method encoding.

Impact: malformed but correctly sized argument arrays can be coerced at the
invocation seam and fail inconsistently inside individual methods.

Acceptance: extend the method schema with argument/result kinds and applicable
ranges; reject invalid values before `NSInvocation`; add negative fixtures for
every kind; use the same schema for dispatch and reference documentation.

#### H5-012: Dialog synchronization is process-global and non-reentrant

`ModalShow` stores one static semaphore for all presentations. A second dialog
can replace it while the first caller is waiting
([ModalShow.m](../ModalShow.m#L7)).

Impact: overlapping alerts, confirms, or prompts can unblock the wrong caller or
leave a caller waiting indefinitely.

Acceptance: give each presentation its own completion state, serialize or queue
presentations, and ensure every dismissal completes exactly one request.

### P2 — Verification, architecture, and delivery debt

#### H5-005: Package variants lack content-level assertions

Normal, rootless, and roothide now receive exactly one compile definition and
the host test checks the compiler commands. CI builds the three artifacts but
does not inspect their installed paths, dependencies, or translated roothide
locations.

Acceptance: unpack each generated package in CI and assert its control metadata,
install paths, dylib/plist pairing, and variant-specific path behavior.

#### H5-014: The host suite is not enforced by CI

`tests/run_tests.sh` provides a deterministic host suite, but the build and
manual-release workflows call `build.sh` without running that suite first.

Acceptance: run the host suite as a required CI job, make skipped integration
checks visible, and keep device results in the checked validation matrix.

#### H5-015: `h5ggEngine` and bootstrap remain high-coupling modules

The extracted result, codec, bridge-schema, filename, memory-page, memory-dump,
and dylib-template modules improve locality. `h5ggEngine` still coordinates
process ownership, persistence, plugins, files, dumps, freezing, and searches;
`Tweak.mm` still coordinates lifecycle through globals and polling timers.

Acceptance: continue the internal module work described in
[architecture.md](architecture.md) behind the unchanged JavaScript interface,
with tests crossing the same seams used by callers.

#### H5-016: GlobalView shared memory has no version or size guard

`GVData` is a cross-process binary interface with no magic, schema version, or
total-size header and includes a 512 KiB inline image buffer
([globalview.h](../globalview/globalview.h#L4)).

Acceptance: validate a versioned header before either process uses the mapping;
represent optional capabilities explicitly; move large payload transfer behind
a separate bounded mechanism before changing the layout.

#### H5-018: Generated artifacts, IDE state, and large dependencies are tracked

The repository still tracks `.deb`/`.tipa` outputs, prebuilt application and
plugin binaries, Xcode `xcuserdata`, and the nested Dobby source snapshot. The
ignore rules prevent some new outputs but do not remove existing tracked files
or document dependency provenance.

Acceptance: classify required binaries, record versions/checksums and licenses,
remove regenerable outputs and user state from source history, and choose an
explicit policy for the Dobby snapshot.

#### H5-019: Legacy examples do not all follow the WK Promise/RPC contract

The complete 52-method bridge inventory is documented and checked against
`BridgeMethods.cpp`. At least the WebUDID example still calls `loadPlugin`
synchronously and expects a native object
([h5ggWebUDID.js](../examples-HTML5/get-device-UDID/h5ggWebUDID.js#L1)).

Acceptance: migrate or clearly label every legacy example; add representative
examples to bridge contract fixtures; keep the checked method inventory in sync.

#### H5-020: Debug logging is unconditional and may expose target details

Release builds still emit process paths, addresses, mapped regions, values, and
UI state through unconditional `NSLog` calls while `DEBUG=0`.

Acceptance: centralize log levels, compile verbose region/value logging out of
release packages, redact sensitive fields, and document an opt-in diagnostics
path.

## Positive current state

- `Result` owns count/type invariants and is exercised by host tests.
- Numeric typed reads and bounded raw-byte reads are distinct interfaces.
- Target replacement clears results and frozen values and releases old ports.
- File-picker callbacks capture independent call IDs and settle cancellation.
- Script and dump names are confined to a single safe Documents entry.
- WK plugins use JSON-compatible descriptors and `H5GGPluginRPC` calls.
- The floating button establishes its first layout baseline before rescaling;
  injected dylibs default to 35 points from the left and vertical center.
- All build adapters use an iOS 15.0 deployment baseline and explicit variant
  definitions.

## Review limits

This is a source, host-test, and build-evidence review, not an exploit audit of
vendored Frida/Dobby/ldid code. Private iOS interfaces, Mach task operations,
SpringBoard hosting, orientation, signing acceptance, and jailbreak layouts
still require the device evidence listed in [validation.md](validation.md).
