#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chrome_binary="${H5GG_CHROME_BINARY:-}"

if [[ -z "$chrome_binary" ]]; then
    for candidate in \
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
        "/Applications/Chromium.app/Contents/MacOS/Chromium" \
        "$(command -v google-chrome 2>/dev/null || true)" \
        "$(command -v chromium 2>/dev/null || true)"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            chrome_binary="$candidate"
            break
        fi
    done
fi

if [[ -z "$chrome_binary" || ! -x "$chrome_binary" ]]; then
    echo "Chrome or Chromium is required for UI regression tests." >&2
    exit 1
fi

profile_dir="$(mktemp -d "${TMPDIR:-/tmp}/h5gg-ui-chrome.XXXXXX")"
chrome_log="$(mktemp "${TMPDIR:-/tmp}/h5gg-ui-chrome.XXXXXX.log")"
chrome_pid=""

cleanup() {
    if [[ -n "$chrome_pid" ]]; then
        kill "$chrome_pid" 2>/dev/null || true
        wait "$chrome_pid" 2>/dev/null || true
    fi
    rm -rf "$profile_dir"
    rm -f "$chrome_log"
}
trap cleanup EXIT

"$chrome_binary" \
    --headless=new \
    --remote-debugging-port=0 \
    --remote-allow-origins='*' \
    --user-data-dir="$profile_dir" \
    --no-first-run \
    --no-default-browser-check \
    about:blank >"$chrome_log" 2>&1 &
chrome_pid=$!

for _ in {1..100}; do
    if [[ -s "$profile_dir/DevToolsActivePort" ]]; then
        break
    fi
    if ! kill -0 "$chrome_pid" 2>/dev/null; then
        cat "$chrome_log" >&2
        exit 1
    fi
    sleep 0.05
done

if [[ ! -s "$profile_dir/DevToolsActivePort" ]]; then
    cat "$chrome_log" >&2
    echo "Chrome did not expose a DevTools port." >&2
    exit 1
fi

port="$(sed -n '1p' "$profile_dir/DevToolsActivePort")"
H5GG_CDP_HTTP="http://127.0.0.1:$port" node "$repo_root/tests/UIBugReproTests.js"
