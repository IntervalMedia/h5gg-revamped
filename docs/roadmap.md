# Stabilization and feature roadmap

This roadmap converts the review into ordered outcomes. It intentionally puts
correctness and verification before additional user-facing features.

## Implementation status

The initial stabilization slice was implemented on 2026-07-31:
host-runnable result/filter/codec/schema/path tests, a raw-read engine API,
atomic target sessions, result invariants, strict hex first-search behavior,
bridge allowlisting, Promise error settlement, and distinct compiler
definitions for each package variant. The host suite covers the bridge schema
and the in-memory reader seam; native WK dispatch, raw Mach reads, package
layouts, and the device checks in [validation.md](validation.md) remain release
gates. Phases 3–5 remain planned work.

Phase 2 code and host verification were completed on 2026-07-31. The exact
contracts and explicit limits are recorded in
[phase-2-features.md](phase-2-features.md). Hardware-dependent rows remain
experimental until recorded in [validation.md](validation.md).

## Release gates

A release is not considered stable until:

- one automated suite exercises value parsing, result invariants, raw reads,
  bridge dispatch, and file confinement;
- numeric and byte search sessions pass on one local-process and one
  cross-process device scenario;
- every JavaScript Promise resolves or rejects exactly once;
- normal, rootless, and roothide packages prove their variant paths and install
  layouts;
- the standalone, injected, and GlobalView modes pass a documented smoke matrix.

## Phase 0 — Freeze and reproduce

Goal: make failures deterministic before restructuring.

1. Add a small test target and an in-memory adapter for memory regions.
2. Encode the result invariants from `architecture.md` as assertions/tests.
3. Add bridge contract fixtures for every advertised method.
4. Capture device smoke steps for target selection, numeric search, read/write,
   window display, and package installation.
5. Decide the supported iOS/jailbreak matrix and record it in README/package
   metadata.

Exit: each P0 defect has a failing automated or repeatable device check.

## Phase 1 — Core correctness

Goal: make the existing primary workflows trustworthy.

Work order:

1. **Target process/session ownership** — fix H5-001 and H5-010.
2. **Typed and raw memory interfaces** — fix H5-002.
3. **Result model and enumeration** — fix H5-004, including counts/types.
4. **Bridge allowlist and validation** — fix H5-003.
5. **Variant compiler flags and package assertions** — fix H5-005.

Recommended tracer slices:

- switch target, read one known value, switch back;
- raw read across one readable page;
- exact numeric first/refine search for each type;
- filter one deterministic result set and verify count/types;
- hex first search with valid/invalid patterns;
- reject one unknown bridge method;
- prove exactly one variant macro in each build.

Exit: numeric search/read/write and cross-process selection are device-verified;
hex/filter/raw byte tests pass against the memory adapter; all package variants
have distinct verified configuration.

## Phase 2 — Complete partially implemented v8 features

Goal: finish features already present in the UI or README before expanding scope.

| Capability | Current state | Completion outcome |
|---|---|---|
| Hex search | Complete | First/refine semantics; nibble wildcards; parser/refinement tests |
| Search within results | Complete | Every numeric type; equal/greater/less; invariant-safe filtering |
| Memory viewer | Complete | Partial reads; `??` markers; bounded 64-bit paging |
| Memory dump | Complete | Streaming; progress/cancel; partial-file cleanup; safe filename |
| Cross-process mode | Complete | Atomic target sessions; termination invalidation; dump port ownership |
| Value freezer | Complete | Target PID binding; visible failures; safe timer teardown |
| Script editor | Complete | Sandboxed names; explicit `.js`/`.html` policy; errors; explicit save |
| Native plugins | Complete, new contract | JSON RPC for WK; legacy object compatibility only in JavaScriptCore |
| Dylib generation | Host-verified; device experimental | Embedded per-slice stubs; replacement/signing integration check |
| File picker | Complete | Once-only cancellation/success; independent call IDs; scope cleanup |
| Pointer tools | Complete with limits | 64-bit/8-byte; 4,096 results; 512 MiB scan; 32-step chains |

Exit: every capability is either verified and documented, marked experimental
with explicit limits, or removed from the stable UI.

## Phase 3 — Deepen the modules

Goal: improve locality and make future work safer.

1. Add `TargetProcess` and `MemorySession`; make task-port ownership explicit.
2. Add `ValueCodec`; remove scattered `strto*` and enum conversions.
3. Add a raw/typed memory adapter seam with a deterministic in-memory adapter.
4. Replace ad hoc `result_region` mutation with one invariant-preserving result
   module.
5. Make `FloatMenu` table-driven from one method schema used for native
   dispatch, JavaScript injection, and documentation.
6. Add `ScriptStore`, `PluginLoader`, and `DylibBuilder` behind the existing
   engine façade.
7. Replace bootstrap globals/timer knowledge with a runtime coordinator.
8. Version the `GVData` shared-memory interface.

Exit: tests and callers use the same small interfaces, and deleting any of
these modules would force its complexity back into multiple callers—the
modules are earning their seam.

## Phase 4 — Delivery and repository health

Goal: make releases reproducible and the repository navigable.

1. Stop tracking regenerated packages and Xcode user state.
2. Inventory/checksum prebuilt dependencies and document their provenance.
3. Decide whether the nested Dobby source belongs as a submodule, fetched
   dependency, or maintained vendored snapshot.
4. Split build, package, and release verification; do not rely on artifact
   names alone to prove a variant.
5. Remove the hardcoded local `THEOS_DEVICE_IP`.
6. Gate verbose logs and add a support bundle with explicit user consent.
7. Generate complete JavaScript reference documentation from the bridge schema.

Exit: a clean checkout can reproduce each supported artifact, while releases
and local IDE state are kept out of source history.

## Phase 5 — New feature candidates

These are candidates, not commitments. Run a design/spec pass after Phases 0–2
have produced reliable foundations.

### Search quality

- wildcard/masked byte patterns;
- aligned/unaligned scan options;
- readable/writable/executable region filters;
- saved search sessions with explicit target/module identity;
- cancellable scans and progress reporting.

### Pointer analysis

- configurable pointer width and offset bounds;
- multi-level chain search with deduplication and cancellation;
- module-relative chain persistence;
- revalidation after application restart/ASLR changes.

### Script and plugin platform

- versioned capability manifest;
- scoped permissions for memory, files, network, and native plugins;
- structured plugin RPC rather than Objective-C object exposure;
- script import/export with provenance and compatibility metadata.

### Diagnostics

- opt-in structured logs with redacted addresses/paths;
- memory/session statistics;
- package/runtime build identity in the UI;
- exportable diagnostic report.

## Dependency order

```text
Test harness
  ├── TargetProcess + MemorySession
  │     ├── cross-process mode
  │     └── target-aware freezer
  ├── raw/typed memory seam
  │     ├── memory viewer
  │     └── memory dump
  ├── invariant result module
  │     ├── hex search
  │     ├── result filters
  │     └── pointer analysis
  └── bridge method schema
        ├── security allowlist
        ├── complete API docs
        ├── file-picker lifecycle
        └── plugin RPC decision
```

Build-variant repair can proceed in parallel with the runtime work, but no
variant should be released before the common core release gates pass.
