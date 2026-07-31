const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

function extractFunction(html, name) {
    const start = html.indexOf(`function ${name}(`);
    assert.notStrictEqual(start, -1, `${name} must be exposed by Index-en.html`);

    const bodyStart = html.indexOf('{', start);
    let depth = 0;
    for(let index = bodyStart; index < html.length; index++) {
        if(html[index] === '{') depth++;
        if(html[index] === '}') {
            depth--;
            if(depth === 0) return html.slice(start, index + 1);
        }
    }
    throw new Error(`Unable to extract ${name}`);
}

const result = { address: '0x1026A38A0', value: '5', type: 'I32' };

for(const filename of ['Index-en.html', 'Index.html']) {
    const html = fs.readFileSync(new URL(`../${filename}`, `file://${__filename}`), 'utf8');
    const context = {};
    vm.createContext(context);
    vm.runInContext(extractFunction(html, 'getResultCopyText'), context);
    assert.strictEqual(context.getResultCopyText(result, 'address'), '0x1026A38A0');
    assert.strictEqual(context.getResultCopyText(result, 'value'), '5');
    assert.strictEqual(context.getResultCopyText(result, 'both'), '0x1026A38A0 = 5 [I32]');
    assert.strictEqual(context.getResultCopyText(result, 'unknown'), null);
}

console.log('Result action tests passed');
