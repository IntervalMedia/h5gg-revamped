# Stabilization and feature roadmap

Last verified: 2026-08-20.

## Status legend and current phase

| Status | Meaning |
|---|---|
| ✅ Complete | Implemented and covered by the available host/build verification |
| 🟡 Partial | Implemented in part or awaiting a required verification gate |
| ⬜ Planned | No material implementation of the roadmap outcome yet |

**Current phase: Phase 2 device exit validation and Phase 3 final façade extraction.**
The Phase 0–2 implementation is largely present, but the project has not met
the device release gates. Phase 3 now has host/build-verified
modules for the bridge, value, target/session, reader/pointer policy, modal and
file-picker lifecycle, freezer ownership, script persistence, plugin loading,
dylib building, runtime lifecycle, and GlobalView protocol. Dump orchestration
still remains in the façade, so Phase 3 is not closed. Phase 4 is partially underway.

## Phase summary

| Phase | Status | Current outcome |
|---|---|---|
| Phase 0 — Freeze and reproduce | 🟡 Partial | Host harness and device matrix exist; native bridge/device repro coverage is incomplete |
| Phase 1 — Core correctness | 🟡 Partial | Core fixes, bridge validation, and package layouts are host/CI-verified; device gates remain |
| Phase 2 — Complete v8 features | 🟡 Partial | Feature implementation is present; hardware-dependent rows remain experimental |
| Phase 3 — Deepen the modules | 🟡 Partial | Planned modules plus preferences/freezer/picker/pointer seams are host/build-verified; dump orchestration remains H5-015 |
| Phase 4 — Delivery and repository health | 🟡 Partial | Variant builds, artifact assertions, and CI host tests are present; tracked artifacts, provenance, and logging remain |
| Phase 5 — New feature candidates | ⬜ Planned | Candidate backlog only |

## Release gates

| Gate | Status | Evidence or next action |
|---|---|---|
| Host suite covers codecs, results, typed/raw/pointer reads, bridge inventory, deferred/freezer lifecycle, persistence, runtime/GlobalView contracts, and dylib building | ✅ Complete | `bash tests/run_tests.sh` passes locally |
| Host suite is required in CI | ✅ Complete | Build and manual-release workflows run it before packaging |
| Local and cross-process numeric/byte sessions pass on device | ⬜ Planned | Record [validation.md](validation.md) rows |
| Every JavaScript Promise settles once | 🟡 Partial | Picker path is implemented; native/device overlap matrix remains |
| Bridge validates method names, counts, argument kinds, and numeric constraints | ✅ Complete | Shared schema is host-tested and enforced before `NSInvocation` |
| Normal/rootless/roothide package contents and paths are asserted | ✅ Complete | Every generated `.deb` is unpacked and checked before publication |
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
| Separate typed and raw memory interfaces | ✅ Complete | `MemoryReader` derives validated typed/exact reads from one partial-byte primitive; host page/dump adapters use the same seam |
| Central result model and invariant-safe filtering | ✅ Complete | `Result`, `MemoryFilter`, and masked-hex refinement tests |
| Native bridge allowlist | ✅ Complete | `BridgeMethods` is required before selector creation |
| Bridge argument-kind/range validation | ✅ Complete | Shared schema rejects malformed values before `NSInvocation` |
| Variant compiler definitions | ✅ Complete | One definition per normal/rootless/roothide dry run |
| Variant package content assertions | ✅ Complete | Control fields/architecture/dependency, exact installed paths, executable `preinst`, plist filter, and arm64/arm64e slices are checked for every `.deb` |
| Device verification of search/read/write and target switching | ⬜ Planned | Use `validation.md` |

Exit status: **partial**. Core implementation, host checks, and package-content
assertions pass; device checks prevent the phase from being closed.

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
| Value freezer | ✅ Complete | ✅ Entry validation, target binding, writes, failure/recovery, and deterministic timer lifecycle through `FreezerController` | ⬜ Pending |
| Script editor/store policy | ✅ Complete | ✅ Names/extensions and JS actions | ⬜ Pending |
| Native plugin RPC | ✅ Complete | ✅ Loader modes, image caching, handles, JSON validation, errors, and exceptions | ⬜ Pending |
| Dylib generation | ✅ Complete | ✅ Builder validation, atomic multi-slice replacement, cleanup, and host signing | ⬜ Pending |
| File picker | ✅ Complete | ✅ Type normalization, originating call IDs, cancellation, overlap, and racing exactly-once completion through `FilePickerRequest` | ⬜ Pending |
| Pointer tools | ✅ Complete with documented limits | ✅ Exact aligned matcher plus result/range/byte limits through `PointerSearch`; Mach enumeration remains device-only | ⬜ Pending |
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
| Add a raw/typed reader seam with in-memory adapters | ✅ Complete | Engine snapshots/refinement, filters, façade reads, pages, dumps, and pointer matching use `MemoryReader`; buffer and callback adapters are host-tested |
| Replace ad hoc result mutation with one result module | ✅ Complete | `MemoryResults` owns mutation/count invariants |
| Use one bridge schema for dispatch, injection, validation, and docs | ✅ Complete | Production method/argument structures drive injection and dispatch; a linked host verifier generates/checks the documentation table |
| Add `ScriptStore` | ✅ Complete | Confined regular-file persistence, UTF-8/size rules, atomic writes, deterministic listing, and errors are host-tested through the production interface |
| Add `PreferencesStore` | ✅ Complete | Input/search history caps, bookmark uniqueness, malformed persisted-value filtering, and deterministic timestamps are Foundation-tested through the production interface |
| Add `PluginLoader` | ✅ Complete | Image caching, legacy/WK modes, opaque handle ownership, JSON validation, invocation, and error conversion are tested through injected adapters |
| Add `DylibBuilder` | ✅ Complete | Regular-file inputs, bounded payloads, image/menu validation seam, all-slice replacement, signing, cleanup, and atomic publication are host/integration-tested |
| Replace bootstrap globals/timers with a runtime coordinator | ✅ Complete | Modes, exactly-once readiness, owned monitoring timers, floating UI retention, and teardown use `RuntimeCoordinator`; its Foundation contract test crosses the production interface |
| Make modal presentation request-scoped and serial | ✅ Complete | FIFO request state, exactly-once completion, cancellation promotion, and blocking waits are host-tested; UIKit adapter builds for both slices |
| Extract freezer and file-picker lifecycle | ✅ Complete | `FreezerController` owns target-bound writes and one scheduler token; `FilePickerRequest` owns the originating call ID and exactly-once completion; deterministic Foundation tests cross both production interfaces |
| Extract dump orchestration from the façade | ⬜ Planned | Streaming is in `MemoryDump`, but request state, target-port retention, file publication, async completion, and cancellation still live in `h5ggEngine` (H5-015) |
| Version the `GVData` shared-memory interface | ✅ Complete | Fixed-width magic/version/size/capability headers are validated by both peers; incompatible hosts fail closed and images use a separate bounded single-slot transfer |

Exit status: **active and partial**. The planned modules and newly identified
preference/freezer/picker/pointer seams are implemented and covered by available
host/build verification. Dump orchestration still prevents Phase 3 closure;
cross-process Mach and UIKit behavior remains gated by the Phase 2 device matrix.

## Phase 4 — Delivery and repository health

Goal: make releases reproducible and the repository navigable.

| Work item | Status | Current state / outcome |
|---|---|---|
| Stop tracking generated packages and Xcode user state | 🟡 Partial | Ignore rules improved; already tracked files remain (H5-018) |
| Inventory/checksum prebuilt dependencies and provenance | ⬜ Planned | H5-018 |
| Choose a policy for the nested Dobby source | ⬜ Planned | H5-018 |
| Separate build, package, and release verification | ✅ Complete | `build.sh` isolates artifacts, rejects invalid packages before collection, and publishes only verified outputs |
| Remove hardcoded local device addresses | ✅ Complete | Only a commented example remains |
| Run host verification in CI before packaging | ✅ Complete | Both build and manual-release workflows gate packaging on `tests/run_tests.sh` |
| Gate/redact verbose logs and add opt-in diagnostics | ⬜ Planned | H5-020 |
| Maintain complete JavaScript reference documentation | ✅ Complete | All 52 methods and native argument constraints are generated/checked; WK examples are awaited and native-object examples are explicitly labelled |

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
  ├── ✅ package content assertions
  └── device smoke matrix
        ├── close Phase 0/1/2 exits
        └── Phase 3 module implementation
              ├── ✅ TargetProcess + MemorySession
              ├── ✅ runtime coordinator + modal queue
              ├── ✅ store/plugin/builder ownership modules
              ├── ✅ preferences/freezer/picker/pointer modules
              ├── ⬜ dump orchestration module
              └── ✅ versioned GVData + bounded image transfer
```
