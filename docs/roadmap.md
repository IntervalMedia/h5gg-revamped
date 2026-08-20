# Stabilization and feature roadmap

Last verified: 2026-08-20.

## Status legend and current phase

| Status | Meaning |
|---|---|
| ✅ Complete | Implemented and covered by the available host/build verification |
| 🟡 Partial | Implemented in part or awaiting a required verification gate |
| ⬜ Planned | No material implementation of the roadmap outcome yet |

**Current phase: Phase 2 exit validation with Phase 3 implementation underway.**
The Phase 0–2 implementation is largely present, but the project has not met
the device and package release gates. Phase 3 is now actively deepening the
bridge, value, target/session, and modal lifecycle seams. Phase 4 is partially
underway.

## Phase summary

| Phase | Status | Current outcome |
|---|---|---|
| Phase 0 — Freeze and reproduce | 🟡 Partial | Host harness and device matrix exist; native bridge/device repro coverage is incomplete |
| Phase 1 — Core correctness | 🟡 Partial | Core fixes and bridge validation are host-verified; package and device gates remain |
| Phase 2 — Complete v8 features | 🟡 Partial | Feature implementation is present; hardware-dependent rows remain experimental |
| Phase 3 — Deepen the modules | 🟡 Partial | Bridge validation, value rules, target/session ownership, and modal serialization are centralized; service/bootstrap seams remain broad |
| Phase 4 — Delivery and repository health | 🟡 Partial | Variant builds/artifact publication improved; tracked artifacts, CI tests, provenance, and logging remain |
| Phase 5 — New feature candidates | ⬜ Planned | Candidate backlog only |

## Release gates

| Gate | Status | Evidence or next action |
|---|---|---|
| Host suite covers codecs, results, raw reads, bridge inventory, and file confinement | ✅ Complete | `bash tests/run_tests.sh` passes locally |
| Host suite is required in CI | ⬜ Planned | Add it before variant builds/releases |
| Local and cross-process numeric/byte sessions pass on device | ⬜ Planned | Record [validation.md](validation.md) rows |
| Every JavaScript Promise settles once | 🟡 Partial | Picker path is implemented; native/device overlap matrix remains |
| Bridge validates method names, counts, argument kinds, and numeric constraints | ✅ Complete | Shared schema is host-tested and enforced before `NSInvocation` |
| Normal/rootless/roothide package contents and paths are asserted | 🟡 Partial | Compile definitions pass; unpacked package assertions remain H5-005 |
| Standalone, injected, and GlobalView modes pass smoke tests | ⬜ Planned | Record device matrix |

No stable release should be declared until every gate above is complete.

## Phase 0 — Freeze and reproduce

Goal: make failures deterministic before restructuring.

| Work item | Status | Evidence / remaining work |
|---|---|---|
| Add a host test target and in-memory readers | ✅ Complete | `tests/run_tests.sh`, C++ fixtures, and callback readers exist |
| Encode result invariants as assertions/tests | ✅ Complete | `MemoryResultsTests.cpp` exercises counts and typed/untyped regions |
| Add bridge contract fixtures | 🟡 Partial | Portable inventory, count, kind, range, and enum checks exist; a host WK dispatch fixture remains |
| Capture repeatable device smoke steps | ✅ Complete | Matrix exists in `validation.md` |
| Record supported platform baseline | ✅ Complete | iOS 15.0+, arm64/arm64e is consistent in README, targets, and package description |

Exit status: **partial**. The deterministic host loop exists, but native WK and
hardware-dependent failures do not yet have recorded device results.

## Phase 1 — Core correctness

Goal: make primary workflows trustworthy.

| Work item | Status | Evidence / remaining work |
|---|---|---|
| Atomic target process/session replacement | ✅ Complete | New task and engine are acquired before state replacement; old ports are released |
| Separate typed and raw memory interfaces | ✅ Complete | `JJReadMemory` and `JJReadBytes`; host page/dump readers |
| Central result model and invariant-safe filtering | ✅ Complete | `Result`, `MemoryFilter`, and masked-hex refinement tests |
| Native bridge allowlist | ✅ Complete | `BridgeMethods` is required before selector creation |
| Bridge argument-kind/range validation | ✅ Complete | Shared schema rejects malformed values before `NSInvocation` |
| Variant compiler definitions | ✅ Complete | One definition per normal/rootless/roothide dry run |
| Variant package content assertions | ⬜ Planned | Active issue H5-005 |
| Device verification of search/read/write and target switching | ⬜ Planned | Use `validation.md` |

Exit status: **partial**. Core implementation and host checks pass; schema,
package-content, and device checks prevent the phase from being closed.

## Phase 2 — Complete partially implemented v8 features

Goal: finish features already exposed by the UI or documentation before adding
scope.

| Capability | Implementation | Host verification | Device verification |
|---|---|---|---|
| Hex search | ✅ Complete | ✅ Parser, wildcards, refinement | ⬜ Pending |
| Numeric grouped/ranged search | ✅ Complete | ✅ Atomic parser and OR matcher | ⬜ Pending |
| Search within results | ✅ Complete | ✅ All numeric kinds and modes | ⬜ Pending |
| Memory viewer | ✅ Complete | ✅ Partial-page model and JS actions | ⬜ Pending |
| Memory dump | ✅ Complete | ✅ Streaming, progress, cancel, cleanup | ⬜ Pending |
| Cross-process mode | ✅ Complete | 🟡 Ownership logic inspected; no real Mach target on host | ⬜ Pending |
| Value freezer | ✅ Complete | 🟡 Target binding and teardown inspected; no UIKit timer fixture | ⬜ Pending |
| Script editor/store policy | ✅ Complete | ✅ Names/extensions and JS actions | ⬜ Pending |
| Native plugin RPC | ✅ Complete | 🟡 Contract/docs/demo present; no loaded WK plugin host test | ⬜ Pending |
| Dylib generation | ✅ Complete | ✅ Multi-slice replacement and host signing | ⬜ Pending |
| File picker | ✅ Complete | 🟡 Independent IDs/cancel path inspected; no UIKit fixture | ⬜ Pending |
| Pointer tools | ✅ Complete with documented limits | 🟡 Capability and UI logic present; Mach scan not host-tested | ⬜ Pending |
| Injected floating-button default | ✅ Complete | ✅ Source regression check and arm64/arm64e compile | ⬜ Pending |

Exact contracts and limits are recorded in
[phase-2-features.md](phase-2-features.md). Exit status: **partial** until the
hardware-dependent rows are recorded and any failures are resolved.

## Phase 3 — Deepen the modules

Goal: improve locality and make future work safer without changing the
JavaScript interface.

| Work item | Status | Current state / outcome |
|---|---|---|
| Add `TargetProcess` and `MemorySession` | ✅ Complete | Move-only task ownership, engine-before-port teardown, atomic replacement, and search metadata are host-tested |
| Centralize value/address/type conversion | ✅ Complete | Type names, tolerance, parsing, formatting, addresses, grouped/ranged expressions, and hex patterns use host-tested `MemoryValue` rules |
| Add a raw/typed reader seam with in-memory adapters | 🟡 Partial | Page, dump, and filter callbacks exist; the whole engine does not use one adapter interface |
| Replace ad hoc result mutation with one result module | ✅ Complete | `MemoryResults` owns mutation/count invariants |
| Use one bridge schema for dispatch, injection, validation, and docs | 🟡 Partial | Inventory and argument rules are shared by injection/dispatch; detailed docs generation remains |
| Add `ScriptStore`, `PluginLoader`, and `DylibBuilder` | 🟡 Partial | Filename and template helpers exist; ownership remains in the façade |
| Replace bootstrap globals/timers with a runtime coordinator | ⬜ Planned | Active issue H5-015 |
| Make modal presentation request-scoped and serial | ✅ Complete | FIFO request state, exactly-once completion, cancellation promotion, and blocking waits are host-tested; UIKit adapter builds for both slices |
| Version the `GVData` shared-memory interface | ⬜ Planned | Active issue H5-016 |

Exit status: **active and partial**. The bridge, value, target/session, and modal
modules now provide real locality, but store/plugin/builder, bootstrap, and
GlobalView ownership seams remain incomplete.

## Phase 4 — Delivery and repository health

Goal: make releases reproducible and the repository navigable.

| Work item | Status | Current state / outcome |
|---|---|---|
| Stop tracking generated packages and Xcode user state | 🟡 Partial | Ignore rules improved; already tracked files remain (H5-018) |
| Inventory/checksum prebuilt dependencies and provenance | ⬜ Planned | H5-018 |
| Choose a policy for the nested Dobby source | ⬜ Planned | H5-018 |
| Separate build, package, and release verification | 🟡 Partial | `build.sh` isolates artifacts; package-content checks remain |
| Remove hardcoded local device addresses | ✅ Complete | Only a commented example remains |
| Run host verification in CI before packaging | ⬜ Planned | H5-014 |
| Gate/redact verbose logs and add opt-in diagnostics | ⬜ Planned | H5-020 |
| Maintain complete JavaScript reference documentation | 🟡 Partial | All 52 methods are checked; legacy examples remain H5-019 |

Exit status: **partial**. Artifact publication improved, but repository hygiene
and release assurance are not complete.

## Phase 5 — New feature candidates

These remain uncommitted candidates. Do not schedule them ahead of the release
gates and active P1 issues.

### Search quality — ⬜ Planned

- wildcard/masked byte patterns beyond current nibble wildcards;
- aligned/unaligned scan options;
- readable/writable/executable region filters;
- saved search sessions with explicit target/module identity;
- cancellable scans and progress reporting.

### Pointer analysis — ⬜ Planned

- configurable pointer width and offset bounds;
- multi-level chain search with deduplication and cancellation;
- module-relative chain persistence;
- revalidation after application restart/ASLR changes.

### Script and plugin platform — ⬜ Planned

- versioned capability manifest;
- scoped permissions for memory, files, network, and native plugins;
- script import/export with provenance and compatibility metadata.

### Diagnostics — ⬜ Planned

- opt-in structured logs with redacted addresses/paths;
- memory/session statistics;
- package/runtime build identity in the UI;
- exportable diagnostic report.

## Dependency order

```text
Required CI + device feedback loops
  ├── bridge argument schema
  ├── package content assertions
  └── device smoke matrix
        ├── close Phase 0/1/2 exits
        └── begin coordinated Phase 3
              ├── ✅ TargetProcess + MemorySession
              ├── runtime coordinator + ✅ modal queue
              ├── store/plugin/builder ownership modules
              └── versioned GVData
```
