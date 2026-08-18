const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const bridgeSource = fs.readFileSync(path.join(root, 'BridgeMethods.cpp'), 'utf8');
const documentation = fs.readFileSync(path.join(root, 'docs/javascript-api.md'), 'utf8');

const bridgeMethods = [...bridgeSource.matchAll(/^\s*\{"([^"]+)",/gm)]
    .map(match => match[1]);

const inventoryMatch = documentation.match(
    /<!-- bridge-methods:start -->([\s\S]*?)<!-- bridge-methods:end -->/
);
assert(inventoryMatch, 'JavaScript API documentation must contain the bridge inventory markers');

const documentedMethods = [...inventoryMatch[1].matchAll(/^- `([^`]+)`$/gm)]
    .map(match => match[1]);

assert.deepStrictEqual(
    documentedMethods,
    bridgeMethods,
    'docs/javascript-api.md bridge inventory must match BridgeMethods.cpp'
);

for(const method of bridgeMethods) {
    assert(
        documentation.includes(`h5gg.${method}(`),
        `docs/javascript-api.md must contain a reference entry for h5gg.${method}`
    );
}

console.log(`JavaScript API documentation covers ${bridgeMethods.length} bridge methods`);
