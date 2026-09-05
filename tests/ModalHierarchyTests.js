const fs = require('fs');
const path = require('path');

const menuSource = fs.readFileSync(path.join(__dirname, '..', 'FloatMenu.mm'), 'utf8');
const modalSource = fs.readFileSync(path.join(__dirname, '..', 'ModalShow.mm'), 'utf8');

function methodBody(source, selector) {
    const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const start = source.search(new RegExp(`[+-] \\(.*?\\)${escaped}[^\\{]*\\{`));
    if (start < 0) throw new Error(`Missing method: ${selector}`);

    const open = source.indexOf('{', start);
    let depth = 0;
    for (let index = open; index < source.length; index++) {
        if (source[index] === '{') depth++;
        if (source[index] === '}' && --depth === 0) return source.slice(open + 1, index);
    }
    throw new Error(`Unterminated method: ${selector}`);
}

function assert(condition, message) {
    if (!condition) {
        console.error(`FAIL modal hierarchy: ${message}`);
        process.exitCode = 1;
    }
}

const present = methodBody(modalSource, 'present:');
assert(present.includes('makeWindow('), 'dialogs must use a dedicated overlay window');
assert(present.includes('dialogWindow.windowLevel'), 'the dialog overlay must set an explicit window level');
assert(present.includes('window.windowLevel + 1'), 'the dialog overlay must sit above its source window');
assert(present.includes('[dialogWindow setHidden:NO]'), 'the dialog overlay must be made visible');
assert(present.includes('[dialogWindow setHidden:YES]'), 'the dialog overlay must be hidden after completion');

for (const selector of ['alert:', 'confirm:', 'prompt:']) {
    const body = methodBody(menuSource, selector);
    assert(!body.includes('sendSubviewToBack:'), `${selector} must not reorder the web view around a modal`);
    assert(!body.includes('bringSubviewToFront:'), `${selector} must not reorder the web view around a modal`);
}

if (!process.exitCode) console.log('Modal hierarchy contract tests passed');
