#include "BridgeMethods.h"

#include <cmath>
#include <cstring>
#include <limits>

namespace {

constexpr H5GGBridgeArgument kString = {
    H5GGBridgeValueString, false, false, false, 0, 0, nullptr, 0,
};

constexpr H5GGBridgeArgument kOptionalString = {
    H5GGBridgeValueString | H5GGBridgeValueNull,
    false, false, false, 0, 0, nullptr, 0,
};

constexpr H5GGBridgeArgument kOptionalArray = {
    H5GGBridgeValueArray | H5GGBridgeValueNull,
    false, false, false, 0, 0, nullptr, 0,
};

constexpr H5GGBridgeArgument kArray = {
    H5GGBridgeValueArray, false, false, false, 0, 0, nullptr, 0,
};

constexpr H5GGBridgeArgument kNonnegativeNumber = {
    H5GGBridgeValueNumber, false, true, false, 0, 0, nullptr, 0,
};

constexpr H5GGBridgeArgument kPositiveInteger = {
    H5GGBridgeValueNumber, true, true, true, 1,
    std::numeric_limits<int>::max(), nullptr, 0,
};

constexpr H5GGBridgeArgument kNonnegativeInteger = {
    H5GGBridgeValueNumber, true, true, true, 0,
    std::numeric_limits<int>::max(), nullptr, 0,
};

constexpr H5GGBridgeArgument kMemoryPageLength = {
    H5GGBridgeValueNumber, true, true, true, 1, 4096, nullptr, 0,
};

constexpr double kFilterModes[] = {0, 2, 3};
constexpr H5GGBridgeArgument kFilterMode = {
    H5GGBridgeValueNumber, true, false, false, 0, 0,
    kFilterModes, sizeof(kFilterModes) / sizeof(kFilterModes[0]),
};

#define H5GG_ARGS(...) {__VA_ARGS__}
#define H5GG_NO_ARGS {}

const H5GGBridgeMethod kBridgeMethods[] = {
    {"searchNumber", "searchNumber:param2:param3:param4:", 4, 4,
     H5GG_ARGS(kString, kString, kString, kString)},
    {"searchNearby", "searchNearby:param2:param3:", 3, 3,
     H5GG_ARGS(kString, kString, kString)},
    {"getValue", "getValue:param2:", 2, 2, H5GG_ARGS(kString, kString)},
    {"setValue", "setValue:param2:param3:", 3, 3,
     H5GG_ARGS(kString, kString, kString)},
    {"editAll", "editAll:param3:", 2, 2, H5GG_ARGS(kString, kString)},
    {"getResults", "getResults:param1:", 1, 2,
     H5GG_ARGS(kPositiveInteger, kNonnegativeInteger)},
    {"getResultsCount", "getResultsCount", 0, 0, H5GG_NO_ARGS},
    {"clearResults", "clearResults", 0, 0, H5GG_NO_ARGS},
    {"getLocalScripts", "getLocalScripts", 0, 0, H5GG_NO_ARGS},
    {"pickScriptFile", "pickScriptFileWithTypes:", 0, 1,
     H5GG_ARGS(kOptionalArray)},
    {"getRangesList", "getRangesList:", 0, 1,
     H5GG_ARGS(kOptionalString)},
    {"getProcList", "getProcList:", 0, 1, H5GG_ARGS(kOptionalString)},
    {"setTargetProc", "setTargetProc:", 1, 1, H5GG_ARGS(kPositiveInteger)},
    {"getTargetStatus", "getTargetStatus", 0, 0, H5GG_NO_ARGS},
    {"loadPlugin", "loadPlugin:path:", 2, 2, H5GG_ARGS(kString, kString)},
    {"callPlugin", "callPlugin:method:arguments:", 3, 3,
     H5GG_ARGS(kString, kString, kArray)},
    {"getPluginCapabilities", "getPluginCapabilities", 0, 0, H5GG_NO_ARGS},
    {"makeTweak", "makeTweak:with:", 2, 2, H5GG_ARGS(kString, kString)},
    {"require", "require:", 1, 1, H5GG_ARGS(kNonnegativeNumber)},
    {"setFloatTolerance", "setFloatTolerance:", 1, 1, H5GG_ARGS(kString)},
    {"searchChange", "searchChange:", 1, 1, H5GG_ARGS(kString)},
    {"searchFilter", "searchFilter:type:mode:", 3, 3,
     H5GG_ARGS(kString, kString, kFilterMode)},
    {"getInputHistory", "getInputHistory", 0, 0, H5GG_NO_ARGS},
    {"addInputHistory", "addInputHistory:", 1, 1, H5GG_ARGS(kString)},
    {"clearInputHistory", "clearInputHistory", 0, 0, H5GG_NO_ARGS},
    {"addBookmark", "addBookmark:name:type:", 3, 3,
     H5GG_ARGS(kString, kString, kString)},
    {"removeBookmark", "removeBookmark:", 1, 1, H5GG_ARGS(kString)},
    {"getBookmarks", "getBookmarks", 0, 0, H5GG_NO_ARGS},
    {"clearBookmarks", "clearBookmarks", 0, 0, H5GG_NO_ARGS},
    {"freezeValue", "freezeValue:value:type:", 3, 3,
     H5GG_ARGS(kString, kString, kString)},
    {"unfreezeValue", "unfreezeValue:", 1, 1, H5GG_ARGS(kString)},
    {"getFrozenValues", "getFrozenValues", 0, 0, H5GG_NO_ARGS},
    {"clearFrozenValues", "clearFrozenValues", 0, 0, H5GG_NO_ARGS},
    {"searchHex", "searchHex:memoryFrom:memoryTo:", 3, 3,
     H5GG_ARGS(kString, kString, kString)},
    {"getSearchHistory", "getSearchHistory", 0, 0, H5GG_NO_ARGS},
    {"addSearchHistory", "addSearchHistory:type:count:", 3, 3,
     H5GG_ARGS(kString, kString, kNonnegativeInteger)},
    {"clearSearchHistory", "clearSearchHistory", 0, 0, H5GG_NO_ARGS},
    {"dumpMemory", "dumpMemory:end:filename:", 3, 3,
     H5GG_ARGS(kString, kString, kString)},
    {"getDumpStatus", "getDumpStatus", 0, 0, H5GG_NO_ARGS},
    {"cancelDump", "cancelDump", 0, 0, H5GG_NO_ARGS},
    {"readPointer", "readPointer:", 1, 1, H5GG_ARGS(kString)},
    {"findPointers", "findPointers:rangeStart:rangeEnd:", 3, 3,
     H5GG_ARGS(kString, kString, kString)},
    {"getPointerCapabilities", "getPointerCapabilities", 0, 0, H5GG_NO_ARGS},
    {"appendLog", "appendLog:", 1, 1, H5GG_ARGS(kString)},
    {"readBytes", "readBytes:length:", 2, 2,
     H5GG_ARGS(kString, kMemoryPageLength)},
    {"readMemoryPage", "readMemoryPage:length:", 1, 2,
     H5GG_ARGS(kString, kMemoryPageLength)},
    {"saveScript", "saveScript:content:", 2, 2, H5GG_ARGS(kString, kString)},
    {"loadScript", "loadScript:", 1, 1, H5GG_ARGS(kString)},
    {"deleteScript", "deleteScript:", 1, 1, H5GG_ARGS(kString)},
    {"listScripts", "listScripts", 0, 0, H5GG_NO_ARGS},
    {"getLastFileError", "getLastFileError", 0, 0, H5GG_NO_ARGS},
    {"copyText", "copyText:", 1, 1, H5GG_ARGS(kString)},
};

#undef H5GG_NO_ARGS
#undef H5GG_ARGS

} // namespace

bool H5GGBridgeArgument::accepts(H5GGBridgeValueKind kind,
                                 double numberValue) const {
    if((allowedKinds & static_cast<uint8_t>(kind)) == 0) return false;
    if(kind != H5GGBridgeValueNumber) return true;
    if(!std::isfinite(numberValue)) return false;
    if(integerOnly && std::trunc(numberValue) != numberValue) return false;
    if(hasMinimum && numberValue < minimum) return false;
    if(hasMaximum && numberValue > maximum) return false;
    if(allowedNumberCount > 0) {
        for(size_t index = 0; index < allowedNumberCount; index++) {
            if(numberValue == allowedNumbers[index]) return true;
        }
        return false;
    }
    return true;
}

bool H5GGBridgeMethod::acceptsArgument(size_t index,
                                       H5GGBridgeValueKind kind,
                                       double numberValue) const {
    return index < maximumArguments && arguments[index].accepts(kind, numberValue);
}

const H5GGBridgeMethod* H5GGBridgeMethods(size_t& count) {
    count = sizeof(kBridgeMethods) / sizeof(kBridgeMethods[0]);
    return kBridgeMethods;
}

const H5GGBridgeMethod* H5GGBridgeMethodNamed(const char* name) {
    if(!name) return nullptr;

    size_t count = 0;
    const H5GGBridgeMethod* methods = H5GGBridgeMethods(count);
    for(size_t index = 0; index < count; index++) {
        if(std::strcmp(methods[index].name, name) == 0) return &methods[index];
    }
    return nullptr;
}
