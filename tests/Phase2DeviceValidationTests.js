const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(
    path.join(root, 'examples-JavaScript/h5ggV8/phase2DeviceValidation.js'),
    'utf8'
);

const fixtureBase = 0x1000n;
const boundaryAddress = 0x2000n;
const dumpAddress = 0x3000n;
const dumpSize = 52n;
const cancelAddress = 0x4000n;
const cancelSize = 32n * 1024n * 1024n;
const marker = '5212150515364943416';
const asHex = value => `0x${value.toString(16).toUpperCase()}`;

const typedFixtures = new Map([
    [`${asHex(fixtureBase + 8n)}:I8`, '-101'],
    [`${asHex(fixtureBase + 9n)}:U8`, '211'],
    [`${asHex(fixtureBase + 10n)}:I16`, '-23456'],
    [`${asHex(fixtureBase + 12n)}:U16`, '54321'],
    [`${asHex(fixtureBase + 16n)}:I32`, '-123456789'],
    [`${asHex(fixtureBase + 20n)}:U32`, '3456789012'],
    [`${asHex(fixtureBase + 24n)}:I64`, '-5124095576030430'],
    [`${asHex(fixtureBase + 32n)}:U64`, '18364758544493064720'],
    [`${asHex(fixtureBase + 40n)}:F32`, '1234.250000'],
    [`${asHex(fixtureBase + 48n)}:F64`, '-98765.125000'],
    [`${asHex(fixtureBase + 72n)}:U64`, boundaryAddress.toString()],
    [`${asHex(fixtureBase + 88n)}:U64`, dumpAddress.toString()],
    [`${asHex(fixtureBase + 96n)}:U64`, dumpSize.toString()],
    [`${asHex(fixtureBase + 104n)}:U64`, cancelAddress.toString()],
    [`${asHex(fixtureBase + 112n)}:U64`, cancelSize.toString()],
]);

const numericLocations = new Map([
    ['I8:-101', fixtureBase + 8n],
    ['U8:211', fixtureBase + 9n],
    ['I16:-23456', fixtureBase + 10n],
    ['U16:54321', fixtureBase + 12n],
    ['I32:-123456789', fixtureBase + 16n],
    ['U32:3456789012', fixtureBase + 20n],
    ['I64:-5124095576030430', fixtureBase + 24n],
    ['U64:18364758544493064720', fixtureBase + 32n],
    ['F32:1234.25', fixtureBase + 40n],
    ['F64:-98765.125', fixtureBase + 48n],
]);

let results = [];
let frozenAddress = null;
let dumpStatus = {state: 'idle', progress: 0};
let cancelCompletion = null;
let appendedLog = null;
let copiedText = null;
const storedFiles = new Map();

const resultAt = (address, value, type) => ({address: asHex(address), value, type});
const h5gg = {
    async getTargetStatus() {
        return {available: true, pid: 4242, selected: true};
    },
    async getPointerCapabilities() {
        return {
            pointerWidth: 64,
            alignment: 8,
            exactMatchesOnly: true,
            maxResults: 4096,
            maxScannedBytes: 512 * 1024 * 1024,
            maxChainDepth: 32,
        };
    },
    async getRangesList(filter) {
        assert.strictEqual(filter, 'H5GG.dylib');
        return [{name: '/Library/H5GG.dylib', start: '0x1000', end: '0x2000'}];
    },
    async clearResults() {
        results = [];
    },
    async searchNumber(value, type) {
        if(value === marker && type === 'U64') {
            results = [resultAt(fixtureBase, marker, 'U64')];
            return;
        }
        if(value === '135791357,246802468' && type === 'I32') {
            results = [
                resultAt(fixtureBase + 56n, '135791357', 'I32'),
                resultAt(fixtureBase + 60n, '246802468', 'I32'),
            ];
            return;
        }
        if(value === '135791357' && type === 'I32' && results.length === 2) {
            results = [results[0]];
            return;
        }
        const address = numericLocations.get(`${type}:${value}`);
        results = address === undefined ? [] : [resultAt(address, value, type)];
    },
    async getResultsCount() {
        return results.length;
    },
    async getResults(maxCount, skipCount) {
        return results.slice(skipCount, skipCount + maxCount);
    },
    async setFloatTolerance() {},
    async getValue(address, type) {
        if(frozenAddress === address && type === 'I32') return '-123456789';
        return typedFixtures.get(`${address}:${type}`) || '';
    },
    async setValue(address, value, type) {
        typedFixtures.set(`${address}:${type}`, value);
        return true;
    },
    async searchFilter(value, type, mode) {
        assert.strictEqual(type, 'I32');
        assert([0, 2, 3].includes(mode));
        assert(value === '135791357' || value === '246802468');
        results = [results[mode === 3 ? 0 : 1]];
        return 1;
    },
    async searchHex(pattern) {
        assert(pattern === 'de AD ?? eF cA Fe b? 0b' ||
               pattern === 'DE AD BE EF CA FE B0 0B');
        results = [resultAt(fixtureBase + 120n, 'DE', 'U8')];
    },
    async freezeValue(address) {
        frozenAddress = address;
        return true;
    },
    async unfreezeValue(address) {
        assert.strictEqual(address, frozenAddress);
        frozenAddress = null;
        return true;
    },
    async getFrozenValues() {
        return frozenAddress ? [{address: frozenAddress}] : [];
    },
    async readPointer(address) {
        assert.strictEqual(address, asHex(fixtureBase + 64n));
        return asHex(fixtureBase);
    },
    async findPointers(address) {
        assert.strictEqual(address, asHex(fixtureBase));
        return [{address: asHex(fixtureBase + 64n), value: asHex(fixtureBase)}];
    },
    async readMemoryPage(address, length) {
        assert.strictEqual(address, asHex(boundaryAddress));
        assert.strictEqual(length, 256);
        return {
            readable: 128,
            complete: false,
            bytes: [...Array(128).fill(0x5A), ...Array(128).fill(null)],
        };
    },
    dumpMemory(start, end, filename) {
        if(start === asHex(dumpAddress)) {
            assert.strictEqual(end, asHex(dumpAddress + dumpSize));
            let content = '';
            for(let index = 0; index < Number(dumpSize); index++) {
                content += String.fromCharCode(65 + index % 26);
            }
            storedFiles.set(filename, content);
            dumpStatus = {
                state: 'completed', progress: 1,
                written: dumpSize.toString(), total: dumpSize.toString(),
            };
            return Promise.resolve(true);
        }
        if(start === asHex(cancelAddress)) {
            assert.strictEqual(end, asHex(cancelAddress + cancelSize));
            dumpStatus = {state: 'running', progress: 0, written: 0, total: cancelSize.toString()};
            return new Promise(resolve => {
                cancelCompletion = resolve;
            });
        }
        assert.strictEqual(start, asHex(boundaryAddress));
        dumpStatus = {state: 'failed', progress: 0, error: 'unreadable'};
        return Promise.resolve(false);
    },
    async getDumpStatus() {
        return dumpStatus;
    },
    async cancelDump() {
        assert(cancelCompletion);
        dumpStatus = {state: 'cancelled', progress: 0};
        cancelCompletion(false);
        cancelCompletion = null;
        return true;
    },
    async loadScript(filename) {
        return storedFiles.has(filename) ? storedFiles.get(filename) : null;
    },
    async saveScript(filename, content) {
        if(filename.includes('/')) return false;
        storedFiles.set(filename, content);
        return true;
    },
    async deleteScript(filename) {
        return storedFiles.delete(filename);
    },
    async appendLog(message) {
        appendedLog = message;
    },
    async copyText(text) {
        copiedText = text;
        return true;
    },
};

const context = {
    console,
    h5gg,
    navigator: {userAgent: 'Phase2DeviceValidationTests/1.0'},
    location: {href: 'file:///phase2-test.html'},
    setTimeout(callback) {
        callback();
        return 1;
    },
};
context.window = context;
context.__h5gg_native = async method => {
    throw new Error(`Unknown bridge method: ${method}`);
};

vm.createContext(context);
vm.runInContext(source, context, {filename: 'phase2DeviceValidation.js'});

(async () => {
    const report = await context.runH5GGPhase2DeviceValidation({
        device: 'mock-device',
        ios: 'mock-ios',
        jailbreak: 'mock-bootstrap',
        scheme: 'rootless',
        mode: 'standalone',
    });

    assert.strictEqual(report.ok, true, JSON.stringify(report.failed));
    assert.strictEqual(report.failed.length, 0);
    assert.strictEqual(report.passed.length, 15);
    assert.strictEqual(report.metadata.device, 'mock-device');
    assert.strictEqual(report.metadata.mode, 'standalone');
    assert.strictEqual(report.runtime.target.pid, 4242);
    assert.strictEqual(report.runtime.pointerCapabilities.maxChainDepth, 32);
    assert.strictEqual(report.runtime.fixtureModule.name, '/Library/H5GG.dylib');
    assert.strictEqual(appendedLog, copiedText);
    assert.deepStrictEqual(JSON.parse(appendedLog), JSON.parse(JSON.stringify(report)));
    assert(!storedFiles.has('phase2-readable-dump.html'));
    assert(!storedFiles.has('phase2-cancelled-dump.html'));
    assert(!storedFiles.has('phase2-unreadable-dump.html'));
    assert(!storedFiles.has('phase2-store.js'));

    console.log(`Phase 2 device runner completed ${report.passed.length} mocked checks`);
})().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
