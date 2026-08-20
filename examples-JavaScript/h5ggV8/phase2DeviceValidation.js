// Phase 2 device validation fixture runner.
// Build H5GG with H5GG_DEVICE_VALIDATION=1 before running this script.

window.runH5GGPhase2DeviceValidation = async function runH5GGPhase2DeviceValidation(options = {}) {
    const supplied = options && typeof options === "object" ? options : {};
    const metadata = {};
    for(const key of ["device", "ios", "jailbreak", "scheme", "mode"]) {
        if(typeof supplied[key] === "string") metadata[key] = supplied[key];
    }
    const report = {
        startedAt: new Date().toISOString(),
        metadata,
        runtime: {
            userAgent: navigator.userAgent,
            url: window.location.href,
        },
        passed: [],
        failed: [],
    };
    const marker = 5212150515364943416n;
    const fixtureBytes = 128n;
    const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
    const hex = value => `0x${value.toString(16).toUpperCase()}`;
    const addressAt = (base, offset) => hex(base + BigInt(offset));
    const requireCondition = (condition, message) => {
        if(!condition) throw new Error(message);
    };
    const record = async (name, operation) => {
        try {
            await operation();
            report.passed.push(name);
        } catch(error) {
            report.failed.push({name, error: String(error && error.message || error)});
        }
    };
    const requireSearchAddress = async (value, type, expectedAddress, start, end) => {
        await h5gg.clearResults();
        await h5gg.searchNumber(value, type, start, end);
        const count = await h5gg.getResultsCount();
        const results = await h5gg.getResults(Math.max(1, Math.min(256, count)), 0);
        requireCondition(results.some(result => BigInt(result.address) === expectedAddress),
                         `${type} search missed ${hex(expectedAddress)}`);
    };

    await record("capture target and pointer capabilities", async () => {
        report.runtime.target = await h5gg.getTargetStatus();
        report.runtime.pointerCapabilities = await h5gg.getPointerCapabilities();
    });

    await record("unknown WK bridge method rejection", async () => {
        requireCondition(typeof window.__h5gg_native === "function",
                         "WK bridge invocation function is unavailable");
        let rejection = "";
        try {
            await window.__h5gg_native("__phase2UnknownMethod", []);
        } catch(error) {
            rejection = String(error);
        }
        requireCondition(rejection.includes("Unknown bridge method"),
                         `unexpected bridge rejection: ${rejection || "none"}`);
    });

    let fixtureBase = 0n;
    let fixtureStart = "";
    let fixtureEnd = "";
    await record("locate validation fixture", async () => {
        const ranges = await h5gg.getRangesList("H5GG.dylib");
        requireCondition(Array.isArray(ranges) && ranges.length === 1,
                         "H5GG.dylib range is unavailable");
        await h5gg.clearResults();
        await h5gg.searchNumber(marker.toString(), "U64", ranges[0].start, ranges[0].end);
        const count = await h5gg.getResultsCount();
        const results = await h5gg.getResults(Math.max(1, Math.min(64, count)), 0);
        const match = results.find(result => result.value === marker.toString());
        requireCondition(match, "validation marker was not found; rebuild with H5GG_DEVICE_VALIDATION=1");
        report.runtime.fixtureModule = ranges[0];
        fixtureBase = BigInt(match.address);
        fixtureStart = hex(fixtureBase);
        fixtureEnd = hex(fixtureBase + fixtureBytes);
    });

    if(fixtureBase !== 0n) {
        const typedValues = [
            {type: "I8", offset: 8, value: "-101"},
            {type: "U8", offset: 9, value: "211"},
            {type: "I16", offset: 10, value: "-23456"},
            {type: "U16", offset: 12, value: "54321"},
            {type: "I32", offset: 16, value: "-123456789"},
            {type: "U32", offset: 20, value: "3456789012"},
            {type: "I64", offset: 24, value: "-5124095576030430"},
            {type: "U64", offset: 32, value: "18364758544493064720"},
            {type: "F32", offset: 40, value: "1234.25", read: "1234.250000"},
            {type: "F64", offset: 48, value: "-98765.125", read: "-98765.125000"},
        ];

        await record("numeric first search for every type", async () => {
            await h5gg.setFloatTolerance("0");
            for(const fixture of typedValues) {
                await requireSearchAddress(fixture.value, fixture.type,
                                           fixtureBase + BigInt(fixture.offset),
                                           fixtureStart, fixtureEnd);
            }
        });

        await record("typed read and write", async () => {
            for(const fixture of typedValues) {
                const address = addressAt(fixtureBase, fixture.offset);
                const original = await h5gg.getValue(address, fixture.type);
                requireCondition(original === (fixture.read || fixture.value),
                                 `${fixture.type} read returned ${original}`);
            }
            const i32Address = addressAt(fixtureBase, 16);
            requireCondition(await h5gg.setValue(i32Address, "-123456788", "I32"),
                             "I32 write failed");
            requireCondition(await h5gg.getValue(i32Address, "I32") === "-123456788",
                             "I32 write was not observable");
            requireCondition(await h5gg.setValue(i32Address, "-123456789", "I32"),
                             "I32 restore failed");
        });

        await record("grouped and refined numeric search", async () => {
            await h5gg.clearResults();
            await h5gg.searchNumber("135791357,246802468", "I32", fixtureStart, fixtureEnd);
            requireCondition(await h5gg.getResultsCount() === 2, "group OR search did not find two values");
            await h5gg.searchNumber("135791357", "I32", fixtureStart, fixtureEnd);
            requireCondition(await h5gg.getResultsCount() === 1, "numeric refinement did not retain one value");
        });

        await record("equal greater and less filters", async () => {
            for(const [mode, expected] of [[0, 1], [2, 1], [3, 1]]) {
                await h5gg.clearResults();
                await h5gg.searchNumber("135791357,246802468", "I32", fixtureStart, fixtureEnd);
                const threshold = mode === 3 ? "246802468" : "135791357";
                const kept = await h5gg.searchFilter(threshold, "I32", mode);
                requireCondition(kept === expected && await h5gg.getResultsCount() === expected,
                                 `filter mode ${mode} returned inconsistent counts`);
            }
        });

        await record("hex first and refine search", async () => {
            await h5gg.clearResults();
            await h5gg.searchHex("de AD ?? eF cA Fe b? 0b", fixtureStart, fixtureEnd);
            requireCondition(await h5gg.getResultsCount() === 1, "wildcard hex search missed fixture");
            await h5gg.searchHex("DE AD BE EF CA FE B0 0B", fixtureStart, fixtureEnd);
            requireCondition(await h5gg.getResultsCount() === 1, "hex refinement changed the match");
        });

        await record("freezer write and teardown", async () => {
            const address = addressAt(fixtureBase, 16);
            requireCondition(await h5gg.freezeValue(address, "-123456789", "I32"),
                             "freeze request failed");
            requireCondition(await h5gg.setValue(address, "7", "I32"), "pre-freeze mutation failed");
            await delay(250);
            requireCondition(await h5gg.getValue(address, "I32") === "-123456789",
                             "freezer did not restore the value");
            requireCondition(await h5gg.unfreezeValue(address), "unfreeze failed");
            requireCondition((await h5gg.getFrozenValues()).length === 0, "freezer retained an entry");
        });

        await record("exact pointer search and read", async () => {
            const pointerSlot = fixtureBase + 64n;
            requireCondition(BigInt(await h5gg.readPointer(hex(pointerSlot))) === fixtureBase,
                             "pointer slot did not resolve to marker");
            const pointers = await h5gg.findPointers(hex(fixtureBase), fixtureStart, fixtureEnd);
            requireCondition(pointers.some(pointer => BigInt(pointer.address) === pointerSlot),
                             "exact pointer search missed the fixture slot");
        });

        await record("partial memory page at protection boundary", async () => {
            const boundary = BigInt(await h5gg.getValue(addressAt(fixtureBase, 72), "U64"));
            requireCondition(boundary !== 0n, "boundary fixture allocation failed");
            const page = await h5gg.readMemoryPage(hex(boundary), 256);
            requireCondition(page.readable === 128 && page.complete === false,
                             `boundary read reported ${page.readable} readable bytes`);
            requireCondition(page.bytes.slice(0, 128).every(value => value === 0x5A),
                             "readable boundary bytes are wrong");
            requireCondition(page.bytes.slice(128).every(value => value === null),
                             "unreadable boundary bytes were not null");
        });

        await record("readable dump publication", async () => {
            const dumpAddress = BigInt(await h5gg.getValue(addressAt(fixtureBase, 88), "U64"));
            const dumpSize = BigInt(await h5gg.getValue(addressAt(fixtureBase, 96), "U64"));
            requireCondition(dumpAddress !== 0n && dumpSize > 0n, "dump fixture allocation failed");
            const filename = "phase2-readable-dump.html";
            requireCondition(await h5gg.dumpMemory(hex(dumpAddress), hex(dumpAddress + dumpSize), filename),
                             "readable dump failed");
            const status = await h5gg.getDumpStatus();
            requireCondition(status.state === "completed" && BigInt(status.written) === dumpSize,
                             "readable dump status is inconsistent");
            const content = await h5gg.loadScript(filename);
            let expected = "";
            for(let index = 0; index < Number(dumpSize); index++) {
                expected += String.fromCharCode(65 + index % 26);
            }
            requireCondition(content === expected, "dump file differs from fixture memory");
            requireCondition(await h5gg.deleteScript(filename), "readable dump cleanup failed");
        });

        await record("cancelled dump cleanup", async () => {
            const cancelAddress = BigInt(await h5gg.getValue(addressAt(fixtureBase, 104), "U64"));
            const cancelSize = BigInt(await h5gg.getValue(addressAt(fixtureBase, 112), "U64"));
            requireCondition(cancelAddress !== 0n && cancelSize > 0n, "cancel fixture allocation failed");
            const dumpPromise = (async () => await h5gg.dumpMemory(
                hex(cancelAddress), hex(cancelAddress + cancelSize), "phase2-cancelled-dump.html"))();
            await delay(10);
            requireCondition(await h5gg.cancelDump(), "cancelDump rejected the running dump");
            requireCondition(await dumpPromise === false, "cancelled dump resolved true");
            requireCondition((await h5gg.getDumpStatus()).state === "cancelled",
                             "cancelled dump status is wrong");
            requireCondition(await h5gg.loadScript("phase2-cancelled-dump.html") === null,
                             "cancelled dump retained a partial file");
        });

        await record("unreadable dump cleanup", async () => {
            const boundary = BigInt(await h5gg.getValue(addressAt(fixtureBase, 72), "U64"));
            requireCondition(await h5gg.dumpMemory(
                hex(boundary), hex(boundary + 256n), "phase2-unreadable-dump.html") === false,
                "unreadable dump resolved true");
            requireCondition((await h5gg.getDumpStatus()).state === "failed",
                             "unreadable dump status is wrong");
            requireCondition(await h5gg.loadScript("phase2-unreadable-dump.html") === null,
                             "unreadable dump retained a partial file");
        });

        await record("script store policy", async () => {
            requireCondition(await h5gg.saveScript("phase2-store.js", "window.phase2Store = true;"),
                             "valid script save failed");
            requireCondition(await h5gg.loadScript("phase2-store.js") === "window.phase2Store = true;",
                             "valid script load failed");
            requireCondition(await h5gg.saveScript("../phase2-escape.js", "bad") === false,
                             "traversal script name was accepted");
            requireCondition(await h5gg.deleteScript("phase2-store.js"), "script delete failed");
        });
    }

    report.finishedAt = new Date().toISOString();
    report.ok = report.failed.length === 0;
    const serialized = JSON.stringify(report, null, 2);
    await h5gg.appendLog(serialized);
    await h5gg.copyText(serialized);
    return report;
};
