#include "BridgeMethods.h"

#include <cstring>

static const H5GGBridgeMethod kBridgeMethods[] = {
    {"searchNumber", "searchNumber:param2:param3:param4:", 4, 4},
    {"searchNearby", "searchNearby:param2:param3:", 3, 3},
    {"getValue", "getValue:param2:", 2, 2},
    {"setValue", "setValue:param2:param3:", 3, 3},
    {"editAll", "editAll:param3:", 2, 2},
    {"getResults", "getResults:param1:", 1, 2},
    {"getResultsCount", "getResultsCount", 0, 0},
    {"clearResults", "clearResults", 0, 0},
    {"getLocalScripts", "getLocalScripts", 0, 0},
    {"pickScriptFile", "pickScriptFileWithTypes:", 0, 1},
    {"getRangesList", "getRangesList:", 0, 1},
    {"getProcList", "getProcList:", 0, 1},
    {"setTargetProc", "setTargetProc:", 1, 1},
    {"getTargetStatus", "getTargetStatus", 0, 0},
    {"loadPlugin", "loadPlugin:path:", 2, 2},
    {"callPlugin", "callPlugin:method:arguments:", 3, 3},
    {"getPluginCapabilities", "getPluginCapabilities", 0, 0},
    {"makeTweak", "makeTweak:with:", 2, 2},
    {"require", "require:", 1, 1},
    {"setFloatTolerance", "setFloatTolerance:", 1, 1},
    {"searchChange", "searchChange:", 1, 1},
    {"searchFilter", "searchFilter:type:mode:", 3, 3},
    {"getInputHistory", "getInputHistory", 0, 0},
    {"addInputHistory", "addInputHistory:", 1, 1},
    {"clearInputHistory", "clearInputHistory", 0, 0},
    {"addBookmark", "addBookmark:name:type:", 3, 3},
    {"removeBookmark", "removeBookmark:", 1, 1},
    {"getBookmarks", "getBookmarks", 0, 0},
    {"clearBookmarks", "clearBookmarks", 0, 0},
    {"freezeValue", "freezeValue:value:type:", 3, 3},
    {"unfreezeValue", "unfreezeValue:", 1, 1},
    {"getFrozenValues", "getFrozenValues", 0, 0},
    {"clearFrozenValues", "clearFrozenValues", 0, 0},
    {"searchHex", "searchHex:memoryFrom:memoryTo:", 3, 3},
    {"getSearchHistory", "getSearchHistory", 0, 0},
    {"addSearchHistory", "addSearchHistory:type:count:", 3, 3},
    {"clearSearchHistory", "clearSearchHistory", 0, 0},
    {"dumpMemory", "dumpMemory:end:filename:", 3, 3},
    {"getDumpStatus", "getDumpStatus", 0, 0},
    {"cancelDump", "cancelDump", 0, 0},
    {"readPointer", "readPointer:", 1, 1},
    {"findPointers", "findPointers:rangeStart:rangeEnd:", 3, 3},
    {"getPointerCapabilities", "getPointerCapabilities", 0, 0},
    {"appendLog", "appendLog:", 1, 1},
    {"readBytes", "readBytes:length:", 2, 2},
    {"readMemoryPage", "readMemoryPage:length:", 1, 2},
    {"saveScript", "saveScript:content:", 2, 2},
    {"loadScript", "loadScript:", 1, 1},
    {"deleteScript", "deleteScript:", 1, 1},
    {"listScripts", "listScripts", 0, 0},
    {"getLastFileError", "getLastFileError", 0, 0},
    {"copyText", "copyText:", 1, 1},
};

const H5GGBridgeMethod* H5GGBridgeMethods(size_t& count) {
    count = sizeof(kBridgeMethods) / sizeof(kBridgeMethods[0]);
    return kBridgeMethods;
}

const H5GGBridgeMethod* H5GGBridgeMethodNamed(const char* name) {
    if(!name) {
        return nullptr;
    }

    size_t count = 0;
    const H5GGBridgeMethod* methods = H5GGBridgeMethods(count);
    for(size_t index = 0; index < count; index++) {
        if(std::strcmp(methods[index].name, name) == 0) {
            return &methods[index];
        }
    }
    return nullptr;
}
