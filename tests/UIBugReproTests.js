#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

const ROOT = path.resolve(__dirname, '..');
const CDP_HTTP = process.env.H5GG_CDP_HTTP || 'http://127.0.0.1:9333';
const JQUERY = fs.readFileSync(path.join(ROOT, 'jquery.min.js'), 'utf8');
const FIXTURE_PATH = path.join(ROOT, 'tests/fixtures/ui-load-script.js');

function bridgeMockSource() {
    return `
window.__mock = {
    alerts: [], prompts: [], copied: [], bookmarks: [], frozen: [], rects: [],
    results: [{address:'0x100000010', type:'I32', value:'42'}],
    searchPending: false, searchResolved: false, loadedScripts: []
};
window.alert = function(message) { window.__mock.alerts.push(String(message)); };
window.prompt = function(message, value) {
    window.__mock.prompts.push(String(message));
    return String(message).toLowerCase().includes('bookmark') || String(message).includes('\u4e66\u7b7e') ? 'Test bookmark' : (value || '42');
};
window.confirm = function() { return true; };
window.h5gg_internel_version = 8;
window.setWindowDrag = function() {};
window.setLayoutAction = function(callback) { window.__mock.layoutAction = callback; callback(1024, 768); };
window.setWindowRect = function(x,y,w,h) { window.__mock.rects.push({x,y,w,h}); };
window.setWindowVisible = function() {};
window.setButtonImage = function() {};
window.setFloatWindow = function() {};
window.h5gg = {
    appendLog: async function() {},
    clearResults: async function() {},
    getProcList: async function() { return null; },
    getResultsCount: async function() { return window.__mock.results.length; },
    getResults: async function(count, from) { return window.__mock.results.slice(from, from + count); },
    getValue: async function(address, type) { return type === 'U8' ? '17' : '42'; },
    setValue: async function() { return true; },
    editAll: async function() { return 1; },
    setFloatTolerance: async function() {},
    searchNumber: function() {
        window.__mock.searchPending = true;
        return new Promise(function(resolve) {
            window.__mock.resolveSearch = function() {
                window.__mock.searchPending = false;
                window.__mock.searchResolved = true;
                resolve(true);
            };
        });
    },
    searchNearby: async function() {}, searchHex: async function() {}, searchFilter: async function() {},
    addSearchHistory: async function() {}, getSearchHistory: async function() { return []; }, clearSearchHistory: async function() {},
    addBookmark: async function(address, name, type) { window.__mock.bookmarks.push({address,name,type}); return true; },
    getBookmarks: async function() { return window.__mock.bookmarks.slice(); },
    removeBookmark: async function() {}, clearBookmarks: async function() { window.__mock.bookmarks = []; },
    freezeValue: async function(address, value, type) { window.__mock.frozen.push({address,value,type,status:'active'}); return true; },
    getFrozenValues: async function() { return window.__mock.frozen.slice(); },
    unfreezeValue: async function() {}, clearFrozenValues: async function() { window.__mock.frozen = []; },
    copyText: async function(value) { window.__mock.copied.push(String(value)); return true; },
    getLocalScripts: async function() { return [{name:'ui-load-script.js',path:${JSON.stringify(FIXTURE_PATH)}}]; },
    pickScriptFile: async function() { return null; },
    listScripts: async function() { return ['example.js']; },
    loadScript: async function(name) { window.__mock.loadedScripts.push(name); return 'window.__bridgeLoadedScript = true;'; },
    saveScript: async function() { return true; }, deleteScript: async function() { return true; }, getLastFileError: async function() { return null; },
    getRangesList: async function() { return [{name:'TestBinary',start:'0x100000000',end:'0x100010000'}]; },
    readMemoryPage: async function(address, size) {
        var bytes = []; for(var i=0;i<size;i++) bytes.push(i & 255);
        return {address:address, bytes:bytes};
    },
    readPointer: async function() { return '0x100000100'; },
    dumpMemory: async function() { return true; }, cancelDump: async function() {}, getDumpStatus: async function() { return {state:'done',progress:1}; },
    makeTweak: async function() { return ''; }
};
`;
}

class CDPClient {
    constructor(socket) {
        this.socket = socket;
        this.nextId = 1;
        this.pending = new Map();
        this.events = new Map();
        socket.addEventListener('message', event => {
            const message = JSON.parse(event.data);
            if (message.id) {
                const pending = this.pending.get(message.id);
                if (!pending) return;
                this.pending.delete(message.id);
                if (message.error) pending.reject(new Error(message.error.message));
                else pending.resolve(message.result);
                return;
            }
            const waiters = this.events.get(message.method) || [];
            this.events.delete(message.method);
            waiters.forEach(resolve => resolve(message.params));
        });
    }

    send(method, params = {}) {
        const id = this.nextId++;
        return new Promise((resolve, reject) => {
            this.pending.set(id, {resolve, reject});
            this.socket.send(JSON.stringify({id, method, params}));
        });
    }

    event(method) {
        return new Promise(resolve => {
            const waiters = this.events.get(method) || [];
            waiters.push(resolve);
            this.events.set(method, waiters);
        });
    }

    close() {
        this.socket.close();
    }
}

async function connect(url) {
    const socket = new WebSocket(url);
    await new Promise((resolve, reject) => {
        socket.addEventListener('open', resolve, {once:true});
        socket.addEventListener('error', reject, {once:true});
    });
    return new CDPClient(socket);
}

async function evaluate(client, expression) {
    const reply = await client.send('Runtime.evaluate', {
        expression: `(async function(){${expression}})()`,
        awaitPromise: true,
        returnByValue: true
    });
    if (reply.exceptionDetails) {
        const detail = reply.exceptionDetails.exception && reply.exceptionDetails.exception.description;
        throw new Error(detail || reply.exceptionDetails.text);
    }
    return reply.result.value;
}

async function openPage(fileName) {
    const target = await fetch(`${CDP_HTTP}/json/new?about:blank`, {method:'PUT'}).then(response => response.json());
    const client = await connect(target.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Page.addScriptToEvaluateOnNewDocument', {source: JQUERY});
    await client.send('Page.addScriptToEvaluateOnNewDocument', {source: bridgeMockSource()});
    const loaded = client.event('Page.loadEventFired');
    await client.send('Page.navigate', {url:pathToFileURL(path.join(ROOT, fileName)).href});
    await loaded;
    await new Promise(resolve => setTimeout(resolve, 100));
    return client;
}

const checks = [
    ['search overlay remains visible until the bridge resolves and reports completion', async client => {
        return evaluate(client, `
            onClickSearchNumber();
            document.querySelector('#datavalue').value = '42';
            document.querySelector('#popup_search_edit #action').click();
            await new Promise(r => setTimeout(r, 300));
            var busy = document.querySelector('[data-search-progress]');
            var pendingVisible = !!busy && getComputedStyle(busy).display !== 'none' && __mock.searchPending;
            __mock.resolveSearch && __mock.resolveSearch();
            await new Promise(r => setTimeout(r, 100));
            var completed = !!document.querySelector('[data-search-status="complete"]');
            return pendingVisible && completed;
        `);
    }],
    ['closing Settings removes conflicting modal layers and stale inputs', async client => {
        return evaluate(client, `
            onClickSearchNumber();
            openSettings();
            closeOverlay('settingsOverlay');
            var stale = ['#popup_search_edit','#popup_progress','#maskview','#maskview_script']
                .some(function(selector) { var node=document.querySelector(selector); return node && getComputedStyle(node).display !== 'none'; });
            return !stale && !document.querySelector('#settingsOverlay');
        `);
    }],
    ['result row opens actions reliably and bookmark/freeze controls become active', async client => {
        return evaluate(client, `
            renderResults(__mock.results);
            var row = document.querySelector('.result-row');
            for(var i=0;i<20;i++) {
                row.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,pointerType:'touch'}));
                row.click();
                if(typeof dismissResultActions === 'function') dismissResultActions();
                if(typeof closeResultActions === 'function') closeResultActions();
            }
            row.click();
            var actionVisible = !!document.querySelector('#resultActionMask, #uiResultActionMask') &&
                Array.from(document.querySelectorAll('#resultActionMask, #uiResultActionMask')).some(n => getComputedStyle(n).display !== 'none');
            var buttons = row.querySelectorAll('.result-icon-button');
            buttons[0].click(); buttons[1].click();
            await new Promise(r => setTimeout(r, 50));
            return actionVisible && __mock.bookmarks.length === 1 && __mock.frozen.length === 1 &&
                buttons[0].classList.contains('active') && buttons[1].classList.contains('active');
        `);
    }],
    ['local script loading uses the native bridge and completes without URL errors', async client => {
        return evaluate(client, `
            onClickLoadScript(${JSON.stringify(FIXTURE_PATH)});
            await new Promise(r => setTimeout(r, 150));
            return __mock.loadedScripts.length === 1 && __mock.alerts.every(message => !message.includes('Load Error'));
        `);
    }],
    ['window resizing has an accessible handle and persists its dimensions', async client => {
        return evaluate(client, `
            var handle = document.querySelector('[data-window-resize]');
            return !!handle && !!localStorage.getItem('h5gg_window_size');
        `);
    }],
    ['script editor exposes API documentation and inserts a selected function call', async client => {
        return evaluate(client, `
            await openScriptEditor();
            var docs = document.querySelector('[data-api-docs]');
            var insert = document.querySelector('[data-api-insert]');
            var methods = document.querySelector('#h5ggApiMethod');
            if(!docs || !insert || !methods || methods.options.length < 52) return false;
            var editor = document.querySelector('#scriptEditor');
            editor.value = '';
            insert.click();
            return editor.value.includes('h5gg.');
        `);
    }],
    ['memory viewer starts at the binary base and offers row context actions', async client => {
        return evaluate(client, `
            await openMemoryViewer();
            await new Promise(r => setTimeout(r, 50));
            var input = document.querySelector('#viewerAddr');
            var row = document.querySelector('[data-memory-address]');
            if(row) row.click();
            var menu = document.querySelector('[data-memory-context]');
            return input && input.value.toLowerCase() === '0x100000000' && row && menu &&
                menu.querySelector('[data-memory-action="copy-address"]') &&
                menu.querySelector('[data-memory-action="copy-8-bytes"]') &&
                menu.querySelector('[data-memory-action="dump-start"]') &&
                menu.querySelector('[data-memory-action="dump-end"]');
        `);
    }],
    ['dedicated Base Address control displays the binary base', async client => {
        return evaluate(client, `
            var button = document.querySelector('[data-base-address-button]');
            if(!button) return false;
            button.click();
            await new Promise(r => setTimeout(r, 50));
            return document.body.textContent.toLowerCase().includes('0x100000000');
        `);
    }]
];

async function main() {
    let failures = 0;
    for (const fileName of ['Index.html', 'Index-en.html']) {
        const client = await openPage(fileName);
        try {
            for (const [name, check] of checks) {
                try {
                    const passed = await check(client);
                    console.log(`${passed ? 'PASS' : 'FAIL'} ${fileName}: ${name}`);
                    if (!passed) failures++;
                } catch (error) {
                    failures++;
                    console.log(`FAIL ${fileName}: ${name}`);
                    console.log(`     ${String(error.message).split('\n')[0]}`);
                }
            }
        } finally {
            client.close();
        }
    }
    if (failures) {
        console.error(`\n${failures} UI regression check(s) failed.`);
        process.exitCode = 1;
    } else {
        console.log('\nAll UI regression checks passed.');
    }
}

main().catch(error => {
    console.error(error.stack || error);
    process.exitCode = 1;
});
