const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, '..', 'FloatMenu.mm'), 'utf8');

function assert(condition, message) {
    if (!condition) {
        console.error(`FAIL window action dispatch: ${message}`);
        process.exitCode = 1;
    }
}

assert(source.includes('H5GGInvokeWindowAction'), 'window actions need an explicit typed dispatcher');
assert(source.includes('setWindowDrag') && source.includes('args.count != 4'),
    'setWindowDrag must accept exactly four arguments');
assert(source.includes('void (^callback)(int, int, int, int)'),
    'four-coordinate actions must invoke their registered block with four integers');
assert(!/action methodSignatureForSelector:@selector\(invoke\)/.test(source),
    'window action arity must not rely on the generic block invoke signature');

if (!process.exitCode) console.log('Window action dispatch contract tests passed');
