# JavaScript frontend contract

Status: current code inventory for the `GUI` branch on 2026-08-05.

This is the canonical reference for JavaScript that runs inside H5GG's iOS
`WKWebView`. It documents the complete frontend contract: engine bridge methods,
window-control functions, host callbacks, injected runtime values, and deprecated
compatibility functions.

## Contract conventions

### Status

- **Stable** — established frontend contract.
- **Experimental** — exposed now, but device coverage or compatibility remains incomplete.
- **Deprecated** — retained only for compatibility; new frontend code must not call it.
- **Internal** — host/bridge plumbing, not an application-facing API.

### Promise and failure behavior

Every `window.h5gg` method and registered global control function returns a
`Promise`. Use `await` even when the native method has no result:

```js
await h5gg.clearResults(); // resolves null
```

The Promise rejects when bridge dispatch fails—for example, an unknown method,
wrong argument count, native exception, unavailable native selector, or a result
that cannot be serialized to JSON. Most operation-level validation does **not**
reject. Depending on the method, it shows a native alert and resolves `null`, or
resolves a sentinel such as `false`, `0`, `""`, `[]`, or an object containing an
`error` field. Check the documented result for every operation.

Only JSON-compatible values cross the `WKWebView` bridge. Functions and native
Objective-C objects cannot be passed through it.

### Common scalar formats

- **Address** — unsigned 64-bit decimal text or `0x`-prefixed hexadecimal text,
  unless a method explicitly requires hexadecimal.
- **Range endpoint** — `0x`-prefixed hexadecimal address.
- **Value type** — `I8`, `U8`, `I16`, `U16`, `I32`, `U32`, `I64`, `U64`, `F32`, or `F64`.
- **Result** — `{ address: string, value: string, type: string }`.

## Allowlisted bridge inventory

This machine-checked list must match `BridgeMethods.cpp` exactly.

<!-- bridge-methods:start -->
- `searchNumber`
- `searchNearby`
- `getValue`
- `setValue`
- `editAll`
- `getResults`
- `getResultsCount`
- `clearResults`
- `getLocalScripts`
- `pickScriptFile`
- `getRangesList`
- `getProcList`
- `setTargetProc`
- `getTargetStatus`
- `loadPlugin`
- `callPlugin`
- `getPluginCapabilities`
- `makeTweak`
- `require`
- `setFloatTolerance`
- `searchChange`
- `searchFilter`
- `getInputHistory`
- `addInputHistory`
- `clearInputHistory`
- `addBookmark`
- `removeBookmark`
- `getBookmarks`
- `clearBookmarks`
- `freezeValue`
- `unfreezeValue`
- `getFrozenValues`
- `clearFrozenValues`
- `searchHex`
- `getSearchHistory`
- `addSearchHistory`
- `clearSearchHistory`
- `dumpMemory`
- `getDumpStatus`
- `cancelDump`
- `readPointer`
- `findPointers`
- `getPointerCapabilities`
- `appendLog`
- `readBytes`
- `readMemoryPage`
- `saveScript`
- `loadScript`
- `deleteScript`
- `listScripts`
- `getLastFileError`
- `copyText`
<!-- bridge-methods:end -->

## Runtime and memory bridge methods

| Method and status | Parameters | Resolves | Side effects, failures, and restrictions | Minimal example | Native source |
|---|---|---|---|---|---|
| `h5gg.require(minVersion)`<br>**Stable** | `minVersion`: numeric H5GG version. | `boolean`; `true` when the runtime is new enough. | Does not change state. An older runtime resolves `false`; legacy JavaScriptCore paths may also set a JS exception. | `if (!await h5gg.require(8.0)) return;` | `h5ggEngine require:` in `h5gg.mm` |
| `h5gg.setFloatTolerance(value)`<br>**Stable** | `value`: non-negative numeric string. | `null`. | Updates tolerance used by float searches. Invalid or negative text shows an alert and leaves the prior tolerance unchanged. | `await h5gg.setFloatTolerance("0.01");` | `h5ggEngine setFloatTolerance:` |
| `h5gg.copyText(text)`<br>**Stable** | `text`: clipboard string. | `boolean`. | Writes the general iOS pasteboard. A missing/null argument is rejected by bridge arity or resolves `false` natively. | `await h5gg.copyText(result.address);` | `h5ggEngine copyText:` |
| `h5gg.searchNumber(value, type, start, end)`<br>**Stable** | `value`: exact number, `a~b` range, or comma-separated group; `type`: value type; `start`, `end`: hexadecimal range endpoints. | `null`. | Starts a scan after `clearResults`, otherwise refines existing results. Updates search history and last result type. Invalid values/ranges or refining an empty list show an alert. Device memory access is required. | `await h5gg.searchNumber("42", "I32", "0x100000000", "0x200000000");` | `h5ggEngine searchNumber:param2:param3:param4:` |
| `h5gg.searchNearby(value, type, range)`<br>**Stable** | `value`, `type`; `range`: hexadecimal byte distance from `2` through `4096`. | `null`. | Replaces current results with nearby matches. Requires existing results; invalid input or an empty list shows an alert. | `await h5gg.searchNearby("7", "I32", "0x100");` | `h5ggEngine searchNearby:param2:param3:` |
| `h5gg.searchChange(change)`<br>**Stable** | `change`: `Unchanged`, `Changed`, `Increased`, or `Decreased`. | `null`. | Refines existing results by change from the saved snapshot. Invalid modes or an empty list show an alert. | `await h5gg.searchChange("Increased");` | `h5ggEngine searchChange:` |
| `h5gg.searchFilter(value, type, mode)`<br>**Experimental** | `value`, `type`; `mode`: `0` equal, `2` greater, `3` less. | Number of results retained. | Mutates the current result set. Invalid values/modes or an empty set resolve `0` and may show an alert. | `const kept = await h5gg.searchFilter("100", "I32", 2);` | `h5ggEngine searchFilter:type:mode:` |
| `h5gg.searchHex(pattern, start, end)`<br>**Experimental** | `pattern`: bytes with optional wildcard nibbles such as `DE AD ?? E?`; hexadecimal endpoints. | `null`. | Starts/refines a byte-pattern search and changes the result type to `Hex`. Invalid patterns/ranges show an alert. | `await h5gg.searchHex("DE AD ?? EF", "0x100000000", "0x200000000");` | `h5ggEngine searchHex:memoryFrom:memoryTo:` |
| `h5gg.getValue(address, type)`<br>**Stable** | Address and value type. | Formatted value string. | Reads selected-process memory. Invalid address/type or unreadable memory resolves `""`; invalid address may show an alert. | `const value = await h5gg.getValue("0x102000000", "I32");` | `h5ggEngine getValue:param2:` |
| `h5gg.setValue(address, value, type)`<br>**Stable** | Address, value string, and value type. | `boolean`. | Writes selected-process memory. Invalid values/addresses or failed writes resolve `false`; invalid address may show an alert. | `const ok = await h5gg.setValue(address, "99", "I32");` | `h5ggEngine setValue:param2:param3:` |
| `h5gg.editAll(value, type)`<br>**Stable** | Value string and value type. | Number of addresses written. | Writes the same value to all current results. Invalid input or an empty list resolves `0`; empty list shows an alert. | `const changed = await h5gg.editAll("0", "I32");` | `h5ggEngine editAll:param3:` |
| `h5gg.getResults(maxCount, skipCount = 0)`<br>**Stable** | Positive maximum count; optional number to skip. | Array of `{address, value, type}`. | Reads current values at result addresses. Allocation failure shows an alert and may return a partial/empty array. | `const page = await h5gg.getResults(100, 0);` | `h5ggEngine getResults:param1:` |
| `h5gg.getResultsCount()`<br>**Stable** | None. | Total current result count. | Read-only. The count may be much larger than a page returned by `getResults`. | `const count = await h5gg.getResultsCount();` | `h5ggEngine getResultsCount` |
| `h5gg.clearResults()`<br>**Stable** | None. | `null`. | Destroys the current search engine/session and creates an empty one for the same target. | `await h5gg.clearResults();` | `h5ggEngine clearResults` |

## Target and image bridge methods

| Method and status | Parameters | Resolves | Side effects, failures, and restrictions | Minimal example | Native source |
|---|---|---|---|---|---|
| `h5gg.getRangesList(filter?)`<br>**Stable** | Optional exact image filename; `"0"` selects the main image. | Array of `{name, start, end}` strings. | Reads loaded Mach-O images for the selected process. With no filter, returns all readable images. Failed cross-process discovery resolves an empty array. | `const images = await h5gg.getRangesList("UnityFramework");` | `h5ggEngine getRangesList:` |
| `h5gg.getProcList(filter?)`<br>**Stable** | Optional exact process name. | Array of `{pid: number, name: string}`. | Lists application processes under `/var/.../Application/`. Requires jailbreak process visibility; enumeration failure resolves `null`. | `const apps = await h5gg.getProcList();` | `h5ggEngine getProcList:` |
| `h5gg.setTargetProc(pid)`<br>**Stable** | Positive process ID. | `boolean`. | Acquires a Mach task port, replaces the memory session, and clears frozen values. Requires `task_for_pid` capability; failure preserves the previous valid target. | `const selected = await h5gg.setTargetProc(app.pid);` | `h5ggEngine setTargetProc:` |
| `h5gg.getTargetStatus()`<br>**Stable** | None. | `{available, pid, selected}`. | Checks the target. If it terminated, invalidates its memory session and frozen values. | `const {available} = await h5gg.getTargetStatus();` | `h5ggEngine getTargetStatus` |

## Persistent frontend state

| Method and status | Parameters | Resolves | Side effects, failures, and restrictions | Minimal example | Native source |
|---|---|---|---|---|---|
| `h5gg.getInputHistory()`<br>**Stable** | None. | Array of strings, newest first. | Reads up to 20 values from `NSUserDefaults`. | `const values = await h5gg.getInputHistory();` | `h5ggEngine getInputHistory` |
| `h5gg.addInputHistory(value)`<br>**Stable** | Non-empty string. | `null`. | Prepends a value, suppresses only an identical first entry, and caps history at 20. Empty input is ignored. | `await h5gg.addInputHistory("42");` | `h5ggEngine addInputHistory:` |
| `h5gg.clearInputHistory()`<br>**Stable** | None. | `null`. | Removes input history from `NSUserDefaults`. | `await h5gg.clearInputHistory();` | `h5ggEngine clearInputHistory` |
| `h5gg.addBookmark(address, name, type)`<br>**Stable** | Address, display name, and value type strings. | `boolean`. | Persists a bookmark. Duplicate addresses or missing fields resolve `false`. It does not validate that the address is currently readable. | `await h5gg.addBookmark(address, "Player health", "I32");` | `h5ggEngine addBookmark:name:type:` |
| `h5gg.removeBookmark(address)`<br>**Stable** | Address string exactly as stored. | `boolean`. | Removes the matching bookmark; missing entries resolve `false`. | `await h5gg.removeBookmark(address);` | `h5ggEngine removeBookmark:` |
| `h5gg.getBookmarks()`<br>**Stable** | None. | Array of `{address, name, type}`. | Reads persisted bookmarks. | `const bookmarks = await h5gg.getBookmarks();` | `h5ggEngine getBookmarks` |
| `h5gg.clearBookmarks()`<br>**Stable** | None. | `null`. | Removes every persisted bookmark. | `await h5gg.clearBookmarks();` | `h5ggEngine clearBookmarks` |
| `h5gg.freezeValue(address, value, type)`<br>**Experimental** | Address, value string, and value type. | `boolean`. | Starts/replaces a 100 ms repeating write for the current target. Invalid target/address/value/type resolves `false`. | `await h5gg.freezeValue(address, "100", "I32");` | `h5ggEngine freezeValue:value:type:` |
| `h5gg.unfreezeValue(address)`<br>**Experimental** | Decimal or hexadecimal address. | `boolean`. | Removes the canonical-address entry; missing/invalid entries resolve `false`. Stops the timer when none remain. | `await h5gg.unfreezeValue(address);` | `h5ggEngine unfreezeValue:` |
| `h5gg.getFrozenValues()`<br>**Experimental** | None. | Sorted array of `{address, value, type, targetPid, status, failures, lastError}`. | Read-only snapshot. Status may be `active`, `target-unavailable`, `invalid`, or `write-failed`. | `const frozen = await h5gg.getFrozenValues();` | `h5ggEngine getFrozenValues` |
| `h5gg.clearFrozenValues()`<br>**Experimental** | None. | `null`. | Removes all entries and stops the freezer timer. | `await h5gg.clearFrozenValues();` | `h5ggEngine clearFrozenValues` |
| `h5gg.getSearchHistory()`<br>**Stable** | None. | Array of `{value, type, count, time}`, newest first. | Reads up to 50 entries from `NSUserDefaults`; `time` is `HH:mm:ss`. | `const history = await h5gg.getSearchHistory();` | `h5ggEngine getSearchHistory` |
| `h5gg.addSearchHistory(value, type, count)`<br>**Stable** | Value string, type string, numeric count. | `null`. | Persists a new timestamped entry and caps history at 50. Missing value is ignored. | `await h5gg.addSearchHistory("42", "I32", count);` | `h5ggEngine addSearchHistory:type:count:` |
| `h5gg.clearSearchHistory()`<br>**Stable** | None. | `null`. | Removes all search-history entries. | `await h5gg.clearSearchHistory();` | `h5ggEngine clearSearchHistory` |

## Files and picker bridge methods

| Method and status | Parameters | Resolves | Side effects, failures, and restrictions | Minimal example | Native source |
|---|---|---|---|---|---|
| `h5gg.getLocalScripts()`<br>**Stable** | None. | Array of `{name, path}` for `.js` and `.html` files. | Reads the app Documents directory and application bundle. Directory failures produce no entries for that location. | `const scripts = await h5gg.getLocalScripts();` | `h5ggEngine getLocalScripts` |
| `h5gg.pickScriptFile(types?)`<br>**Stable** | Optional array of Uniform Type Identifier strings; defaults to `public.data`. | Selected path string or `null` on cancellation. | Presents the native iOS file picker and defers Promise completion until selection/cancellation. | `const path = await h5gg.pickScriptFile(["public.html"]);` | `h5ggEngine pickScriptFileWithTypes:` |
| `h5gg.saveScript(name, content)`<br>**Experimental** | Safe single-entry `.js`/`.html` filename and UTF-8 text. Missing extension becomes `.js`. | `boolean`. | Atomically writes Documents. Rejects paths, unsupported extensions, and content over 2 MiB; inspect `getLastFileError`. | `const ok = await h5gg.saveScript("tool.js", source);` | `h5ggEngine saveScript:content:` |
| `h5gg.loadScript(name)`<br>**Experimental** | Safe `.js`/`.html` filename. | UTF-8 string or `null`. | Reads Documents only. Invalid/missing files set `getLastFileError`. | `const source = await h5gg.loadScript("tool.js");` | `h5ggEngine loadScript:` |
| `h5gg.deleteScript(name)`<br>**Experimental** | Safe `.js`/`.html` filename. | `boolean`. | Removes the Documents file; invalid/missing files resolve `false` and set the last file error. | `await h5gg.deleteScript("tool.js");` | `h5ggEngine deleteScript:` |
| `h5gg.listScripts()`<br>**Experimental** | None. | Case-insensitively sorted filename array. | Lists valid `.js`/`.html` files in Documents. Failure resolves `[]` and sets the last file error. | `const names = await h5gg.listScripts();` | `h5ggEngine listScripts` |
| `h5gg.getLastFileError()`<br>**Experimental** | None. | Error string or `null`. | Returns the latest script-store error; each script-store operation clears it before starting. | `const error = await h5gg.getLastFileError();` | `h5ggEngine getLastFileError` |

## Dumps, raw memory, and pointers

| Method and status | Parameters | Resolves | Side effects, failures, and restrictions | Minimal example | Native source |
|---|---|---|---|---|---|
| `h5gg.dumpMemory(start, end, filename)`<br>**Experimental** | Start/end addresses and safe single-entry output filename. | Final `boolean` after the asynchronous dump finishes. | Streams the range to Documents, retains its target port, updates dump status, and deletes partial files on failure/cancellation. Rejects invalid/overlapping requests with `false`. | `const ok = await h5gg.dumpMemory(start, end, "dump.bin");` | `h5ggEngine dumpMemory:end:filename:` |
| `h5gg.getDumpStatus()`<br>**Experimental** | None. | `{state, progress, written?, total?, path?, error?}`. | Read-only. State is `idle`, `running`, `completed`, `cancelled`, or `failed`; progress is `0...1`. | `const status = await h5gg.getDumpStatus();` | `h5ggEngine getDumpStatus` |
| `h5gg.cancelDump()`<br>**Experimental** | None. | `boolean`. | Requests cancellation of a running dump. Resolves `false` when no dump is running. | `await h5gg.cancelDump();` | `h5ggEngine cancelDump` |
| `h5gg.readPointer(address)`<br>**Experimental** | Address string. | Hexadecimal pointer string or `""`. | Reads one 64-bit unsigned pointer. Invalid/unreadable/null pointers resolve `""`. | `const next = await h5gg.readPointer(address);` | `h5ggEngine readPointer:` |
| `h5gg.readBytes(address, length)`<br>**Experimental** | Address and byte length. | Formatted uppercase hex string with line breaks. | Reads at most 4096 bytes; non-positive or oversized length defaults to 256. Invalid/unreadable address resolves `""`. | `const hex = await h5gg.readBytes(address, 64);` | `h5ggEngine readBytes:length:` |
| `h5gg.readMemoryPage(address, length = 256)`<br>**Experimental** | Address and optional length, capped at 4096. | `{address, length, readable, complete, bytes}` or `{error}`. | `bytes` contains numbers or `null` for unreadable bytes. Errors include `invalid-address` and `address-range-overflow`. | `const page = await h5gg.readMemoryPage(address, 256);` | `h5ggEngine readMemoryPage:length:` |
| `h5gg.findPointers(address, rangeStart, rangeEnd)`<br>**Experimental** | Target address; hexadecimal scan endpoints. | Array of `{address, value}` hexadecimal strings. | Exact, aligned 64-bit pointer search. Invalid input resolves `[]`; engine limits are reported separately. | `const refs = await h5gg.findPointers(target, start, end);` | `h5ggEngine findPointers:rangeStart:rangeEnd:` |
| `h5gg.getPointerCapabilities()`<br>**Experimental** | None. | `{pointerWidth, alignment, exactMatchesOnly, maxResults, maxScannedBytes, maxChainDepth}`. | Read-only capability record; currently 64-bit, 8-byte aligned, 4096 results, 512 MiB scan, depth 32. | `const limits = await h5gg.getPointerCapabilities();` | `h5ggEngine getPointerCapabilities` |

## Plugins, generated dylibs, and logging

| Method and status | Parameters | Resolves | Side effects, failures, and restrictions | Minimal example | Native source |
|---|---|---|---|---|---|
| `h5gg.loadPlugin(className, dylibPath)`<br>**Experimental** | Objective-C class name and absolute path, or bundle-relative dylib path. | WKWebView: `{loaded, id?, className?, rpc?, error?}`. | Loads executable code with `dlopen`. WK plugins must implement `H5GGPluginRPC`; failures are returned in the object. Legacy JavaScriptCore may receive a native object instead. | `const plugin = await h5gg.loadPlugin("MyPlugin", "MyPlugin.dylib");` | `h5ggEngine loadPlugin:path:` |
| `h5gg.callPlugin(pluginId, method, arguments)`<br>**Experimental** | Plugin handle, method string, JSON-compatible argument array. | `{ok: true, result}` or `{ok: false, error}`. | Invokes `H5GGPluginRPC`. Exceptions, plugin errors, unknown handles, and non-JSON results become `{ok:false}`. | `const reply = await h5gg.callPlugin(plugin.id, "status", []);` | `h5ggEngine callPlugin:method:arguments:` |
| `h5gg.getPluginCapabilities()`<br>**Experimental** | None. | Capability object describing RPC, protocol, legacy objects, and JSON restrictions. | Read-only. Use before assuming native-object transport. | `const caps = await h5gg.getPluginCapabilities();` | `h5ggEngine getPluginCapabilities` |
| `h5gg.makeTweak(iconPath, htmlPath)`<br>**Experimental** | Selected icon and HTML filesystem paths. | Localized result-message string. | Generates/signs a customized dylib. Empty paths return a failure message; signing/template errors are reported in the string. Jailbreak/runtime restrictions apply. | `const message = await h5gg.makeTweak(icon, html);` | `h5ggEngine makeTweak:with:` |
| `h5gg.appendLog(message)`<br>**Stable** | Log string. | `null`. | Appends a line to `Documents/h5gg.log`, creating it if necessary. File errors are not surfaced. | `await h5gg.appendLog("search started");` | `h5ggEngine appendLog:` |

## Global window-control functions

These are globals—not properties of `window.h5gg`. They are registered by
`Tweak.mm` and use the same Promise bridge.

| Function and status | Parameters | Resolves | Side effects, failures, and restrictions | Minimal example | Native source |
|---|---|---|---|---|---|
| `setButtonImage(url)`<br>**Stable** | Image URL string. | `boolean`. | Loads the image asynchronously and updates the local floating button. Invalid images, failed requests, data over 512 KiB, or a pending hosted image update resolve `false`; HTTP requests time out after 15 seconds. A hosted GlobalView receives successful updates through the bounded shared buffer. | `await setButtonImage("https://example.test/icon.png");` | `initFloatMenu` block in `Tweak.mm` |
| `setButtonAction()`<br>**Stable** | None. | `null`. | Enables custom button callbacks. Define `window.h5gg_onButtonClick` first. | `window.h5gg_onButtonClick = openPanel; await setButtonAction();` | `initFloatMenu` block in `Tweak.mm` |
| `setWindowRect(x, y, width, height)`<br>**Stable** | Integer points. `x === -1 && y === -1` preserves current origin. | `null`. | Asynchronously changes the WKWebView frame and shared GlobalView rect. No bounds validation is applied. | `await setWindowRect(-1, -1, 560, 420);` | `initFloatMenu` block in `Tweak.mm` |
| `setWindowDrag(x, y, width, height)`<br>**Stable** | Integer rectangle in view coordinates. | `null`. | Sets the region from which pan gestures may drag the menu. | `await setWindowDrag(0, 0, 560, 44);` | `initFloatMenu` block in `Tweak.mm` |
| `setWindowTouch(x, y, width, height)`<br>**Experimental** | Either `(0|1,0,0,0)` for global touchability or a touch rectangle. | `null`. | Updates hit-testing/shared GlobalView state. Rectangle mode is host-sensitive; validate on the target distribution. | `await setWindowTouch(1, 0, 0, 0);` | `initFloatMenu` block in `Tweak.mm` |
| `setWindowVisible(visible)`<br>**Stable** | Boolean. | `null`. | Shows/hides the menu locally or requests the hosted GlobalView visibility change. | `await setWindowVisible(false);` | `initFloatMenu` block in `Tweak.mm` |
| `setLayoutAction()`<br>**Stable** | None. | `null`. | Requests an immediate layout notification. Define `window.h5gg_onLayoutChange`; do not pass a callback through the Promise bridge. | `window.h5gg_onLayoutChange = (w,h) => {}; await setLayoutAction();` | `initFloatMenu` block in `Tweak.mm` |
| `closeMenu()`<br>**Deprecated** | None. | `null`. | Shows a deprecation alert. Use `setWindowVisible(false)`. | `await setWindowVisible(false);` | Compatibility block in `Tweak.mm` |
| `setFloatButton()`<br>**Deprecated** | None. | `null`. | Shows a deprecation alert. Use `setButtonImage`. | `await setButtonImage(url);` | Compatibility block in `Tweak.mm` |
| `setFloatWindow()`<br>**Deprecated** | None. | `null`. | Shows a deprecation alert. Use `setWindowRect`. | `await setWindowRect(x, y, w, h);` | Compatibility block in `Tweak.mm` |

## Host callbacks

The frontend defines these optional globals; the host invokes them directly.
They do not return a meaningful value to native code.

| Callback and status | Arguments | Trigger and restrictions | Minimal definition | Native source |
|---|---|---|---|---|
| `window.h5gg_onLayoutChange(width, height)`<br>**Stable** | Available host width and height in points. | Called on host layout changes and after `setLayoutAction()`. Keep work short; call `setWindowRect` separately if resizing. | `window.h5gg_onLayoutChange = (w, h) => console.log(w, h);` | `onScreenLayoutChange` in `Tweak.mm` |
| `window.h5gg_onButtonClick()`<br>**Stable** | None. | Called after `setButtonAction()` when the floating button reports a custom click. | `window.h5gg_onButtonClick = () => openPanel();` | GlobalView timer/button path in `Tweak.mm` |
| `window.onerror` / `window.h5gg_js_error_handler`<br>**Internal** | Standard browser error arguments. | Installed by `initial.js`; logs and presents a localized alert for uncaught JavaScript errors. Replacing it disables built-in reporting. | No application definition required. | `initial.js` |

## Injected runtime values and internal bridge names

| Name and status | Shape | Meaning and restrictions | Native source |
|---|---|---|---|
| `window.h5gg`<br>**Stable** | Object containing every allowlisted method above. | Created at document start. Treat method names as the public engine interface. | `_bridgeSource` in `FloatMenu.mm` |
| `window.h5gg_internel_version`<br>**Stable** | Number. | Current native H5GG version. The misspelling is part of the compatibility contract. | `_onBridgeReady` in `FloatMenu.mm` |
| `window.h5gg_mainframe_reload`<br>**Internal** | Boolean. | Marks that bridge-ready initialization has run for the main frame. Do not modify. | `_onBridgeReady` in `FloatMenu.mm` |
| `window.__h5ggPM`<br>**Internal** | Boolean. | Prevents duplicate bridge injection. Do not modify. | `_bridgeSource` in `FloatMenu.mm` |
| `window.__h5gg_native(method, args)`<br>**Internal** | Promise-returning function. | Low-level message sender. Application code must call allowlisted wrappers instead. | `_bridgeSource` in `FloatMenu.mm` |
| `window.__h5gg_onResult(callId, error, result)`<br>**Internal** | Function. | Settles pending bridge Promises. Calling or replacing it can strand every frontend operation. | `_bridgeSource` in `FloatMenu.mm` |

## Complete example

```js
async function findAndCopyFirstMatch() {
    if (!await h5gg.require(8.0)) return;

    await h5gg.clearResults();
    await h5gg.searchNumber(
        "42",
        "I32",
        "0x100000000",
        "0x200000000"
    );

    const count = await h5gg.getResultsCount();
    if (count === 0) return;

    const [result] = await h5gg.getResults(1, 0);
    if (result) {
        await h5gg.copyText(`${result.address} = ${result.value} [${result.type}]`);
    }
}
```

## Sources of truth

- Allowlisted method names and arity: `BridgeMethods.cpp`
- Engine declarations: `h5gg.h`
- Native behavior and schemas: `h5gg.mm`
- Promise transport and injected names: `FloatMenu.mm`
- Window controls and host callbacks: `Tweak.mm`
- Initial error hook: `initial.js`
- Advanced feature support boundary: `docs/phase-2-features.md`
