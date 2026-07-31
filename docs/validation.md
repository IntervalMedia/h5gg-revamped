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
- strict hexadecimal pattern parsing;
- bridge method allowlisting and argument ranges;
- user-controlled filename confinement;
- exactly one `H5GG_BUILD_*` definition for every Theos scheme when `THEOS` is
  configured.

Compile the tweak without producing or replacing package artifacts:

```sh
make -j2
```

Package validation should use `./build.sh` only in a clean release checkout
because its clean targets intentionally replace generated package outputs.

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
| Any | Hex search with spaced/mixed-case bytes | Matches are returned as byte results |
| Any | Invalid/odd-length hex search | Search is rejected without changing the current session |
| Any | Read 256 raw bytes | Viewer shows only bytes actually read |
| Any | Dump across a readable page | File length and contents match memory |
| Any | Dump crossing an unreadable page | No uninitialized output is written |
| Any | Cancel and overlap file pickers | Every Promise settles once with the correct call ID |
| Any | Post unknown bridge method | Promise rejects and no Objective-C selector is invoked |
| Any | Save/load/delete script | Valid `.js`/`.html` names work; traversal names are rejected |
| GlobalView | Host/unhost supported application | View and button state synchronize without a SpringBoard crash |
| GlobalView | Rotate and switch applications | Orientation and configured dismissal behavior apply |
| Rootful | Install/uninstall normal package | Files use rootful paths and runtime launches |
| Rootless | Install/uninstall rootless package | Files use rootless paths and runtime launches |
| Roothide | Install/uninstall roothide package | Paths are translated and runtime launches |

## Current evidence

As of 2026-07-31:

- host tests pass;
- normal arm64/arm64e compilation passes;
- rootless and roothide sources compile with their distinct definitions;
- plist and entitlement linting passes;
- device rows remain unverified and must be completed before a stable release.
