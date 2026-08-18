**************** H5GG JavaScript Engine Document (v8.0, WKWebView, async API) ********************

WARNING: This is H5GG-Revamped v8.0 with a new WKWebView bridge. All h5gg methods now return Promises and must be called with await. These APIs will NOT work with old H5GG versions (< v8.0).

Dual support (old sync style + new async) may be added in a future release.

h5gg is the engine object, which can call the following functions:

await h5gg.require(H5GG version number); //Set the minimum H5GG version number required by the script, can be written at the start of the script

h5gg.setFloatTolerance('floating-point deviation'); //Set the deviation range of F32/F64 floating-point search, engine defaults to 0.0

await h5gg.searchNumber('value', 'type', 'search lower limit', 'search upper limit'); //Search or refine exact value

await h5gg.searchNearby('value', 'type', 'adjacent range'); //Nearby search

await h5gg.getValue('address', 'type'); //Read value at address, returns value string

await h5gg.setValue('Address', 'Value', 'Type'); //Set value at address, returns success/failure

await h5gg.editAll('value', 'type'); //Modify all search results, returns count of successful modifications

await h5gg.getResultsCount(); //Get total number of search results

await h5gg.getResults('GetCount', 'SkipCount'); //Get result array, each element has address, value, type

await h5gg.clearResults(); //Clear search results

await h5gg.getRangesList('module file name'); //Return module array with start, end, name attributes
(module file name=0 returns app main module, no argument returns all modules)

const plugin = await h5gg.loadPlugin('Objective-C Class Name','dylib file path'); //WK plugins implement H5GGPluginRPC and return a JSON handle
const reply = await h5gg.callPlugin(plugin.id, 'method name', ['JSON argument']); //Returns {ok,result} or {ok:false,error}

await h5gg.searchHex('DE AD ?? E?', '0x0', '0x200000000'); //First call searches; later calls refine. ? is a wildcard nibble.
await h5gg.searchFilter('100', 'I32', 0); //Filter current results: 0 equal, 2 greater, 3 less
await h5gg.readMemoryPage('0x1000', 256); //Returns byte numbers/null markers, readable count, and complete flag
await h5gg.dumpMemory('0x1000', '0x2000', 'dump.bin'); //Streams asynchronously; inspect getDumpStatus() or call cancelDump()

For standalone CrosProc APP version only:

await h5gg.setTargetProc(process number); //Set target process, returns success/failure

await h5gg.getProcList('process name'); //Get process array with pid, name attributes
(no argument returns all processes)

Other APIs (these are async but their return values are usually not needed):

setButtonImage(icon); //Set floating button icon (http URL or base64)

setButtonAction(js callback function); //Custom floating button click action

setWindowRect(x, y, width, height); //Set floating window position and size

setWindowDrag(x, y, width, height); //Set draggable area on the H5 page

setWindowTouch(bool); //true = window touch-through, false = window captures touch

setWindowVisible(bool); //Show or hide the floating window

setLayoutAction(js callback function); //Callback when screen rotates or iPad split screen changes, parameters (width, height)

Notes:

1: Address supports decimal or 0x-prefixed hex, other params must be strings

2: Float types: F32, F64. Signed: I8, I16, I32, I64. Unsigned: U8, U16, U32, U64

3: For large result sets, get results in sections to avoid memory issues

4: Results are always strings. Use Number(x) for arithmetic

5: Use x.toString(16) for hex conversion (x must be a number)

6: Search supports range format like "50~100" in both searchNumber and searchNearby

7: All h5gg calls are now async and return Promises. Wrap scripts in async functions and use await.

8: Existing scripts that use synchronous h5gg calls must be updated for v8.0.

9: Default floating window size is 370x370. Position and size can be changed via JS API.
