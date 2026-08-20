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

Compile the tweak without producing or replacing package artifacts:

```sh
make -j2
```

Build and validate all package variants with:

```sh
./build.sh all
```

Invalid artifacts are rejected before collection or publication.

## Device smoke matrix

Record the device, iOS version, jailbreak/bootstrap, package scheme, and result
for every row.

| Mode | Scenario | Expected result |
|---|---|---|
| Injected dylib | Launch target application | Floating button and menu appear without changing the app's key window |
| Injected dylib | Search/read/write known local value | Exact search finds the address and write is observable |
| Standalone | Select a running application | Selection succeeds and the next read uses that application's task port |
| Standalone | Switch target twice | Results and frozen values do not leak between targets |
| Standalone | Invalid/terminated target | Operation fails without corrupting the current session |
| Any | Numeric first/refine search for every type | Counts, values, and types remain consistent |
| Any | Equal/greater/less result filter | Returned count equals displayed result count |
| Any | Hex first/refine search with mixed-case and `?` wildcards | Matches refine in place and are returned as byte results |
| Any | Invalid/odd-length hex search | Search is rejected without changing the current session |
| Any | Read 256 bytes across a protection boundary | Viewer shows readable bytes and `??` for each unreadable byte |
| Any | Dump across a readable page | Progress reaches 100%; file length and contents match memory |
| Any | Cancel a multi-page dump | Promise settles false and no partial file remains |
| Any | Dump crossing an unreadable page | Status identifies the failure and no partial file remains |
| Any | Cancel and overlap file pickers | Every Promise settles once with the correct call ID |
| Any | Post unknown bridge method | Promise rejects and no Objective-C selector is invoked |
| Any | Save/load/delete script | Valid `.js`/`.html` names work; traversal names are rejected |
| Any | Load an `H5GGPluginRPC` demo plugin | Handle loads and JSON calls/results cross the WK bridge |
| Any | Generate and load a custom dylib | Both architecture slices are signed; custom icon/menu load |
| Any | Terminate selected target with frozen values | Session invalidates and entries report/clear target state safely |
| Any | Search exact 64-bit pointers | Results stop at documented limits and chains stop at 32 reads |
| GlobalView | Host/unhost supported application | View and button state synchronize without a SpringBoard crash |
| GlobalView | Rotate and switch applications | Orientation and configured dismissal behavior apply |
| Rootful | Install/uninstall normal package | Files use rootful paths and runtime launches |
| Rootless | Install/uninstall rootless package | Files use rootless paths and runtime launches |
| Roothide | Install/uninstall roothide package | Paths are translated and runtime launches |

## Current evidence

As of 2026-08-20:

- host tests pass;
- normal, rootless, and roothide arm64/arm64e compilation passes;
- normal, rootless, and roothide package control metadata and installed layouts
  pass the artifact verifier;
- universal dylib build, atomic publication, and host signing integration pass;
- PluginLoader's macOS Foundation contract tests pass;
- RuntimeCoordinator and GlobalView protocol host contract tests pass;
- FreezerController, FilePickerRequest, PreferencesStore, and reader-backed
  PointerSearch host contract tests pass;
- plist and entitlement linting passes;
- device rows remain unverified and must be completed before a stable release.
