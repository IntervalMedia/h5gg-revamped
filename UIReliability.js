(function() {
    'use strict';

    var english = /Index-en\.html$/i.test(location.pathname) || document.documentElement.lang === 'en';
    var text = english ? {
        searching: 'Searching memory…', complete: 'Search complete', failed: 'Search failed',
        bookmark: 'Bookmark', frozen: 'Frozen', scriptRunning: 'Loading script…',
        scriptComplete: 'Script loaded', scriptFailed: 'Unable to load script',
        baseAddress: 'Base Address', unavailable: 'Unavailable', copy: 'Copy', close: 'Close',
        copyValue: 'Copy Value', copyAddressResult: 'Copy Address', choose: 'Choose an option',
        viewer: 'Memory Viewer', address: 'Address', go: 'Go', copyAddress: 'Copy address',
        copyBytes: 'Copy 8-byte hex value', dumpStart: 'Use as dump start', dumpEnd: 'Use as dump end',
        apiDocs: 'API Docs', insertCall: 'Insert call', okay: 'OK'
    } : {
        searching: '正在搜索内存…', complete: '搜索完成', failed: '搜索失败',
        bookmark: '书签', frozen: '已冻结', scriptRunning: '正在加载脚本…',
        scriptComplete: '脚本已加载', scriptFailed: '无法加载脚本',
        baseAddress: '基址', unavailable: '不可用', copy: '复制', close: '关闭',
        copyValue: '复制数值', copyAddressResult: '复制地址', choose: '选择选项',
        viewer: '内存查看器', address: '地址', go: '跳转', copyAddress: '复制地址',
        copyBytes: '复制 8 字节十六进制值', dumpStart: '设为导出起始地址', dumpEnd: '设为导出结束地址',
        apiDocs: 'API 文档', insertCall: '插入调用', okay: '确定'
    };

    var style = document.createElement('style');
    style.textContent =
        '#h5ggSearchProgress{position:fixed;inset:0;z-index:120000;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center}' +
        '#h5ggSearchProgress .card{min-width:190px;padding:18px;border-radius:12px;background:var(--bg-color,#fff);color:var(--text-color,#111);text-align:center;box-shadow:0 8px 28px rgba(0,0,0,.35)}' +
        '#h5ggSearchProgress .spinner{width:28px;height:28px;margin:0 auto 10px;border:3px solid rgba(51,147,239,.25);border-top-color:#3393ef;border-radius:50%;animation:h5gg-spin .8s linear infinite}' +
        '@keyframes h5gg-spin{to{transform:rotate(360deg)}}' +
        '.h5gg-search-status{position:fixed;left:50%;top:14px;transform:translateX(-50%);z-index:120001;padding:7px 12px;border-radius:8px;background:#202020;color:#fff;font-size:12px;box-shadow:0 4px 16px rgba(0,0,0,.3)}' +
        '.result-row{touch-action:manipulation;-webkit-user-select:none;user-select:none;min-height:58px}' +
        '.result-icon-button.active{color:#f5b400!important;background:rgba(245,180,0,.14)!important}' +
        '.result-icon-button[data-result-action="freeze"].active{color:#43a5ff!important;background:rgba(67,165,255,.16)!important}' +
        '#resultActionMask{position:fixed;inset:0;z-index:120002;padding:16px;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px)}' +
        '#resultActionMenu{border:1px solid var(--border-color,rgba(60,60,67,.15));border-radius:16px;overflow:hidden;background:var(--panel-bg,var(--bg-color,#fff));color:var(--text-color,#111);box-shadow:var(--shadow,0 18px 55px rgba(0,0,0,.4))}' +
        '#resultActionMenu .result-action-title{display:block;padding:16px;border-bottom:1px solid var(--border-color,#ddd);font-size:16px}' +
        '#resultActionMenu button{display:block;width:100%;min-height:52px;margin:0;padding:12px 16px;border:0;border-bottom:1px solid var(--border-color,#ddd);background:transparent;color:var(--accent,#007aff);font:inherit;font-size:16px;font-weight:600;text-align:center}' +
        '#resultActionMenu button:last-child{border-bottom:0;color:var(--text-color,#111);font-weight:400}' +
        'select.h5gg-native-select{display:none!important}' +
        '.h5gg-custom-select{min-width:0;position:relative}.h5gg-custom-select.compact-input{width:120px!important}' +
        '.h5gg-select-trigger{display:flex;width:100%;min-height:38px;align-items:center;justify-content:space-between;gap:10px;padding:8px 12px;border:1px solid transparent;border-radius:8px;background:var(--input-bg,rgba(116,116,128,.08));color:var(--text-color,#111);font:inherit;font-size:15px;text-align:left}' +
        '.h5gg-select-trigger:after{content:"⌄";color:var(--text-muted,#777);font-size:16px}.h5gg-select-trigger:focus-visible{border-color:var(--accent,#007aff)}' +
        '#h5ggSelectMask{position:fixed;inset:0;z-index:130020;padding:16px;background:rgba(0,0,0,.52);display:flex;align-items:center;justify-content:center;backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px)}' +
        '#h5ggSelectMenu{width:min(340px,90%);max-height:min(520px,80vh);overflow:auto;border:1px solid var(--border-color,#ddd);border-radius:16px;background:var(--panel-bg,var(--bg-color,#fff));box-shadow:var(--shadow,0 18px 55px rgba(0,0,0,.4))}' +
        '#h5ggSelectMenu .h5gg-select-title{padding:16px;border-bottom:1px solid var(--border-color,#ddd);font-size:16px;font-weight:600;text-align:center}' +
        '#h5ggSelectMenu button{display:block;width:100%;min-height:52px;padding:12px 16px;border:0;border-bottom:1px solid var(--border-color,#ddd);background:transparent;color:var(--text-color,#111);font:inherit;font-size:16px;text-align:left}' +
        '#h5ggSelectMenu button[aria-selected="true"]{color:var(--accent,#007aff);font-weight:700}#h5ggSelectMenu button:last-child{border-bottom:0}' +
        '#h5ggResizeHandle{position:fixed;right:0;bottom:0;width:34px;height:34px;z-index:110000;cursor:nwse-resize;touch-action:none;background:linear-gradient(135deg,transparent 0 45%,rgba(51,147,239,.8) 46% 53%,transparent 54% 62%,rgba(51,147,239,.8) 63% 70%,transparent 71%);border:0}' +
        '.h5gg-api-toolbar{display:flex;gap:4px;align-items:center;margin-bottom:4px}.h5gg-api-toolbar select,.h5gg-api-toolbar .h5gg-custom-select{min-width:0;flex:1}.h5gg-api-docs{display:none;max-height:38%;overflow:auto;padding:6px;margin-bottom:4px;border:1px solid var(--border-color,#ccc);font-size:10px;line-height:1.4}.h5gg-api-docs.open{display:block}' +
        '.memory-line{display:grid;grid-template-columns:minmax(118px,auto) 1fr auto;gap:8px;align-items:center;padding:5px 3px;border-bottom:1px solid var(--border-color,#ddd);cursor:pointer;touch-action:manipulation}.memory-line:active{background:rgba(51,147,239,.14)}' +
        '#memoryContextMask{position:fixed;inset:0;z-index:120002;background:rgba(0,0,0,.5);display:flex;align-items:flex-end;justify-content:center}#memoryContextMenu{width:min(420px,96%);margin-bottom:8px;padding:6px;border-radius:12px;background:var(--bg-color,#fff)}#memoryContextMenu button{display:block;width:100%;min-height:40px;margin:3px 0}';
    style.textContent +=
        '.h5gg-notice-layer{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;padding:18px;background:rgba(0,0,0,.48);backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px)}' +
        '.h5gg-notice-layer[data-ui-toast]{z-index:130000;pointer-events:none}.h5gg-notice-layer[data-ui-alert]{z-index:130010}' +
        '.h5gg-notice-card{width:min(340px,90%);padding:18px;border:1px solid var(--border-color,rgba(255,255,255,.15));border-radius:16px;background:var(--panel-bg,var(--bg-color,#fff));color:var(--text-color,#111);box-shadow:0 18px 55px rgba(0,0,0,.45);text-align:center;font-size:14px;line-height:1.45;white-space:pre-wrap}' +
        '.h5gg-notice-card button{display:block;width:100%;min-height:42px;margin-top:16px;border:0;border-top:1px solid var(--border-color,#ddd);background:transparent;color:var(--accent,#007aff);font:inherit;font-weight:600}';
    document.head.appendChild(style);

    function visible(node) {
        return node && getComputedStyle(node).display !== 'none';
    }

    function closeCustomSelect() {
        var mask = document.getElementById('h5ggSelectMask');
        if(mask) mask.remove();
    }

    function selectLabel(select) {
        var label = select.id && document.querySelector('label[for="' + select.id + '"]');
        if(!label && select.previousElementSibling && select.previousElementSibling.tagName === 'LABEL') {
            label = select.previousElementSibling;
        }
        return select.getAttribute('aria-label') || (label && label.textContent.trim()) || text.choose;
    }

    function syncCustomSelect(select) {
        var wrapper = select.nextElementSibling;
        var trigger = wrapper && wrapper.querySelector('.h5gg-select-trigger');
        var option = select.options[select.selectedIndex];
        if(trigger) {
            trigger.textContent = option ? option.textContent : text.choose;
            trigger.disabled = select.disabled;
        }
    }

    function openCustomSelect(select) {
        closeCustomSelect();
        syncCustomSelect(select);
        var mask = document.createElement('div');
        mask.id = 'h5ggSelectMask';
        var menu = document.createElement('div');
        menu.id = 'h5ggSelectMenu';
        menu.setAttribute('role', 'dialog');
        menu.setAttribute('aria-modal', 'true');
        var title = document.createElement('div');
        title.className = 'h5gg-select-title';
        title.textContent = selectLabel(select);
        menu.appendChild(title);
        Array.from(select.options).forEach(function(option, index) {
            var button = document.createElement('button');
            button.type = 'button';
            button.textContent = option.textContent;
            button.disabled = option.disabled;
            button.setAttribute('aria-selected', String(index === select.selectedIndex));
            button.onclick = function() {
                select.selectedIndex = index;
                select.dispatchEvent(new Event('change', {bubbles:true}));
                syncCustomSelect(select);
                closeCustomSelect();
            };
            menu.appendChild(button);
        });
        mask.appendChild(menu);
        mask.onclick = function(event) { if(event.target === mask) closeCustomSelect(); };
        mask.onkeydown = function(event) { if(event.key === 'Escape') closeCustomSelect(); };
        document.body.appendChild(mask);
        var selected = menu.querySelector('[aria-selected="true"]');
        if(selected) selected.focus();
    }

    function enhanceSelect(select) {
        if(!select || select.dataset.customSelect === 'ready') return;
        select.dataset.customSelect = 'ready';
        select.classList.add('h5gg-native-select');
        var wrapper = document.createElement('div');
        wrapper.className = 'h5gg-custom-select' + (select.classList.contains('compact-input') ? ' compact-input' : '');
        wrapper.dataset.customSelect = 'true';
        ['width','minWidth','maxWidth','flex','margin','marginLeft','marginRight','alignSelf'].forEach(function(property) {
            if(select.style[property]) wrapper.style[property] = select.style[property];
        });
        var trigger = document.createElement('button');
        trigger.type = 'button';
        trigger.className = 'h5gg-select-trigger';
        trigger.setAttribute('aria-haspopup', 'dialog');
        trigger.setAttribute('aria-label', selectLabel(select));
        trigger.onclick = function() { openCustomSelect(select); };
        wrapper.appendChild(trigger);
        select.parentNode.insertBefore(wrapper, select.nextSibling);
        select.addEventListener('change', function() { syncCustomSelect(select); });
        syncCustomSelect(select);
    }

    function installCustomSelects(root) {
        if(root && root.matches && root.matches('select')) enhanceSelect(root);
        if(root && root.querySelectorAll) root.querySelectorAll('select').forEach(enhanceSelect);
    }

    function removeNotice(kind) {
        var notice = document.querySelector('[data-ui-' + kind + ']');
        if(notice) notice.remove();
    }

    window.showToast = function(message) {
        removeNotice('toast');
        var layer = document.createElement('div');
        layer.className = 'h5gg-notice-layer';
        layer.dataset.uiToast = 'true';
        var card = document.createElement('div');
        card.className = 'h5gg-notice-card';
        card.setAttribute('role', 'alert');
        card.textContent = String(message == null ? '' : message);
        layer.appendChild(card);
        document.body.appendChild(layer);
        setTimeout(function() { if(layer.parentNode) layer.remove(); }, 1800);
    };

    window.alert = function(message) {
        removeNotice('alert');
        var layer = document.createElement('div');
        layer.className = 'h5gg-notice-layer';
        layer.dataset.uiAlert = 'true';
        var card = document.createElement('div');
        card.className = 'h5gg-notice-card';
        card.setAttribute('role', 'alertdialog');
        card.setAttribute('aria-modal', 'true');
        var copy = document.createElement('div');
        copy.textContent = String(message == null ? '' : message);
        var close = document.createElement('button');
        close.type = 'button';
        close.textContent = text.okay;
        close.onclick = function() { layer.remove(); };
        card.appendChild(copy);
        card.appendChild(close);
        layer.appendChild(card);
        layer.onclick = function(event) { if(event.target === layer) layer.remove(); };
        document.body.appendChild(layer);
        close.focus();
    };

    function resetTransientUI() {
        ['popup_search_edit', 'popup_progress', 'popup_loadscripts', 'maskview', 'maskview_script'].forEach(function(id) {
            var node = document.getElementById(id);
            if(node) node.style.display = 'none';
        });
        var search = document.getElementById('h5ggSearchProgress');
        if(search) search.remove();
        if(typeof window.dismissResultActions === 'function') window.dismissResultActions();
        if(typeof window.closeResultActions === 'function') window.closeResultActions();
    }

    var legacyOpenSettings = window.openSettings;
    window.openSettings = function() {
        resetTransientUI();
        var existing = document.getElementById('settingsOverlay');
        if(existing) existing.remove();
        return legacyOpenSettings.apply(this, arguments);
    };

    var legacyCloseOverlay = window.closeOverlay;
    window.closeOverlay = function(id) {
        var result = legacyCloseOverlay.apply(this, arguments);
        if(id === 'settingsOverlay') resetTransientUI();
        return result;
    };

    function showSearchProgress() {
        var old = document.getElementById('h5ggSearchProgress');
        if(old) old.remove();
        var overlay = document.createElement('div');
        overlay.id = 'h5ggSearchProgress';
        overlay.dataset.searchProgress = 'active';
        overlay.setAttribute('role', 'status');
        overlay.setAttribute('aria-live', 'polite');
        overlay.setAttribute('aria-busy', 'true');
        overlay.innerHTML = '<div class="card"><div class="spinner"></div><div>' + text.searching + '</div></div>';
        document.body.appendChild(overlay);
    }

    function finishSearchProgress(succeeded, message) {
        var overlay = document.getElementById('h5ggSearchProgress');
        if(overlay) overlay.remove();
        document.querySelectorAll('.h5gg-search-status').forEach(function(node) { node.remove(); });
        var status = document.createElement('div');
        status.className = 'h5gg-search-status';
        status.dataset.searchStatus = succeeded ? 'complete' : 'failed';
        status.setAttribute('role', 'status');
        status.textContent = message || (succeeded ? text.complete : text.failed);
        document.body.appendChild(status);
        setTimeout(function() { if(status.parentNode) status.remove(); }, 2400);
    }

    async function runSearch(operation) {
        showSearchProgress();
        try {
            await operation();
            finishSearchProgress(true);
            return true;
        } catch(error) {
            console.error('H5GG search failed:', error);
            finishSearchProgress(false, text.failed + ': ' + (error && error.message ? error.message : error));
            return false;
        }
    }

    window.showPopView = function(name, action, type, value) {
        var mask = $('#maskview');
        var popup = $('#popup_search_edit');
        mask.css('display', 'flex');
        popup.css('display', 'flex');
        popup.find('#popupTitle, #titleBar').first().html(name);
        popup.find('button#action').html(name);
        if(type) {
            $('table#datatype td').removeClass('selected').each(function() {
                if($(this).text() === type) $(this).addClass('selected');
            });
        }
        popup.find('#datavalue').val(value == null ? '' : value);
        popup.find('button#action').off('click').on('click', async function() {
            var button = this;
            var selectedType = $('table#datatype td.selected').text() || 'I32';
            var selectedValue = popup.find('#datavalue').val();
            button.disabled = true;
            popup.hide();
            try {
                await action(selectedType, selectedValue);
            } finally {
                button.disabled = false;
                if(!visible(document.getElementById('h5ggSearchProgress'))) mask.hide();
            }
        });
        popup.find('button#cancel').off('click').on('click', function() {
            popup.hide();
            mask.hide();
        });
        $('table#datatype td').off('click').on('click', function() {
            $('table#datatype td').removeClass('selected');
            $(this).addClass('selected');
            popup.find('#datavalue').focus();
        });
    };

    window.onClickSearchNumber = function() {
        showPopView(english ? 'Search Number' : '搜索数值', function(type, value) {
            return runSearch(async function() {
                await h5gg.setFloatTolerance($('#float_tolerance').val());
                var from = $('#range_min').val();
                var to = $('#range_max').val();
                await h5gg.searchNumber(value, h5ggType(type), from, to);
                await h5gg.addSearchHistory(value, h5ggType(type), await h5gg.getResultsCount());
                await onClickRefreshResults(true);
            });
        });
    };

    window.onClickSearchNearby = function() {
        showPopView(english ? 'Nearby Search' : '邻近搜索', function(type, value) {
            return runSearch(async function() {
                await h5gg.setFloatTolerance($('#float_tolerance').val());
                await h5gg.searchNearby(value, h5ggType(type), $('#nearby_range').val());
                await onClickRefreshResults(true);
            });
        });
    };

    window.onClickRefreshResults = async function(clean) {
        if(clean) {
            var display = document.getElementById('listdiv');
            if(display) display.scrollTop = 0;
            window.gCurrentCount = 0;
        }
        var count = await h5gg.getResultsCount();
        $('#results_count').text(english ? 'Results Count: ' + count : '共找到' + count + '条结果').show();
        if(window.gCurrentCount === 0) window.gCurrentCount = 100;
        await loadResults(0, window.gCurrentCount);
    };

    window.doHexSearch = function() {
        var value = document.getElementById('hexInput').value.trim();
        if(!value) return;
        return runSearch(async function() {
            await h5gg.searchHex(value, $('#range_min').val(), $('#range_max').val());
            await loadSearchResults();
            await h5gg.addSearchHistory(value, 'Hex', await h5gg.getResultsCount());
        });
    };

    window.refineNumericResults = function() {
        var value = document.getElementById('refineValue').value.trim();
        if(!value) return;
        return runSearch(async function() {
            await h5gg.searchFilter(value, document.getElementById('refineType').value, Number(document.getElementById('refineMode').value));
            await onClickRefreshResults(true);
        });
    };

    function escape(value) {
        return String(value).replace(/[&<>"']/g, function(character) {
            return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character];
        });
    }

    window.renderResults = function(results) {
        var display = document.getElementById('listdiv');
        if(!display) return;
        display.removeAttribute('ontouchend');
        display.setAttribute('onscroll', 'showMoreResults(this)');
        var html = '';
        (results || []).forEach(function(result) {
            var address = escape(result.address);
            var type = escape(result.type);
            var value = escape(result.value);
            html += '<div class="result-row" role="button" tabindex="0" data-addr="'+address+'" data-type="'+type+'" data-value="'+value+'" aria-label="'+value+', '+address+'">';
            html += '<div class="result-address">'+address+' ['+type+']</div><div class="result-value">'+value+'</div>';
            html += '<div class="result-row-actions"><button class="result-icon-button" data-result-action="bookmark" type="button" aria-label="'+text.bookmark+' '+address+'">☆</button>';
            html += '<button class="result-icon-button" data-result-action="freeze" type="button" aria-label="'+text.frozen+' '+address+'">❄</button></div></div>';
        });
        if(!results || results.length === 0) html = '<div class="empty-state">' + (english ? 'No results' : '暂无结果') + '</div>';
        display.innerHTML = html;
        syncResultStates();
    };

    async function syncResultStates() {
        try {
            var values = await Promise.all([h5gg.getBookmarks(), h5gg.getFrozenValues()]);
            var bookmarks = values[0] || [];
            var frozen = values[1] || [];
            document.querySelectorAll('.result-row').forEach(function(row) {
                var bookmarkButton = row.querySelector('[data-result-action="bookmark"]');
                var freezeButton = row.querySelector('[data-result-action="freeze"]');
                if(bookmarks.some(function(item) { return item.address === row.dataset.addr; })) {
                    bookmarkButton.classList.add('active'); bookmarkButton.textContent = '★';
                }
                if(frozen.some(function(item) { return item.address === row.dataset.addr; })) {
                    freezeButton.classList.add('active'); row.classList.add('frozen');
                }
            });
        } catch(error) {
            console.error('Unable to restore result action state:', error);
        }
    }

    async function activateBookmark(button, row) {
        if(button.classList.contains('active')) return;
        var ok = await h5gg.addBookmark(row.dataset.addr, row.dataset.addr, row.dataset.type);
        if(ok !== false) {
            button.classList.add('active');
            button.textContent = '★';
            if(typeof showToast === 'function') showToast(english ? 'Added to bookmarks' : '已添加书签');
        }
    }

    async function activateFreeze(button, row) {
        if(button.classList.contains('active')) return;
        var ok = await h5gg.freezeValue(row.dataset.addr, row.dataset.value, row.dataset.type);
        if(ok) {
            button.classList.add('active');
            row.classList.add('frozen');
            if(typeof showToast === 'function') showToast(english ? 'Value frozen' : '数值已冻结');
        } else if(typeof showToast === 'function') {
            showToast(english ? 'Unable to freeze value' : '无法冻结数值');
        }
    }

    function closeResultActions() {
        var mask = document.getElementById('resultActionMask');
        if(mask) mask.remove();
    }

    function showResultActions(row) {
        closeResultActions();
        var mask = document.createElement('div');
        mask.id = 'resultActionMask';
        mask.innerHTML = '<div id="resultActionMenu" class="modal-card" role="dialog" aria-modal="true" aria-label="'+escape(row.dataset.addr)+'"><b class="result-action-title">'+escape(row.dataset.addr)+'</b>' +
            '<button type="button" data-sheet-action="edit">'+(english ? 'Edit value' : '修改数值')+'</button>' +
            '<button type="button" data-sheet-action="copy-value">'+text.copyValue+'</button>' +
            '<button type="button" data-sheet-action="copy-address">'+text.copyAddressResult+'</button>' +
            '<button type="button" data-sheet-action="bookmark">'+text.bookmark+'</button>' +
            '<button type="button" data-sheet-action="freeze">'+text.frozen+'</button>' +
            '<button type="button" data-sheet-action="cancel">'+text.close+'</button></div>';
        document.body.appendChild(mask);
        mask.addEventListener('click', async function(event) {
            var action = event.target.closest('[data-sheet-action]');
            if(!action) {
                if(event.target === mask) closeResultActions();
                return;
            }
            if(action.dataset.sheetAction === 'edit' && typeof window.openMemoryEditor === 'function') {
                closeResultActions();
                await window.openMemoryEditor(row.dataset.addr, row.dataset.type);
                return;
            }
            if(action.dataset.sheetAction === 'copy-value' || action.dataset.sheetAction === 'copy-address') {
                var copyValue = action.dataset.sheetAction === 'copy-value' ? row.dataset.value : row.dataset.addr;
                var copied = typeof h5gg !== 'undefined' && typeof h5gg.copyText === 'function' ? await h5gg.copyText(copyValue) : false;
                if(typeof showToast === 'function') showToast(copied === false ? text.unavailable : text.copy);
            }
            if(action.dataset.sheetAction === 'bookmark') {
                await activateBookmark(row.querySelector('[data-result-action="bookmark"]'), row);
            }
            if(action.dataset.sheetAction === 'freeze') {
                await activateFreeze(row.querySelector('[data-result-action="freeze"]'), row);
            }
            closeResultActions();
        });
    }

    window.showResultActions = showResultActions;
    window.closeResultActions = closeResultActions;
    window.dismissResultActions = closeResultActions;

    function installResultDelegation() {
        var display = document.getElementById('listdiv');
        if(!display || display.dataset.resultDelegation === 'ready') return;
        display.dataset.resultDelegation = 'ready';
        display.addEventListener('click', async function(event) {
            var row = event.target.closest('.result-row');
            if(!row) return;
            var action = event.target.closest('[data-result-action]');
            if(action) {
                event.preventDefault();
                event.stopPropagation();
                action.disabled = true;
                try {
                    if(action.dataset.resultAction === 'bookmark') await activateBookmark(action, row);
                    else await activateFreeze(action, row);
                } finally {
                    action.disabled = false;
                }
                return;
            }
            showResultActions(row);
        });
        display.addEventListener('keydown', function(event) {
            if(event.key !== 'Enter' && event.key !== ' ') return;
            var row = event.target.closest('.result-row');
            if(!row) return;
            event.preventDefault();
            showResultActions(row);
        });
    }

    window.onClickLoadScript = async function(source, type) {
        if(!source) return false;
        var isRemote = /^https?:\/\//i.test(source);
        var isJavaScript = type === 'js' || (!type && /\.js(?:$|[?#])/i.test(source));
        $('#popup_progress').show().find('center').text(text.scriptRunning);
        $('#maskview_script').show();
        try {
            if(isRemote) {
                if(!isJavaScript) {
                    location.href = source;
                    return true;
                }
                await new Promise(function(resolve, reject) {
                    var script = document.createElement('script');
                    script.onload = resolve;
                    script.onerror = function() { reject(new Error(text.scriptFailed)); };
                    script.src = source;
                    document.body.appendChild(script);
                });
            } else {
                if(typeof h5gg === 'undefined' || typeof h5gg.loadScript !== 'function') throw new Error(text.scriptFailed);
                var content = await h5gg.loadScript(source);
                if(content == null) {
                    var detail = typeof h5gg.getLastFileError === 'function' ? await h5gg.getLastFileError() : null;
                    throw new Error(detail || text.scriptFailed);
                }
                if(isJavaScript) {
                    if(typeof runScript === 'function') {
                        if(runScript(content, source) === false) throw new Error(text.scriptFailed);
                    } else {
                        (0, eval)(content);
                    }
                } else {
                    document.open();
                    document.write(content);
                    document.close();
                    return true;
                }
            }
            if(typeof showToast === 'function') showToast(text.scriptComplete);
            return true;
        } catch(error) {
            console.error('Script load failed:', error);
            if(typeof showToast === 'function') showToast(error.message || text.scriptFailed);
            return false;
        } finally {
            $('#popup_progress').hide();
            $('#maskview_script').hide();
            $('#popup_loadscripts').hide();
            $('#maskview').hide();
        }
    };

    var apiMethods = [
        {signature:'h5gg.searchNumber(value, type, from, to)', insert:'await h5gg.searchNumber("42", "I32", "0x0", "0xFFFFFFFF");', description:'Search memory for a typed value.'},
        {signature:'h5gg.searchNearby(value, type, range)', insert:'await h5gg.searchNearby("42", "I32", "0x100");', description:'Refine around current results.'},
        {signature:'h5gg.getResults(count, skip)', insert:'const results = await h5gg.getResults(100, 0);', description:'Read a page of search results.'},
        {signature:'h5gg.getValue(address, type)', insert:'const value = await h5gg.getValue("0x100000000", "I32");', description:'Read a typed value.'},
        {signature:'h5gg.setValue(address, value, type)', insert:'await h5gg.setValue("0x100000000", "42", "I32");', description:'Write a typed value.'},
        {signature:'h5gg.getRangesList(filter)', insert:'const ranges = await h5gg.getRangesList("0");', description:'List loaded executable ranges; "0" selects the main binary.'},
        {signature:'h5gg.searchHex(pattern, from, to)', insert:'await h5gg.searchHex("90 ?? E? AF", "0x0", "0xFFFFFFFF");', description:'Search for bytes with wildcard nibbles.'},
        {signature:'h5gg.freezeValue(address, value, type)', insert:'await h5gg.freezeValue("0x100000000", "42", "I32");', description:'Keep a value frozen.'},
        {signature:'h5gg.readMemoryPage(address, length)', insert:'const page = await h5gg.readMemoryPage("0x100000000", 256);', description:'Read raw memory with unreadable-byte markers.'},
        {signature:'h5gg.copyText(text)', insert:'await h5gg.copyText("text");', description:'Copy text to the system clipboard.'},
        {signature:'h5gg.editAll(value, type)', insert:'const changed = await h5gg.editAll("0", "I32");', description:'Write one value to every current result.'},
        {signature:'h5gg.getResultsCount()', insert:'const count = await h5gg.getResultsCount();', description:'Return the current result count.'},
        {signature:'h5gg.clearResults()', insert:'await h5gg.clearResults();', description:'Clear the current search session.'},
        {signature:'h5gg.getLocalScripts()', insert:'const scripts = await h5gg.getLocalScripts();', description:'List JavaScript and HTML files available locally.'},
        {signature:'h5gg.pickScriptFile(types)', insert:'const path = await h5gg.pickScriptFile(["public.data"]);', description:'Open the native document picker.'},
        {signature:'h5gg.getProcList(filter)', insert:'const processes = await h5gg.getProcList();', description:'List targetable application processes.'},
        {signature:'h5gg.setTargetProc(pid)', insert:'const selected = await h5gg.setTargetProc(pid);', description:'Select a process as the memory target.'},
        {signature:'h5gg.getTargetStatus()', insert:'const status = await h5gg.getTargetStatus();', description:'Read availability of the selected target.'},
        {signature:'h5gg.loadPlugin(className, path)', insert:'const plugin = await h5gg.loadPlugin("PluginClass", dylibPath);', description:'Load a native plugin.'},
        {signature:'h5gg.callPlugin(id, method, arguments)', insert:'const result = await h5gg.callPlugin(pluginId, "method", []);', description:'Invoke an allowlisted native plugin method.'},
        {signature:'h5gg.getPluginCapabilities()', insert:'const capabilities = await h5gg.getPluginCapabilities();', description:'Inspect plugin bridge capabilities.'},
        {signature:'h5gg.makeTweak(icon, html)', insert:'const result = await h5gg.makeTweak(iconPath, htmlPath);', description:'Generate a custom tweak from an icon and HTML file.'},
        {signature:'h5gg.require(minVersion)', insert:'if (!await h5gg.require(8.0)) return;', description:'Require a minimum H5GG runtime version.'},
        {signature:'h5gg.setFloatTolerance(value)', insert:'await h5gg.setFloatTolerance("0.01");', description:'Set tolerance for floating-point searches.'},
        {signature:'h5gg.searchChange(change)', insert:'await h5gg.searchChange("Changed");', description:'Refine by Changed, Unchanged, Increased, or Decreased.'},
        {signature:'h5gg.searchFilter(value, type, mode)', insert:'const kept = await h5gg.searchFilter("100", "I32", 2);', description:'Refine results with equal, greater, or less comparison.'},
        {signature:'h5gg.getInputHistory()', insert:'const history = await h5gg.getInputHistory();', description:'Read persisted input history.'},
        {signature:'h5gg.addInputHistory(value)', insert:'await h5gg.addInputHistory("42");', description:'Add a value to input history.'},
        {signature:'h5gg.clearInputHistory()', insert:'await h5gg.clearInputHistory();', description:'Clear persisted input history.'},
        {signature:'h5gg.addBookmark(address, name, type)', insert:'await h5gg.addBookmark(address, "Bookmark", "I32");', description:'Persist a memory-address bookmark.'},
        {signature:'h5gg.removeBookmark(address)', insert:'await h5gg.removeBookmark(address);', description:'Remove a bookmark by address.'},
        {signature:'h5gg.getBookmarks()', insert:'const bookmarks = await h5gg.getBookmarks();', description:'Read all persisted bookmarks.'},
        {signature:'h5gg.clearBookmarks()', insert:'await h5gg.clearBookmarks();', description:'Remove every bookmark.'},
        {signature:'h5gg.unfreezeValue(address)', insert:'await h5gg.unfreezeValue(address);', description:'Stop freezing one address.'},
        {signature:'h5gg.getFrozenValues()', insert:'const frozen = await h5gg.getFrozenValues();', description:'Read the frozen-value status list.'},
        {signature:'h5gg.clearFrozenValues()', insert:'await h5gg.clearFrozenValues();', description:'Stop and clear all frozen values.'},
        {signature:'h5gg.getSearchHistory()', insert:'const searches = await h5gg.getSearchHistory();', description:'Read persisted search history.'},
        {signature:'h5gg.addSearchHistory(value, type, count)', insert:'await h5gg.addSearchHistory("42", "I32", count);', description:'Add an entry to search history.'},
        {signature:'h5gg.clearSearchHistory()', insert:'await h5gg.clearSearchHistory();', description:'Clear persisted search history.'},
        {signature:'h5gg.dumpMemory(start, end, filename)', insert:'const saved = await h5gg.dumpMemory(start, end, "dump.bin");', description:'Dump a memory range to a file.'},
        {signature:'h5gg.getDumpStatus()', insert:'const dumpStatus = await h5gg.getDumpStatus();', description:'Read progress of the active dump.'},
        {signature:'h5gg.cancelDump()', insert:'await h5gg.cancelDump();', description:'Cancel the active memory dump.'},
        {signature:'h5gg.readPointer(address)', insert:'const pointer = await h5gg.readPointer(address);', description:'Read one 64-bit pointer.'},
        {signature:'h5gg.findPointers(address, rangeStart, rangeEnd)', insert:'const pointers = await h5gg.findPointers(address, rangeStart, rangeEnd);', description:'Find exact pointers to an address.'},
        {signature:'h5gg.getPointerCapabilities()', insert:'const pointerInfo = await h5gg.getPointerCapabilities();', description:'Inspect pointer-search limits.'},
        {signature:'h5gg.appendLog(message)', insert:'await h5gg.appendLog("message");', description:'Append text to the native log.'},
        {signature:'h5gg.readBytes(address, length)', insert:'const hex = await h5gg.readBytes(address, 16);', description:'Read raw bytes as hexadecimal text.'},
        {signature:'h5gg.saveScript(name, content)', insert:'await h5gg.saveScript("script.js", code);', description:'Save a script explicitly.'},
        {signature:'h5gg.loadScript(name)', insert:'const code = await h5gg.loadScript("script.js");', description:'Load a stored script or approved local path.'},
        {signature:'h5gg.deleteScript(name)', insert:'await h5gg.deleteScript("script.js");', description:'Delete a stored script.'},
        {signature:'h5gg.listScripts()', insert:'const names = await h5gg.listScripts();', description:'List stored script names.'},
        {signature:'h5gg.getLastFileError()', insert:'const fileError = await h5gg.getLastFileError();', description:'Read the last script-store error.'}
    ];

    var legacyOpenScriptEditor = window.openScriptEditor;
    window.openScriptEditor = async function() {
        var result = await legacyOpenScriptEditor.apply(this, arguments);
        enhanceScriptEditor();
        return result;
    };

    function enhanceScriptEditor() {
        var editor = document.getElementById('scriptEditor');
        if(!editor || document.querySelector('.h5gg-api-toolbar')) return;
        var toolbar = document.createElement('div');
        toolbar.className = 'h5gg-api-toolbar';
        toolbar.innerHTML = '<button type="button" data-api-docs>'+text.apiDocs+'</button><select id="h5ggApiMethod" aria-label="'+text.apiDocs+'"></select><button type="button" data-api-insert>'+text.insertCall+'</button>';
        var select = toolbar.querySelector('select');
        apiMethods.forEach(function(method, index) {
            var option = document.createElement('option');
            option.value = String(index);
            option.textContent = method.signature;
            select.appendChild(option);
        });
        var docs = document.createElement('div');
        docs.className = 'h5gg-api-docs';
        docs.innerHTML = apiMethods.map(function(method) { return '<div><b>'+escape(method.signature)+'</b><br>'+escape(method.description)+'</div>'; }).join('<hr>');
        editor.parentNode.insertBefore(toolbar, editor);
        editor.parentNode.insertBefore(docs, editor);
        toolbar.querySelector('[data-api-docs]').addEventListener('click', function() { docs.classList.toggle('open'); });
        toolbar.querySelector('[data-api-insert]').addEventListener('click', function() {
            var snippet = apiMethods[Number(select.value) || 0].insert;
            var start = editor.selectionStart == null ? editor.value.length : editor.selectionStart;
            var end = editor.selectionEnd == null ? start : editor.selectionEnd;
            editor.setRangeText(snippet, start, end, 'end');
            editor.focus();
        });
    }

    var binaryBaseAddress = null;
    async function getBinaryBaseAddress(refresh) {
        if(binaryBaseAddress && !refresh) return binaryBaseAddress;
        if(typeof h5gg === 'undefined' || typeof h5gg.getRangesList !== 'function') return null;
        var ranges = await h5gg.getRangesList('0');
        if(ranges && ranges.length && ranges[0].start) binaryBaseAddress = ranges[0].start;
        return binaryBaseAddress;
    }
    window.getBinaryBaseAddress = getBinaryBaseAddress;

    window.showBaseAddress = async function() {
        var address = await getBinaryBaseAddress(true);
        var existing = document.getElementById('baseAddressOverlay');
        if(existing) existing.remove();
        var overlay = document.createElement('div');
        overlay.id = 'baseAddressOverlay';
        overlay.style.cssText = 'position:fixed;inset:0;z-index:120000;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center';
        overlay.innerHTML = '<div style="width:min(360px,88%);padding:14px;border-radius:10px;background:var(--bg-color,#fff);color:var(--text-color,#111);text-align:center"><b>'+text.baseAddress+'</b><div data-base-address-value style="font-family:monospace;margin:14px 0;font-size:15px">'+escape(address || text.unavailable)+'</div><button data-copy-base type="button">'+text.copy+'</button> <button data-close-base type="button">'+text.close+'</button></div>';
        document.body.appendChild(overlay);
        overlay.querySelector('[data-close-base]').onclick = function() { overlay.remove(); };
        overlay.querySelector('[data-copy-base]').onclick = async function() { if(address) await h5gg.copyText(address); };
        overlay.onclick = function(event) { if(event.target === overlay) overlay.remove(); };
    };

    function installBaseButton() {
        if(document.querySelector('[data-base-address-button]')) return;
        var settings = Array.from(document.querySelectorAll('button')).find(function(button) { return /Settings|设置/.test(button.textContent); });
        var container = settings && settings.parentNode;
        if(!container) return;
        var button = document.createElement('button');
        button.type = 'button';
        button.dataset.baseAddressButton = 'true';
        button.textContent = text.baseAddress;
        button.addEventListener('click', showBaseAddress);
        container.insertBefore(button, settings);
    }

    var viewerBytes = [];
    window.openMemoryViewer = async function() {
        var existing = document.getElementById('viewerOverlay');
        if(existing) existing.remove();
        var base = await getBinaryBaseAddress();
        if(base) window.gViewerAddr = base;
        var html = '<div id="viewerOverlay" style="position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:119999" onclick="closeOverlay(\'viewerOverlay\')">';
        html += '<div style="position:absolute;top:5%;left:3%;width:94%;height:90%;background:var(--bg-color,#fff);border-radius:8px;overflow:hidden;display:flex;flex-direction:column" onclick="event.stopPropagation()">';
        html += '<div style="padding:8px;font-size:14px;font-weight:bold;border-bottom:1px solid var(--border-color,#ccc);display:flex;justify-content:space-between"><span>'+text.viewer+'</span><button type="button" onclick="closeOverlay(\'viewerOverlay\')">×</button></div>';
        html += '<div style="display:flex;padding:6px;gap:4px"><label for="viewerAddr">'+text.address+'</label><input id="viewerAddr" value="'+escape(window.gViewerAddr || '0x0')+'" style="min-width:0;flex:1;font-family:monospace"><button type="button" onclick="viewerGo()">'+text.go+'</button></div>';
        html += '<div style="display:flex;padding:2px 6px"><button onclick="viewerPage(-1)" style="flex:1">-Page</button><button onclick="viewerStep(-16)" style="flex:1">-16</button><button onclick="viewerStep(16)" style="flex:1">+16</button><button onclick="viewerPage(1)" style="flex:1">+Page</button></div>';
        html += '<div id="viewerDump" class="scrollbar" style="flex:1;overflow:auto;padding:6px;font-family:monospace;font-size:10px"></div></div></div>';
        document.body.insertAdjacentHTML('beforeend', html);
        await viewerGo();
    };

    window.viewerRefresh = async function() {
        var dump = document.getElementById('viewerDump');
        if(!dump || !window.gViewerAddr) return;
        var address = BigInt(window.gViewerAddr);
        var page = await h5gg.readMemoryPage(window.gViewerAddr, 256);
        if(!page || page.error) { dump.textContent = english ? 'Failed to read memory' : '读取内存失败'; return; }
        viewerBytes = page.bytes || [];
        dump.innerHTML = '';
        for(var line = 0; line < viewerBytes.length; line += 16) {
            var lineAddress = '0x' + (address + BigInt(line)).toString(16).toUpperCase();
            var values = viewerBytes.slice(line, line + 16);
            var row = document.createElement('div');
            row.className = 'memory-line';
            row.tabIndex = 0;
            row.dataset.memoryAddress = lineAddress;
            row.dataset.memoryOffset = String(line);
            var hex = values.map(function(value) { return value == null ? '??' : Number(value).toString(16).toUpperCase().padStart(2, '0'); }).join(' ');
            var ascii = values.map(function(value) { return value >= 32 && value <= 126 ? String.fromCharCode(value) : '.'; }).join('');
            row.innerHTML = '<span>'+lineAddress+'</span><span>'+hex+'</span><span>|'+escape(ascii)+'|</span>';
            row.addEventListener('click', function() { openMemoryContext(this); });
            row.addEventListener('keydown', function(event) { if(event.key === 'Enter' || event.key === ' ') openMemoryContext(this); });
            dump.appendChild(row);
        }
    };

    function openMemoryContext(row) {
        var old = document.getElementById('memoryContextMask');
        if(old) old.remove();
        var offset = Number(row.dataset.memoryOffset);
        var bytes = viewerBytes.slice(offset, offset + 8);
        var value = bytes.map(function(byte) { return byte == null ? '??' : Number(byte).toString(16).toUpperCase().padStart(2, '0'); }).join(' ');
        var mask = document.createElement('div');
        mask.id = 'memoryContextMask';
        mask.dataset.memoryContext = 'true';
        mask.innerHTML = '<div id="memoryContextMenu"><b style="display:block;padding:8px">'+escape(row.dataset.memoryAddress)+'</b><button data-memory-action="copy-address">'+text.copyAddress+'</button><button data-memory-action="copy-8-bytes">'+text.copyBytes+'</button><button data-memory-action="dump-start">'+text.dumpStart+'</button><button data-memory-action="dump-end">'+text.dumpEnd+'</button><button data-memory-action="cancel">'+text.close+'</button></div>';
        document.body.appendChild(mask);
        mask.onclick = async function(event) {
            var button = event.target.closest('[data-memory-action]');
            if(!button) { if(event.target === mask) mask.remove(); return; }
            var action = button.dataset.memoryAction;
            if(action === 'copy-address') await h5gg.copyText(row.dataset.memoryAddress);
            if(action === 'copy-8-bytes') await h5gg.copyText(value);
            if(action === 'dump-start' || action === 'dump-end') {
                mask.remove();
                if(!document.getElementById('dumpOverlay')) await openDumpPanel();
                var input = document.getElementById(action === 'dump-start' ? 'dumpStart' : 'dumpEnd');
                if(input) input.value = row.dataset.memoryAddress;
                return;
            }
            mask.remove();
        };
    }

    var hostLayout = {width:0, height:0};

    function readWindowSize() {
        var parsed;
        try { parsed = JSON.parse(localStorage.getItem('h5gg_window_size')); } catch(_) {}
        var width = Number(parsed && (parsed.width || parsed.w));
        var height = Number(parsed && (parsed.height || parsed.h));
        return {
            width: width > 0 ? width : Math.min(400, innerWidth || 400),
            height: height > 0 ? height : Math.min(600, innerHeight || 600)
        };
    }

    function saveWindowSize(width, height) {
        var size = {width:Math.round(width), height:Math.round(height)};
        localStorage.setItem('h5gg_window_size', JSON.stringify(size));
        return size;
    }

    window.h5gg_onLayoutChange = function(screenWidth, screenHeight) {
        hostLayout.width = Number(screenWidth) || innerWidth || 400;
        hostLayout.height = Number(screenHeight) || innerHeight || 600;
        var current = readWindowSize();
        var width = Math.max(300, Math.min(current.width, hostLayout.width));
        var height = Math.max(360, Math.min(current.height, hostLayout.height));
        var saved = saveWindowSize(width, height);
        if(typeof setWindowRect === 'function') {
            setWindowRect(Math.max(0, Math.round((hostLayout.width-saved.width)/2)), Math.max(0, Math.round((hostLayout.height-saved.height)/2)), saved.width, saved.height);
        }
    };

    function installResizeHandle() {
        if(document.getElementById('h5ggResizeHandle')) return;
        var handle = document.createElement('button');
        handle.id = 'h5ggResizeHandle';
        handle.type = 'button';
        handle.dataset.windowResize = 'true';
        handle.setAttribute('aria-label', english ? 'Resize H5GG window' : '调整 H5GG 窗口大小');
        document.body.appendChild(handle);
        var saved = readWindowSize();
        saveWindowSize(saved.width, saved.height);
        if(typeof setLayoutAction === 'function') {
            setLayoutAction();
        }
        var drag = null;
        handle.addEventListener('pointerdown', function(event) {
            var current = readWindowSize();
            drag = {x:event.clientX, y:event.clientY, width:Number(current.width), height:Number(current.height)};
            handle.setPointerCapture(event.pointerId);
            event.preventDefault();
        });
        handle.addEventListener('pointermove', function(event) {
            if(!drag) return;
            var maxWidth = hostLayout.width || Number.MAX_SAFE_INTEGER;
            var maxHeight = hostLayout.height || Number.MAX_SAFE_INTEGER;
            var width = Math.max(300, Math.min(drag.width + event.clientX - drag.x, maxWidth));
            var height = Math.max(360, Math.min(drag.height + event.clientY - drag.y, maxHeight));
            setWindowRect(-1, -1, Math.round(width), Math.round(height));
            saveWindowSize(width, height);
        });
        handle.addEventListener('pointerup', function() { drag = null; });
        handle.addEventListener('pointercancel', function() { drag = null; });
        handle.addEventListener('keydown', function(event) {
            if(!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key)) return;
            var current = readWindowSize();
            if(event.key === 'ArrowLeft') current.width = Math.max(320, current.width - 10);
            if(event.key === 'ArrowRight') current.width += 10;
            if(event.key === 'ArrowUp') current.height = Math.max(360, current.height - 10);
            if(event.key === 'ArrowDown') current.height += 10;
            var saved = saveWindowSize(current.width, current.height);
            setWindowRect(-1, -1, saved.width, saved.height);
            event.preventDefault();
        });
    }

    window.installResizeHandle = installResizeHandle;
    window.toggleResizeHandle = function() {
        var handle = document.getElementById('h5ggResizeHandle');
        if(handle) {
            handle.remove();
            showToast(english ? 'Window resizing disabled' : '已关闭窗口大小调整');
        } else {
            installResizeHandle();
            showToast(english ? 'Drag the bottom-right corner to resize' : '拖动右下角调整窗口大小');
        }
    };

    document.addEventListener('DOMContentLoaded', function() {
        installCustomSelects(document);
        new MutationObserver(function(records) {
            records.forEach(function(record) {
                record.addedNodes.forEach(function(node) { installCustomSelects(node); });
            });
        }).observe(document.body, {childList:true, subtree:true});
        installResultDelegation();
        installBaseButton();
        installResizeHandle();
    });
})();
