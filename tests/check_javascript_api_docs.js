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

function collectJavaScriptFiles(directory) {
    const ignoredDirectories = new Set(['Dobby-fixed', 'node_modules', '.git', '.theos']);
    const files = [];
    for(const entry of fs.readdirSync(directory, {withFileTypes: true})) {
        if(entry.isDirectory()) {
            if(!ignoredDirectories.has(entry.name)) {
                files.push(...collectJavaScriptFiles(path.join(directory, entry.name)));
            }
        } else if(entry.isFile() && entry.name.endsWith('.js')) {
            files.push(path.join(directory, entry.name));
        }
    }
    return files;
}

const exampleRoots = ['examples-HTML5', 'examples-JavaScript', 'examples-h5frida', 'pluginDemo'];
const legacyMarker = 'LEGACY-JAVASCRIPTCORE-ONLY';
for(const exampleRoot of exampleRoots) {
    for(const file of collectJavaScriptFiles(path.join(root, exampleRoot))) {
        const source = fs.readFileSync(file, 'utf8');
        const isLegacy = source.includes(legacyMarker);
        for(const match of source.matchAll(/h5gg\.([A-Za-z][A-Za-z0-9_]*)\s*\(/g)) {
            const method = match[1];
            assert(
                bridgeMethods.includes(method),
                `${path.relative(root, file)} calls unknown bridge method h5gg.${method}`
            );
            if(!isLegacy) {
                const lineStart = source.lastIndexOf('\n', match.index) + 1;
                const prefix = source.slice(lineStart, match.index);
                assert(
                    /\bawait\s*$/.test(prefix),
                    `${path.relative(root, file)} must await h5gg.${method} or be marked ${legacyMarker}`
                );
            }
        }
    }
}

const rpcExample = fs.readFileSync(
    path.join(root, 'pluginDemo/customAlert/customAlert.js'), 'utf8'
);
assert(/await\s+h5gg\.loadPlugin\(/.test(rpcExample));
assert(/await\s+h5gg\.callPlugin\(/.test(rpcExample));

console.log(`JavaScript API documentation covers ${bridgeMethods.length} bridge methods`);
