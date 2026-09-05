#include "../MemoryResults.h"
#include "../MemoryValue.h"
#include "../BridgeMethods.h"
#include "../FileNames.h"
#include "../MemoryFilter.h"
#include "../MemoryPage.h"
#include "../MemoryDump.h"
#include "../MemoryReader.h"
#include "../PointerSearch.h"
#include "../DylibTemplate.h"
#include "../DylibBuilder.h"
#include "../TargetSession.h"
#include "../ModalRequestQueue.h"
#include "../ScriptStore.h"
#include "device/Phase2DeviceFixture.h"

#include <cassert>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <future>
#include <fcntl.h>
#include <memory>
#include <limits>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>
#include <unistd.h>

static int releasedTargetPorts = 0;
static int deletedMemoryEngines = 0;

static void releaseFakeTargetPort(mach_port_t) {
    releasedTargetPorts++;
}

static void deleteFakeMemoryEngine(JJMemoryEngine*) {
    deletedMemoryEngines++;
}

static void targetSessionsOwnExactlyOneTargetAndEngine() {
    releasedTargetPorts = 0;
    deletedMemoryEngines = 0;

    {
        TargetProcess borrowed(7, static_cast<mach_port_t>(70));
        assert(borrowed.valid());
        assert(!borrowed.ownsPort());
    }
    assert(releasedTargetPorts == 0);

    {
        TargetProcess owned(42, static_cast<mach_port_t>(420), releaseFakeTargetPort);
        assert(owned.valid());
        assert(owned.ownsPort());

        TargetProcess moved(std::move(owned));
        assert(!owned.valid());
        assert(moved.pid() == 42);
        assert(moved.port() == static_cast<mach_port_t>(420));

        auto* firstEngine = reinterpret_cast<JJMemoryEngine*>(0x1000);
        auto* secondEngine = reinterpret_cast<JJMemoryEngine*>(0x2000);
        MemorySession session(std::move(moved), firstEngine, deleteFakeMemoryEngine);
        assert(session.target().pid() == 42);
        assert(session.engine() == firstEngine);
        assert(!session.firstSearchDone());
        assert(session.lastSearchType() == JJ_Search_Type_Error);

        session.markSearchDone(JJ_Search_Type_SInt);
        assert(session.firstSearchDone());
        assert(session.lastSearchType() == JJ_Search_Type_SInt);

        session.replaceEngine(secondEngine, deleteFakeMemoryEngine);
        assert(deletedMemoryEngines == 1);
        assert(session.engine() == secondEngine);
        assert(!session.firstSearchDone());
        assert(session.lastSearchType() == JJ_Search_Type_Error);
    }

    assert(deletedMemoryEngines == 2);
    assert(releasedTargetPorts == 1);
}

static void modalRequestsAreRequestScopedAndSerial() {
    ModalRequestQueue queue;
    auto first = queue.enqueue();
    auto second = queue.enqueue();
    auto third = queue.enqueue();

    assert(first.active());
    assert(!second.active());
    assert(!third.active());
    assert(!second.complete());
    assert(!first.completed());
    assert(!second.completed());

    assert(first.complete());
    assert(first.completed());
    assert(second.active());
    assert(!first.complete());

    auto movedSecond = std::move(second);
    assert(movedSecond.active());
    assert(movedSecond.complete());
    assert(third.active());

    assert(third.complete());
    assert(third.completed());

    auto active = queue.enqueue();
    {
        auto abandoned = queue.enqueue();
        assert(!abandoned.active());
    }
    auto next = queue.enqueue();
    assert(active.complete());
    assert(next.active());
    assert(next.complete());

    auto blockingFirst = queue.enqueue();
    auto blockingSecond = queue.enqueue();
    auto activation = std::async(std::launch::async, [&blockingSecond] {
        blockingSecond.waitUntilActive();
        return blockingSecond.active();
    });
    assert(activation.wait_for(std::chrono::milliseconds(20)) ==
           std::future_status::timeout);
    assert(blockingFirst.complete());
    assert(activation.wait_for(std::chrono::seconds(1)) ==
           std::future_status::ready);
    assert(activation.get());

    auto completion = std::async(std::launch::async, [&blockingSecond] {
        blockingSecond.waitUntilCompleted();
        return blockingSecond.completed();
    });
    assert(completion.wait_for(std::chrono::milliseconds(20)) ==
           std::future_status::timeout);
    assert(blockingSecond.complete());
    assert(completion.wait_for(std::chrono::seconds(1)) ==
           std::future_status::ready);
    assert(completion.get());
}

static void scriptStoreOwnsConfinementAndAtomicIO() {
    char rootTemplate[] = "/tmp/h5gg-script-store.XXXXXX";
    char* root = mkdtemp(rootTemplate);
    assert(root);

    ScriptStore store(root);
    std::string content;
    assert(store.save("alpha", "first"));
    assert(store.lastError().empty());
    assert(store.load("alpha", content));
    assert(content == "first");

    assert(store.save("alpha.js", "replacement"));
    assert(store.load("alpha.js", content));
    assert(content == "replacement");
    assert(store.save("Page.HTML", "<p>ok</p>"));

    std::vector<std::string> scripts = store.list();
    assert((scripts == std::vector<std::string>{"alpha.js", "Page.HTML"}));

    assert(!store.save("../escape.js", "bad"));
    assert(!store.lastError().empty());
    assert(!store.save(nullptr, std::nullopt));
    assert(store.lastError() == "A file name and content are required");
    assert(!store.save("bad.txt", "bad"));
    assert(!store.save("invalid.js", std::string("\xFF", 1)));
    assert(!store.save("overlong.js", std::string("\xC0\xAF", 2)));
    assert(!store.save("surrogate.js", std::string("\xED\xA0\x80", 3)));
    assert(!store.save("out-of-range.js", std::string("\xF4\x90\x80\x80", 4)));
    assert(store.save("unicode.js", std::string("H5GG \xF0\x9F\x94\x8D", 9)));
    assert(!store.save("large.js",
                       std::string(ScriptStore::MaximumScriptBytes + 1, 'x')));

    assert(store.remove("alpha"));
    assert(!store.load("alpha", content));
    assert(store.remove("Page.HTML"));
    assert(store.remove("unicode.js"));
    assert(!store.remove("Page.HTML"));
    assert(rmdir(root) == 0);
}

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

static void formatsValuesAccordingToTheirDeclaredType() {
    uint8_t value[8] = {};
    std::string formatted;

    assert(JJParseValue("-42", JJ_Search_Type_SLong, value));
    assert(JJFormatValue(value, JJ_Search_Type_SLong, formatted));
    assert(formatted == "-42");

    assert(JJParseValue("4294967295", JJ_Search_Type_UInt, value));
    assert(JJFormatValue(value, JJ_Search_Type_UInt, formatted));
    assert(formatted == "4294967295");

    assert(JJParseValue("0.5", JJ_Search_Type_Float, value));
    assert(JJFormatValue(value, JJ_Search_Type_Float, formatted));
    assert(formatted == "0.5");

    assert(JJParseValue("1.5", JJ_Search_Type_Double, value));
    assert(JJFormatValue(value, JJ_Search_Type_Double, formatted));
    assert(formatted == "1.500000");

    assert(!JJFormatValue(value, JJ_Search_Type_Error, formatted));
    assert(formatted.empty());
}

static void centralizesTypeNamesAndToleranceParsing() {
    const char* names[] = {
        "F64", "U64", "I64", "F32", "U32",
        "I32", "U16", "I16", "U8", "I8",
    };
    for(int type = JJ_Search_Type_Double; type < JJ_Search_Type_Max; type++) {
        assert(JJTypeFromName(names[type - 1]) == type);
        assert(std::strcmp(JJTypeName(type), names[type - 1]) == 0);
    }
    assert(JJTypeFromName(nullptr) == JJ_Search_Type_Error);
    assert(JJTypeFromName("i32") == JJ_Search_Type_Error);
    assert(std::strcmp(JJTypeName(JJ_Search_Type_Error), "") == 0);
    assert(std::strcmp(JJTypeName(JJ_Search_Type_Max), "") == 0);

    float tolerance = -1;
    assert(JJParseNonnegativeFloat("0", tolerance) && tolerance == 0);
    assert(JJParseNonnegativeFloat("0.125", tolerance) && tolerance == 0.125f);
    assert(!JJParseNonnegativeFloat("-0.1", tolerance));
    assert(!JJParseNonnegativeFloat("1garbage", tolerance));
    assert(!JJParseNonnegativeFloat("nan", tolerance));
    assert(!JJParseNonnegativeFloat("", tolerance));
}

static void parsesGroupedSearchExpressionsAtomically() {
    std::vector<JJSearchValue> values;
    assert(JJParseSearchExpression("1, 2, 3~4", JJ_Search_Type_SInt, values));
    assert(values.size() == 3);

    uint8_t current[8] = {};
    assert(JJParseValue("2", JJ_Search_Type_SInt, current));
    assert(JJSearchValueMatchesAny(current, values, JJ_Search_Type_SInt, 0));
    assert(JJParseValue("4", JJ_Search_Type_SInt, current));
    assert(JJSearchValueMatchesAny(current, values, JJ_Search_Type_SInt, 0));
    assert(JJParseValue("5", JJ_Search_Type_SInt, current));
    assert(!JJSearchValueMatchesAny(current, values, JJ_Search_Type_SInt, 0));

    assert(JJParseSearchExpression("1.0～2.0, 4.0", JJ_Search_Type_Float, values));
    assert(JJParseValue("2.05", JJ_Search_Type_Float, current));
    assert(!JJSearchValueMatchesAny(current, values, JJ_Search_Type_Float, 0));
    assert(JJSearchValueMatchesAny(current, values, JJ_Search_Type_Float, 0.1f));

    assert(!JJParseSearchExpression("1,,2", JJ_Search_Type_SInt, values));
    assert(values.empty());
    assert(!JJParseSearchExpression("1~", JJ_Search_Type_SInt, values));
    assert(values.empty());
    assert(!JJParseSearchExpression("4~3", JJ_Search_Type_SInt, values));
    assert(values.empty());
    assert(!JJParseSearchExpression("1,garbage", JJ_Search_Type_SInt, values));
    assert(values.empty());
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
    for(size_t index = 0; index < 4; index++) {
        assert(search->acceptsArgument(index, H5GGBridgeValueString));
        assert(!search->acceptsArgument(index, H5GGBridgeValueNull));
        assert(!search->acceptsArgument(index, H5GGBridgeValueBoolean));
        assert(!search->acceptsArgument(index, H5GGBridgeValueNumber, 1));
        assert(!search->acceptsArgument(index, H5GGBridgeValueArray));
        assert(!search->acceptsArgument(index, H5GGBridgeValueObject));
    }
    assert(std::strcmp(search->selector, "searchNumber:param2:param3:param4:") == 0);

    const H5GGBridgeMethod* results = H5GGBridgeMethodNamed("getResults");
    assert(results);
    assert(results->acceptsArgumentCount(1));
    assert(results->acceptsArgumentCount(2));
    assert(!results->acceptsArgumentCount(0));
    assert(results->acceptsArgument(0, H5GGBridgeValueNumber, 1));
    assert(results->acceptsArgument(1, H5GGBridgeValueNumber, 0));
    assert(!results->acceptsArgument(0, H5GGBridgeValueNumber, 0));
    assert(!results->acceptsArgument(0, H5GGBridgeValueNumber, 1.5));
    assert(!results->acceptsArgument(1, H5GGBridgeValueNumber, -1));
    assert(!results->acceptsArgument(0, H5GGBridgeValueBoolean));
    assert(!results->acceptsArgument(0, H5GGBridgeValueString));

    const H5GGBridgeMethod* filter = H5GGBridgeMethodNamed("searchFilter");
    assert(filter);
    assert(filter->acceptsArgument(2, H5GGBridgeValueNumber, 0));
    assert(filter->acceptsArgument(2, H5GGBridgeValueNumber, 2));
    assert(filter->acceptsArgument(2, H5GGBridgeValueNumber, 3));
    assert(!filter->acceptsArgument(2, H5GGBridgeValueNumber, 1));
    assert(!filter->acceptsArgument(2, H5GGBridgeValueNumber, 2.5));

    const H5GGBridgeMethod* picker = H5GGBridgeMethodNamed("pickScriptFile");
    assert(picker);
    assert(picker->acceptsArgument(0, H5GGBridgeValueArray));
    assert(picker->acceptsArgument(0, H5GGBridgeValueNull));
    assert(!picker->acceptsArgument(0, H5GGBridgeValueString));

    const H5GGBridgeMethod* plugin = H5GGBridgeMethodNamed("callPlugin");
    assert(plugin);
    assert(plugin->acceptsArgument(0, H5GGBridgeValueString));
    assert(plugin->acceptsArgument(1, H5GGBridgeValueString));
    assert(plugin->acceptsArgument(2, H5GGBridgeValueArray));
    assert(!plugin->acceptsArgument(2, H5GGBridgeValueObject));

    const H5GGBridgeMethod* target = H5GGBridgeMethodNamed("setTargetProc");
    assert(target);
    assert(target->acceptsArgument(0, H5GGBridgeValueNumber, 1));
    assert(!target->acceptsArgument(0, H5GGBridgeValueNumber, 0));
    assert(!target->acceptsArgument(0, H5GGBridgeValueNumber, 1.5));

    const H5GGBridgeMethod* readBytes = H5GGBridgeMethodNamed("readBytes");
    assert(readBytes);
    assert(readBytes->acceptsArgument(1, H5GGBridgeValueNumber, 1));
    assert(readBytes->acceptsArgument(1, H5GGBridgeValueNumber, 4096));
    assert(!readBytes->acceptsArgument(1, H5GGBridgeValueNumber, 0));
    assert(!readBytes->acceptsArgument(1, H5GGBridgeValueNumber, 4097));
    assert(!readBytes->acceptsArgument(1, H5GGBridgeValueNumber, 1.5));

    const H5GGBridgeMethod* require = H5GGBridgeMethodNamed("require");
    assert(require);
    assert(require->acceptsArgument(0, H5GGBridgeValueNumber, 0));
    assert(!require->acceptsArgument(0, H5GGBridgeValueNumber, -1));
    assert(!require->acceptsArgument(
        0, H5GGBridgeValueNumber, std::numeric_limits<double>::infinity()));

    const H5GGBridgeMethod* copyText = H5GGBridgeMethodNamed("copyText");
    assert(copyText);
    assert(copyText->acceptsArgumentCount(1));
    assert(!copyText->acceptsArgumentCount(0));
    assert(!copyText->acceptsArgumentCount(2));
    assert(std::strcmp(copyText->selector, "copyText:") == 0);

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
        for(size_t argument = 0; argument < method.maximumArguments; argument++) {
            assert(method.arguments[argument].allowedKinds != 0);
        }
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

    std::vector<uint8_t> memory(0x34);
    int32_t values[] = {4, 8, 12};
    std::memcpy(memory.data() + 0x10, &values[0], sizeof(values[0]));
    std::memcpy(memory.data() + 0x20, &values[1], sizeof(values[1]));
    std::memcpy(memory.data() + 0x30, &values[2], sizeof(values[2]));
    JJBufferMemoryReader reader(0x1000, std::move(memory));

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

    std::vector<uint8_t> memory(0x34);
    const uint8_t first[] = {0xDE, 0xAD, 0x01, 0xEF};
    const uint8_t second[] = {0xDE, 0xAD, 0x02, 0xE0};
    const uint8_t third[] = {0xDE, 0xAD, 0x03, 0xEF};
    std::memcpy(memory.data() + 0x10, first, sizeof(first));
    std::memcpy(memory.data() + 0x20, second, sizeof(second));
    std::memcpy(memory.data() + 0x30, third, sizeof(third));
    JJBufferMemoryReader reader(0x2000, std::move(memory));

    JJHexPattern pattern;
    assert(JJParseMaskedHexPattern("DE AD ?? EF", pattern));
    assert(JJFilterHexResultSet(results, pattern, reader, 0x2000, 0x2040) == 2);
    assert(results.invariantHolds());
    assert(results.regionAt(0)->slides[0] == 0x10);
    assert(results.regionAt(0)->slides[1] == 0x30);
}

static void readsPartialPagesAndMarksUnreadableBytes() {
    const std::vector<uint8_t> memory = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15};
    JJCallbackMemoryReader reader([&memory](void* output,
                                            uint64_t address,
                                            size_t length) -> size_t {
        if(address < 0x1000 || address >= 0x1000 + memory.size()) return 0;
        size_t offset = (size_t)(address - 0x1000);
        if(offset == 3) return 0;
        size_t readable = std::min(length, memory.size() - offset);
        if(offset < 3) readable = std::min(readable, (size_t)(3 - offset));
        std::memcpy(output, memory.data() + offset, readable);
        return readable;
    });

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

static void memoryReaderUnifiesRawExactAndTypedReads() {
    uint32_t stored = 0x78563412;
    std::vector<uint8_t> memory(sizeof(stored));
    std::memcpy(memory.data(), &stored, sizeof(stored));
    JJBufferMemoryReader reader(0x4000, memory);

    uint8_t raw[8] = {};
    assert(reader.readBytes(raw, 0x4001, sizeof(raw)) == 3);
    assert(raw[0] == memory[1]);
    assert(!reader.readExact(raw, 0x4001, sizeof(stored)));
    assert(!reader.readValue(raw, 0x4000, JJ_Search_Type_Error));

    uint32_t typed = 0;
    assert(reader.readValue(&typed, 0x4000, JJ_Search_Type_UInt));
    assert(typed == stored);

    JJCallbackMemoryReader overReporting(
        [](void* output, uint64_t, size_t length) {
            std::memset(output, 0xAB, length);
            return length + 10;
        });
    assert(overReporting.readBytes(raw, 0x5000, 2) == 2);

    JJMemoryPage overflowPage = JJReadMemoryPage(UINT64_MAX, 2, reader);
    assert(overflowPage.readableCount() == 0);
    JJMemoryDumpResult overflowDump = JJStreamMemoryDump(
        UINT64_MAX, 2, reader,
        [](const void*, size_t) { return true; });
    assert(overflowDump.status == JJMemoryDumpStatus::InvalidInput);
}

static void writeTestFile(const std::string& path,
                          const std::vector<uint8_t>& bytes) {
    int descriptor = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    assert(descriptor >= 0);
    size_t offset = 0;
    while(offset < bytes.size()) {
        ssize_t count = write(descriptor, bytes.data() + offset,
                              bytes.size() - offset);
        assert(count > 0);
        offset += static_cast<size_t>(count);
    }
    assert(close(descriptor) == 0);
}

static std::vector<uint8_t> readTestFile(const std::string& path) {
    int descriptor = open(path.c_str(), O_RDONLY);
    assert(descriptor >= 0);
    std::vector<uint8_t> bytes;
    uint8_t buffer[64];
    while(true) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        assert(count >= 0);
        if(count == 0) break;
        bytes.insert(bytes.end(), buffer, buffer + count);
    }
    assert(close(descriptor) == 0);
    return bytes;
}

static void dylibBuilderOwnsValidationOutputAndSigning() {
    char rootTemplate[] = "/tmp/h5gg-dylib-builder.XXXXXX";
    char* root = mkdtemp(rootTemplate);
    assert(root);

    std::string directory(root);
    std::string sourcePath = directory + "/source.dylib";
    std::string iconPath = directory + "/icon.png";
    std::string menuPath = directory + "/menu.html";
    std::string outputPath = directory + "/output.dylib";

    const std::vector<uint8_t> iconPlaceholder = {
        'I', 'C', 'O', 'N', '_', '_', '_', '_',
    };
    const std::vector<uint8_t> menuPlaceholder = {
        'M', 'E', 'N', 'U', '_', '_', '_', '_', '_', '_', '_', '_',
    };
    const std::vector<uint8_t> icon = {0x89, 'P', 'N', 'G'};
    const std::vector<uint8_t> menu = {'<', 'h', '5', '>'};
    std::vector<uint8_t> source = {'F', 'A', 'T'};
    source.insert(source.end(), iconPlaceholder.begin(), iconPlaceholder.end());
    source.push_back(0x7F);
    source.insert(source.end(), menuPlaceholder.begin(), menuPlaceholder.end());
    source.insert(source.end(), iconPlaceholder.begin(), iconPlaceholder.end());
    source.insert(source.end(), menuPlaceholder.begin(), menuPlaceholder.end());
    writeTestFile(sourcePath, source);
    writeTestFile(iconPath, icon);
    writeTestFile(menuPath, menu);
    writeTestFile(outputPath, {'o', 'l', 'd'});

    int signingCalls = 0;
    DylibBuilder builder(
        iconPlaceholder, menuPlaceholder,
        [](const std::vector<uint8_t>& bytes, std::string& error) {
            if(bytes.size() >= 4 && bytes[0] == 0x89 && bytes[1] == 'P') {
                return true;
            }
            error = "unsupported test icon";
            return false;
        },
        [&signingCalls, &outputPath](const std::string& path, std::string&) {
            signingCalls++;
            assert(path != outputPath);
            assert(!readTestFile(path).empty());
            return true;
        });

    H5GGDylibBuildRequest request = {
        sourcePath, iconPath, menuPath, outputPath,
    };
    H5GGDylibBuildResult built = builder.build(request);
    assert(built.completed());
    assert(built.outputPath == outputPath);
    assert(built.architectureCount == 2);
    assert(signingCalls == 1);

    std::vector<uint8_t> expected = source;
    assert(H5GGReplaceAllTemplates(expected, iconPlaceholder, icon) == 2);
    assert(H5GGReplaceAllTemplates(expected, menuPlaceholder, menu) == 2);
    assert(readTestFile(outputPath) == expected);
    assert(readTestFile(sourcePath) == source);

    writeTestFile(menuPath, {'a', 0, 'b'});
    assert(builder.build(request).status == H5GGDylibBuildStatus::InvalidMenu);
    assert(signingCalls == 1);
    assert(readTestFile(outputPath) == expected);

    writeTestFile(menuPath, menu);
    writeTestFile(iconPath, {});
    assert(builder.build(request).status == H5GGDylibBuildStatus::InvalidIcon);
    assert(signingCalls == 1);

    writeTestFile(iconPath, {'b', 'a', 'd'});
    H5GGDylibBuildResult invalidIcon = builder.build(request);
    assert(invalidIcon.status == H5GGDylibBuildStatus::InvalidIcon);
    assert(invalidIcon.detail == "unsupported test icon");
    assert(signingCalls == 1);

    writeTestFile(iconPath, std::vector<uint8_t>(iconPlaceholder.size(), 1));
    assert(builder.build(request).status == H5GGDylibBuildStatus::IconTooLarge);
    assert(signingCalls == 1);

    writeTestFile(iconPath, icon);
    std::vector<uint8_t> mismatched = iconPlaceholder;
    mismatched.insert(mismatched.end(), menuPlaceholder.begin(), menuPlaceholder.end());
    mismatched.insert(mismatched.end(), menuPlaceholder.begin(), menuPlaceholder.end());
    writeTestFile(sourcePath, mismatched);
    assert(builder.build(request).status == H5GGDylibBuildStatus::TemplateMismatch);
    assert(signingCalls == 1);

    writeTestFile(sourcePath, source);
    const std::vector<uint8_t> existing = {'k', 'e', 'e', 'p'};
    writeTestFile(outputPath, existing);
    DylibBuilder failingSigner(
        iconPlaceholder, menuPlaceholder,
        [](const std::vector<uint8_t>&, std::string&) { return true; },
        [](const std::string&, std::string& error) {
            error = "test signer failed";
            return false;
        });
    H5GGDylibBuildResult signingFailed = failingSigner.build(request);
    assert(signingFailed.status == H5GGDylibBuildStatus::SigningFailed);
    assert(signingFailed.detail == "test signer failed");
    assert(readTestFile(outputPath) == existing);

    assert(unlink(sourcePath.c_str()) == 0);
    assert(unlink(iconPath.c_str()) == 0);
    assert(unlink(menuPath.c_str()) == 0);
    assert(unlink(outputPath.c_str()) == 0);
    assert(rmdir(root) == 0);
}

static void streamsMemoryDumpsWithProgressFailureAndCancellation() {
    std::vector<uint8_t> source(20);
    for(size_t index = 0; index < source.size(); index++) {
        source[index] = static_cast<uint8_t>(index);
    }
    JJCallbackMemoryReader reader([&source](void* output,
                                            uint64_t address,
                                            size_t length) -> size_t {
        if(address < 0x3000 || address >= 0x3000 + source.size()) return 0;
        size_t offset = static_cast<size_t>(address - 0x3000);
        size_t available = std::min(length, source.size() - offset);
        size_t partial = std::min(available, (size_t)3);
        std::memcpy(output, source.data() + offset, partial);
        return partial;
    });

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

static void findsExactPointersThroughTheMemoryReader() {
    constexpr uint64_t base = 0x1000;
    constexpr uint64_t target = 0x1122334455667788ULL;
    std::vector<uint8_t> memory(0x80, 0);
    for(size_t offset : {size_t(0x08), size_t(0x18), size_t(0x40)}) {
        std::memcpy(memory.data() + offset, &target, sizeof(target));
    }
    std::memcpy(memory.data() + 0x31, &target, sizeof(target));
    JJBufferMemoryReader reader(base, memory);
    std::vector<JJPointerSearchRegion> regions = {
        {base + 0x40, 0x20},
        {base + 0x03, 0x35},
    };

    JJPointerSearchOptions options;
    options.chunkBytes = 16;
    auto results = JJFindExactPointers(target, base, base + memory.size(),
                                       regions, reader, options);
    assert((results == std::vector<std::pair<uint64_t, uint64_t>>{
        {base + 0x08, target},
        {base + 0x18, target},
        {base + 0x40, target},
    }));

    auto ranged = JJFindExactPointers(target, base + 0x10, base + 0x40,
                                      regions, reader, options);
    assert((ranged == std::vector<std::pair<uint64_t, uint64_t>>{
        {base + 0x18, target},
    }));

    options.maxResults = 2;
    auto cappedResults = JJFindExactPointers(target, base, base + memory.size(),
                                             regions, reader, options);
    assert(cappedResults.size() == 2);
    assert(cappedResults.back().first == base + 0x18);

    options.maxResults = 4096;
    options.maxScannedBytes = 16;
    auto cappedBytes = JJFindExactPointers(target, base, base + memory.size(),
                                           regions, reader, options);
    assert(cappedBytes.size() == 1);
    assert(cappedBytes.front().first == base + 0x08);

    options.maxScannedBytes = 7;
    assert(JJFindExactPointers(target, base, base + memory.size(),
                               regions, reader, options).empty());
    options.maxScannedBytes = 64;
    options.chunkBytes = 7;
    assert(JJFindExactPointers(target, base, base + memory.size(),
                               regions, reader, options).empty());

    options.chunkBytes = 16;
    std::vector<JJPointerSearchRegion> overflowRegion = {
        {std::numeric_limits<uint64_t>::max() - 15, 32},
    };
    assert(JJFindExactPointers(target,
                               std::numeric_limits<uint64_t>::max() - 15,
                               std::numeric_limits<uint64_t>::max(),
                               overflowRegion, reader, options).empty());
}

static void deviceFixtureLayoutIsStableForTheValidationScript() {
    assert(H5GGPhase2FixtureMarker == 5212150515364943416ULL);
    assert(sizeof(H5GGPhase2DeviceFixture) == 128);
    assert(offsetof(H5GGPhase2DeviceFixture, pointerToMarker) == 64);
    assert(offsetof(H5GGPhase2DeviceFixture, boundaryAddress) == 72);
    assert(offsetof(H5GGPhase2DeviceFixture, dumpAddress) == 88);
    assert(offsetof(H5GGPhase2DeviceFixture, cancelAddress) == 104);
    assert(offsetof(H5GGPhase2DeviceFixture, hexBytes) == 120);
}

int main() {
    targetSessionsOwnExactlyOneTargetAndEngine();
    modalRequestsAreRequestScopedAndSerial();
    scriptStoreOwnsConfinementAndAtomicIO();
    recountsAddressesAcrossRegions();
    typedRegionsRequireOneTypePerAddress();
    untypedRegionsUseTheFallbackType();
    replacingRegionsUpdatesTheCount();
    filtersAllSupportedValueKinds();
    filtersEveryNumericTypeInEveryDocumentedMode();
    parsesValuesAccordingToTheirDeclaredType();
    formatsValuesAccordingToTheirDeclaredType();
    centralizesTypeNamesAndToleranceParsing();
    parsesGroupedSearchExpressionsAtomically();
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
    memoryReaderUnifiesRawExactAndTypedReads();
    dylibBuilderOwnsValidationOutputAndSigning();
    streamsMemoryDumpsWithProgressFailureAndCancellation();
    findsExactPointersThroughTheMemoryReader();
    deviceFixtureLayoutIsStableForTheValidationScript();
    return 0;
}
