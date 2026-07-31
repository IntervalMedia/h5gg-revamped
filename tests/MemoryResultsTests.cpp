#include "../MemoryResults.h"
#include "../MemoryValue.h"
#include "../BridgeMethods.h"
#include "../FileNames.h"
#include "../MemoryFilter.h"
#include "../MemoryPage.h"
#include "../MemoryDump.h"
#include "../DylibTemplate.h"

#include <cassert>
#include <cstring>
#include <cstdint>
#include <memory>
#include <set>
#include <string>
#include <unordered_map>

static void recountsAddressesAcrossRegions() {
    Result results;

    auto first = std::make_unique<result_region>(0x1000, 0x100);
    first->append(0x10);
    first->append(0x20);
    results.add(std::move(first));

    auto second = std::make_unique<result_region>(0x2000, 0x100);
    second->append(0x08);
    results.add(std::move(second));

    assert(results.count() == 3);
    assert(results.invariantHolds());
}

static void typedRegionsRequireOneTypePerAddress() {
    result_region region(0x1000, 0x100);
    region.append(0x10, 4);
    region.append(0x20, 6);

    assert(region.hasTypes());
    assert(region.typeAt(0, 1) == 4);
    assert(region.typeAt(1, 1) == 6);
    assert(region.invariantHolds());
}

static void untypedRegionsUseTheFallbackType() {
    result_region region(0x1000, 0x100);
    region.append(0x10);

    assert(!region.hasTypes());
    assert(region.typeAt(0, 7) == 7);
    assert(region.invariantHolds());
}

static void replacingRegionsUpdatesTheCount() {
    Result results;

    auto original = std::make_unique<result_region>(0x1000, 0x100);
    original->append(0x10);
    original->append(0x20);
    results.add(std::move(original));

    auto replacement = std::make_unique<result_region>(0x1000, 0x100);
    replacement->append(0x20);
    results.replace(0, std::move(replacement));

    assert(results.count() == 1);
    assert(results.invariantHolds());

    results.replace(0, nullptr);
    results.removeEmptyRegions();
    assert(results.count() == 0);
    assert(results.regionCount() == 0);
}

static void filtersAllSupportedValueKinds() {
    uint8_t current[8] = {};
    uint8_t target[8] = {};

    int32_t currentSigned = -2;
    int32_t targetSigned = -3;
    std::memcpy(current, &currentSigned, sizeof(currentSigned));
    std::memcpy(target, &targetSigned, sizeof(targetSigned));
    assert(JJValueMatchesFilter(current, target, JJ_Search_Type_SInt, JJ_Filter_Greater));

    uint32_t currentUnsigned = 2;
    uint32_t targetUnsigned = 3;
    std::memcpy(current, &currentUnsigned, sizeof(currentUnsigned));
    std::memcpy(target, &targetUnsigned, sizeof(targetUnsigned));
    assert(JJValueMatchesFilter(current, target, JJ_Search_Type_UInt, JJ_Filter_Less));

    float currentFloat = 1.5f;
    float targetFloat = 1.5f;
    std::memcpy(current, &currentFloat, sizeof(currentFloat));
    std::memcpy(target, &targetFloat, sizeof(targetFloat));
    assert(JJValueMatchesFilter(current, target, JJ_Search_Type_Float, JJ_Filter_Equal));
}

static void filtersEveryNumericTypeInEveryDocumentedMode() {
    const int types[] = {
        JJ_Search_Type_Double,
        JJ_Search_Type_ULong,
        JJ_Search_Type_SLong,
        JJ_Search_Type_Float,
        JJ_Search_Type_UInt,
        JJ_Search_Type_SInt,
        JJ_Search_Type_UShort,
        JJ_Search_Type_SShort,
        JJ_Search_Type_UByte,
        JJ_Search_Type_SByte,
    };

    for(int type : types) {
        uint8_t target[8] = {};
        uint8_t equal[8] = {};
        uint8_t greater[8] = {};
        uint8_t less[8] = {};
        assert(JJParseValue("2", type, target));
        assert(JJParseValue("2", type, equal));
        assert(JJParseValue("3", type, greater));
        assert(JJParseValue("1", type, less));
        assert(JJValueMatchesFilter(equal, target, type, JJ_Filter_Equal));
        assert(JJValueMatchesFilter(greater, target, type, JJ_Filter_Greater));
        assert(JJValueMatchesFilter(less, target, type, JJ_Filter_Less));
        assert(!JJValueMatchesFilter(less, target, type, 99));
    }
}

static void parsesValuesAccordingToTheirDeclaredType() {
    uint8_t value[8] = {};
    assert(JJParseValue("4294967295", JJ_Search_Type_UInt, value));
    assert(*reinterpret_cast<uint32_t*>(value) == UINT32_MAX);

    assert(JJParseValue("-42", JJ_Search_Type_SLong, value));
    assert(*reinterpret_cast<int64_t*>(value) == -42);

    assert(!JJParseValue("12garbage", JJ_Search_Type_SInt, value));
    assert(!JJParseValue("999", JJ_Search_Type_UByte, value));
}

static void parsesStrictHexPatterns() {
    std::vector<uint8_t> bytes;
    assert(JJParseHexPattern("DE AD be ef", bytes));
    assert((bytes == std::vector<uint8_t>{0xDE, 0xAD, 0xBE, 0xEF}));

    assert(!JJParseHexPattern("ABC", bytes));
    assert(!JJParseHexPattern("GG", bytes));
    assert(!JJParseHexPattern("", bytes));
}

static void parsesAndMatchesHexWildcards() {
    JJHexPattern pattern;
    assert(JJParseMaskedHexPattern("DE AD ?? ?F", pattern));
    assert(pattern.size() == 4);

    const uint8_t matching[] = {0xDE, 0xAD, 0x42, 0xAF};
    const uint8_t wrongNibble[] = {0xDE, 0xAD, 0x42, 0xA0};
    assert(JJHexPatternMatches(matching, sizeof(matching), pattern));
    assert(!JJHexPatternMatches(wrongNibble, sizeof(wrongNibble), pattern));
    assert(!JJParseMaskedHexPattern("DE A", pattern));
    assert(!JJParseMaskedHexPattern("DE X?", pattern));
}

static void parsesAddressesWithFullConsumptionAndRangeChecks() {
    uint64_t address = 0;
    assert(JJParseAddress("0x1234ABCD", 16, address));
    assert(address == 0x1234ABCD);
    assert(JJParseAddress("18446744073709551615", 10, address));
    assert(address == UINT64_MAX);

    assert(!JJParseAddress("", 16, address));
    assert(!JJParseAddress("-1", 16, address));
    assert(!JJParseAddress("+1", 16, address));
    assert(!JJParseAddress(" 1", 16, address));
    assert(!JJParseAddress("1234junk", 16, address));
    assert(!JJParseAddress("18446744073709551616", 10, address));
    assert(!JJParseAddress("1234", 8, address));
}

static void bridgeSchemaRejectsUnknownOrMalformedCalls() {
    const H5GGBridgeMethod* search = H5GGBridgeMethodNamed("searchNumber");
    assert(search);
    assert(search->acceptsArgumentCount(4));
    assert(!search->acceptsArgumentCount(3));
    assert(std::strcmp(search->selector, "searchNumber:param2:param3:param4:") == 0);

    const H5GGBridgeMethod* results = H5GGBridgeMethodNamed("getResults");
    assert(results);
    assert(results->acceptsArgumentCount(1));
    assert(results->acceptsArgumentCount(2));
    assert(!results->acceptsArgumentCount(0));

    assert(H5GGBridgeMethodNamed("dealloc") == nullptr);
    assert(H5GGBridgeMethodNamed("_freezerTick") == nullptr);
}

static void bridgeSchemaCoversEveryAdvertisedMethod() {
    size_t count = 0;
    const H5GGBridgeMethod* methods = H5GGBridgeMethods(count);
    assert(methods);
    assert(count > 0);

    std::set<std::string> names;
    std::set<std::string> selectors;
    for(size_t index = 0; index < count; index++) {
        const H5GGBridgeMethod& method = methods[index];
        assert(method.name);
        assert(method.selector);
        assert(method.minimumArguments <= method.maximumArguments);
        assert(names.insert(method.name).second);
        assert(selectors.insert(method.selector).second);
        assert(H5GGBridgeMethodNamed(method.name) == &method);
        assert(method.acceptsArgumentCount(method.minimumArguments));
        assert(method.acceptsArgumentCount(method.maximumArguments));
        if(method.minimumArguments > 0) {
            assert(!method.acceptsArgumentCount(method.minimumArguments - 1));
        }
        assert(!method.acceptsArgumentCount(method.maximumArguments + 1));
    }
}

static void confinesUserFilesToOneDirectoryEntry() {
    assert(H5GGIsSafeFileName("menu.js"));
    assert(H5GGIsSafeFileName("memory dump.bin"));
    assert(!H5GGIsSafeFileName("../outside.js"));
    assert(!H5GGIsSafeFileName("folder/menu.js"));
    assert(!H5GGIsSafeFileName("/tmp/menu.js"));
    assert(!H5GGIsSafeFileName(""));

    std::string normalized;
    assert(H5GGNormalizeScriptFileName("menu", normalized));
    assert(normalized == "menu.js");
    assert(H5GGNormalizeScriptFileName("menu.JS", normalized));
    assert(normalized == "menu.JS");
    assert(H5GGNormalizeScriptFileName("menu.html", normalized));
    assert(!H5GGNormalizeScriptFileName("menu.txt", normalized));
    assert(!H5GGNormalizeScriptFileName("../menu.js", normalized));
}

static void filtersAResultSetThroughTheMemoryInterface() {
    Result results;
    auto region = std::make_unique<result_region>(0x1000, 0x100);
    region->append(0x10);
    region->append(0x20);
    region->append(0x30);
    results.add(std::move(region));

    std::unordered_map<uint64_t, int32_t> memory = {
        {0x1010, 4},
        {0x1020, 8},
        {0x1030, 12},
    };
    auto reader = [&memory](void* output, uint64_t address, size_t length) {
        auto found = memory.find(address);
        if(found == memory.end() || length != sizeof(int32_t)) return false;
        std::memcpy(output, &found->second, length);
        return true;
    };

    size_t kept = JJFilterResultSet(results, "7", JJ_Search_Type_SInt,
                                    JJ_Filter_Greater, reader);
    assert(kept == 2);
    assert(results.count() == 2);
    assert(results.invariantHolds());
    assert(results.regionAt(0)->slides[0] == 0x20);
    assert(results.regionAt(0)->slides[1] == 0x30);
    assert(results.regionAt(0)->typeAt(0, 0) == JJ_Search_Type_SInt);
}

static void refinesHexResultsThroughTheMemoryInterface() {
    Result results;
    auto region = std::make_unique<result_region>(0x2000, 0x100);
    region->append(0x10, JJ_Search_Type_UByte);
    region->append(0x20, JJ_Search_Type_UByte);
    region->append(0x30, JJ_Search_Type_UByte);
    results.add(std::move(region));

    std::unordered_map<uint64_t, std::vector<uint8_t>> memory = {
        {0x2010, {0xDE, 0xAD, 0x01, 0xEF}},
        {0x2020, {0xDE, 0xAD, 0x02, 0xE0}},
        {0x2030, {0xDE, 0xAD, 0x03, 0xEF}},
    };
    auto reader = [&memory](void* output, uint64_t address, size_t length) {
        auto found = memory.find(address);
        if(found == memory.end() || found->second.size() < length) return false;
        std::memcpy(output, found->second.data(), length);
        return true;
    };

    JJHexPattern pattern;
    assert(JJParseMaskedHexPattern("DE AD ?? EF", pattern));
    assert(JJFilterHexResultSet(results, pattern, reader, 0x2000, 0x2040) == 2);
    assert(results.invariantHolds());
    assert(results.regionAt(0)->slides[0] == 0x10);
    assert(results.regionAt(0)->slides[1] == 0x30);
}

static void readsPartialPagesAndMarksUnreadableBytes() {
    const std::vector<uint8_t> memory = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15};
    auto reader = [&memory](void* output, uint64_t address, size_t length) -> size_t {
        if(address < 0x1000 || address >= 0x1000 + memory.size()) return 0;
        size_t offset = (size_t)(address - 0x1000);
        if(offset == 3) return 0;
        size_t readable = std::min(length, memory.size() - offset);
        if(offset < 3) readable = std::min(readable, (size_t)(3 - offset));
        std::memcpy(output, memory.data() + offset, readable);
        return readable;
    };

    JJMemoryPage page = JJReadMemoryPage(0x1000, 8, reader, 4);
    assert(page.bytes.size() == 8);
    assert(page.bytes[0] == 0x10);
    assert(page.bytes[2] == 0x12);
    assert(page.bytes[3] == -1);
    assert(page.bytes[4] == 0x14);
    assert(page.bytes[5] == 0x15);
    assert(page.bytes[6] == -1);
    assert(page.readableCount() == 5);
    assert(!page.complete());
}

static void replacesEveryDylibTemplateWithoutChangingBinarySize() {
    const std::vector<uint8_t> placeholder = {1, 2, 3, 4};
    const std::vector<uint8_t> payload = {9, 8};
    std::vector<uint8_t> binary = {0, 1, 2, 3, 4, 5, 1, 2, 3, 4, 6};
    size_t originalSize = binary.size();
    assert(H5GGReplaceAllTemplates(binary, placeholder, payload) == 2);
    assert(binary.size() == originalSize);
    assert((binary == std::vector<uint8_t>{0, 9, 8, 0, 0, 5, 9, 8, 0, 0, 6}));
    assert(H5GGReplaceAllTemplates(binary, placeholder, payload) == 0);
    assert(H5GGReplaceAllTemplates(binary, placeholder, placeholder) == 0);
}

static void streamsMemoryDumpsWithProgressFailureAndCancellation() {
    std::vector<uint8_t> source(20);
    for(size_t index = 0; index < source.size(); index++) {
        source[index] = static_cast<uint8_t>(index);
    }
    auto reader = [&source](void* output, uint64_t address, size_t length) -> size_t {
        if(address < 0x3000 || address >= 0x3000 + source.size()) return 0;
        size_t offset = static_cast<size_t>(address - 0x3000);
        size_t available = std::min(length, source.size() - offset);
        size_t partial = std::min(available, (size_t)3);
        std::memcpy(output, source.data() + offset, partial);
        return partial;
    };

    std::vector<uint8_t> output;
    size_t lastProgress = 0;
    JJMemoryDumpResult complete = JJStreamMemoryDump(
        0x3000, source.size(), reader,
        [&output](const void* bytes, size_t length) {
            const uint8_t* begin = static_cast<const uint8_t*>(bytes);
            output.insert(output.end(), begin, begin + length);
            return true;
        },
        {},
        [&lastProgress](size_t written, size_t) { lastProgress = written; },
        8);
    assert(complete.status == JJMemoryDumpStatus::Completed);
    assert(complete.bytesWritten == source.size());
    assert(lastProgress == source.size());
    assert(output == source);

    bool shouldCancel = false;
    JJMemoryDumpResult cancelled = JJStreamMemoryDump(
        0x3000, source.size(), reader,
        [&shouldCancel](const void*, size_t) {
            shouldCancel = true;
            return true;
        },
        [&shouldCancel]() { return shouldCancel; },
        {},
        8);
    assert(cancelled.status == JJMemoryDumpStatus::Cancelled);
    assert(cancelled.bytesWritten == 3);

    JJMemoryDumpResult failed = JJStreamMemoryDump(
        0x3000, source.size() + 1, reader,
        [](const void*, size_t) { return true; },
        {}, {}, 8);
    assert(failed.status == JJMemoryDumpStatus::ReadFailed);
    assert(failed.failureAddress == 0x3000 + source.size());
}

int main() {
    recountsAddressesAcrossRegions();
    typedRegionsRequireOneTypePerAddress();
    untypedRegionsUseTheFallbackType();
    replacingRegionsUpdatesTheCount();
    filtersAllSupportedValueKinds();
    filtersEveryNumericTypeInEveryDocumentedMode();
    parsesValuesAccordingToTheirDeclaredType();
    parsesStrictHexPatterns();
    parsesAndMatchesHexWildcards();
    parsesAddressesWithFullConsumptionAndRangeChecks();
    bridgeSchemaRejectsUnknownOrMalformedCalls();
    bridgeSchemaCoversEveryAdvertisedMethod();
    confinesUserFilesToOneDirectoryEntry();
    filtersAResultSetThroughTheMemoryInterface();
    refinesHexResultsThroughTheMemoryInterface();
    readsPartialPagesAndMarksUnreadableBytes();
    replacesEveryDylibTemplateWithoutChangingBinarySize();
    streamsMemoryDumpsWithProgressFailureAndCancellation();
    return 0;
}
