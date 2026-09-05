# Stabilization validation matrix

Baseline: iOS 15.0+, arm64/arm64e, with normal, rootless, and roothide package
schemes. A checked build is not a substitute for the device checks below.

## Automated checks

Run:

```sh
bash tests/run_tests.sh
```

The host suite covers:

- result counts and typed/untyped result invariants;
- signed, unsigned, floating-point, and invalid value parsing;
- equal/greater/less result filtering through an in-memory reader;
- clamped raw, exact, and typed reads through buffer and fault-injecting
  adapters, including address overflow;
- strict hexadecimal pattern parsing;
- wildcard hex matching and result refinement;
- partial memory pages with unreadable-byte markers;
- streaming dump progress, cancellation, and failure behavior;
- dump-controller validation, overlap rejection, reader-lease release,
  real-file publication/removal, and deferred completion;
- exact aligned 64-bit pointer matching with range, result, byte, and overflow
  limits through the production reader-backed scanner;
- freezer validation, target binding, typed writes, failure/recovery, and
  deterministic timer start/stop through injected production seams;
- file-picker type normalization, independent originating call IDs,
  cancellation, overlap, and racing exactly-once completion;
- isolated preference-store history caps, bookmark uniqueness, malformed-value
  filtering, timestamps, removal, and clearing;
- atomic multi-slice dylib construction, failure cleanup, and host `ldid`
  signing through the production builder interface;
- bridge method allowlisting and argument ranges;
- user-controlled filename confinement;
- plugin path resolution, image caching, legacy/WK modes, opaque handles, JSON
  validation, and plugin error/exception conversion with injected adapters;
- exactly-once runtime readiness, monitor start/stop, mode queries, and retained
  resource teardown through `RuntimeCoordinator`;
- GlobalView magic/version/size/capability rejection and bounded single-slot
  image publication/consumption through the production protocol interface;
- exactly one `H5GG_BUILD_*` definition for every Theos scheme when `THEOS` is
  configured.

The build and manual-release workflows run this suite before packaging. Every
artifact produced by `build.sh` is then unpacked with the portable package
checker, which asserts:

- package name/version, scheme-specific architecture, dependency, and positive
  installed size;
- rootful/roothide `/Library` versus rootless `/var/jb/Library` paths;
- exactly one non-empty `H5GG.dylib`/`H5GG.plist` pair and an executable
  `preinst`;
- a valid non-empty `Filter.Bundles` plist and exactly arm64/arm64e Mach-O
  slices.

List the supported commands directly from the root Makefile:

```sh
make help
```

Compile the rootful tweak without producing or replacing package artifacts:

```sh
make clean all
```

Build and validate all package variants with:

```sh
./build.sh all
```

Invalid artifacts are rejected before collection or publication.

## Phase 2 device runner

The validation fixture and runner make the non-interactive Phase 2 memory rows
repeatable. They are deliberately excluded from default and release builds.
Build an instrumented package for the scheme installed on the test device; for
example, the rootful package is:

```sh
make package-normal FINALPACKAGE=1 H5GG_DEVICE_VALIDATION=1
```

Use `package-rootless` or `package-roothide` instead when appropriate. Do not
use `build.sh` for an instrumented build, because `build.sh` is the release
artifact workflow.

Install the package only on validation hardware, inject it into the chosen test
application, open the H5GG menu, load
`examples-JavaScript/h5ggV8/phase2DeviceValidation.js`, then run:

```js
await runH5GGPhase2DeviceValidation({
    device: "test device name",
    ios: "iOS version",
    jailbreak: "jailbreak/bootstrap and version",
    scheme: "normal, rootless, or roothide",
    mode: "injected or standalone",
});
```

The runner locates a fixed-layout fixture inside `H5GG.dylib` and records a
JSON report in `Documents/h5gg.log` and the clipboard. The report includes the
supplied device metadata, user agent, selected-target status, pointer
capabilities, and resolved fixture module. Its 15 checks exercise real WK
unknown-method rejection, numeric searches for every type, grouped/refined
search, equal/greater/less filters, mixed-case wildcard hex search/refinement,
typed reads/writes, freezer teardown, exact pointer reads/search, partial page
reads, dump completion/cancellation/failure, partial-file cleanup, and the
script-store path policy. Run it once in an injected self-target and again from
the standalone UI after selecting the same process to cover the cross-process
adapter.

The file picker, plugin demo, generated-dylib loading, target termination,
GlobalView/orientation, floating-button presentation, and package
install/uninstall rows remain interactive checks. A runner report is evidence,
not an automatic completion marker: record the hardware, iOS version,
jailbreak/bootstrap, package scheme, mode, and report result below before
changing a row to complete.

## Device smoke matrix

Record the device, iOS version, jailbreak/bootstrap, package scheme, and result
for every row.

| Mode | Scenario | Execution | Expected result |
|---|---|---|---|
| Injected dylib | Launch target application | Interactive | Floating button and menu appear without changing the app's key window |
| Injected dylib | Search/read/write known local value | Runner | Exact search finds the address and write is observable |
| Standalone | Select a running application | Interactive setup + runner | Selection succeeds and the next read uses that application's task port |
| Standalone | Switch target twice | Interactive | Results and frozen values do not leak between targets |
| Standalone | Invalid/terminated target | Interactive | Operation fails without corrupting the current session |
| Any | Numeric first/refine search for every type | Runner | Counts, values, and types remain consistent |
| Any | Equal/greater/less result filter | Runner | Returned count equals displayed result count |
| Any | Hex first/refine search with mixed-case and `?` wildcards | Runner | Matches refine in place and are returned as byte results |
| Any | Invalid/odd-length hex search | Interactive | Search is rejected without changing the current session |
| Any | Read 256 bytes across a protection boundary | Runner | Viewer shows readable bytes and `??` for each unreadable byte |
| Any | Dump across a readable page | Runner | Progress reaches 100%; file length and contents match memory |
| Any | Cancel a multi-page dump | Runner | Promise settles false and no partial file remains |
| Any | Dump crossing an unreadable page | Runner | Status identifies the failure and no partial file remains |
| Any | Cancel and overlap file pickers | Interactive | Every Promise settles once with the correct call ID |
| Any | Post unknown bridge method | Runner | Promise rejects and no Objective-C selector is invoked |
| Any | Save/load/delete script | Runner | Valid `.js`/`.html` names work; traversal names are rejected |
| Any | Load an `H5GGPluginRPC` demo plugin | Interactive | Handle loads and JSON calls/results cross the WK bridge |
| Any | Generate and load a custom dylib | Interactive | Both architecture slices are signed; custom icon/menu load |
| Any | Terminate selected target with frozen values | Interactive | Session invalidates and entries report/clear target state safely |
| Any | Search exact 64-bit pointers | Runner + interactive limits | Results stop at documented limits and chains stop at 32 reads |
| GlobalView | Host/unhost supported application | Interactive | View and button state synchronize without a SpringBoard crash |
| GlobalView | Rotate and switch applications | Interactive | Orientation and configured dismissal behavior apply |
| Rootful | Install/uninstall normal package | Interactive | Files use rootful paths and runtime launches |
| Rootless | Install/uninstall rootless package | Interactive | Files use rootless paths and runtime launches |
| Roothide | Install/uninstall roothide package | Interactive | Paths are translated and runtime launches |

## Current evidence

As of 2026-08-24 for version 8.1:

- host tests pass;
- browser regression checks pass for the English and Chinese built-in menus,
  including their shared reliability layer;
- normal, rootless, and roothide arm64/arm64e compilation passes;
- rootful, rootless, and roothide path normalization is covered by source and
  variant checks; device install paths remain part of the hardware matrix;
- normal, rootless, and roothide package control metadata and installed layouts
  pass the artifact verifier;
- universal dylib build, atomic publication, and host signing integration pass;
- PluginLoader's macOS Foundation contract tests pass;
- RuntimeCoordinator and GlobalView protocol host contract tests pass;
- FreezerController, FilePickerRequest, PreferencesStore, and reader-backed
  PointerSearch host contract tests pass;
- DumpController lifecycle and real temporary-file contract tests pass;
- the Phase 2 fixture layout and all 15 runner checks pass through a mocked
  Promise bridge on host; runner syntax and public API usage are checked;
- instrumented arm64/arm64e builds include the fixture only when
  `H5GG_DEVICE_VALIDATION=1`; clean default builds exclude it;
- the root, standalone, GlobalView, Xcode, and packaged-host metadata are
  regression-checked at the iOS 15.0 deployment baseline;
- the standalone Xcode host builds unsigned for arm64 with a 15.0 Mach-O and
  application minimum;
- plist and entitlement linting passes;
- device rows remain unverified and must be completed before a stable release.
