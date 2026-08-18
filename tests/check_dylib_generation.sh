#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input="$repo_root/.theos/obj/H5GG.dylib"
if [ ! -f "$input" ]; then
  echo "Skipping dylib-generation integration check until H5GG.dylib is built"
  exit 0
fi
if ! command -v ldid >/dev/null 2>&1; then
  echo "Skipping dylib signing check because ldid is unavailable"
  exit 0
fi

tool="$(mktemp "${TMPDIR:-/tmp}/h5gg-dylib-tool.XXXXXX")"
output="$(mktemp "${TMPDIR:-/tmp}/h5gg-custom.XXXXXX.dylib")"
trap 'rm -f "$tool" "$output"' EXIT

"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror \
  "$repo_root/tests/DylibGenerationIntegration.cpp" \
  "$repo_root/DylibTemplate.cpp" \
  -o "$tool"

"$tool" \
  "$input" \
  "$repo_root/H5ICON_STUB_FILE" \
  "$repo_root/H5MENU_STUB_FILE" \
  "$repo_root/icon.png" \
  "$repo_root/Index-en.html" \
  "$output"

ldid -S "$output"
ldid -e "$output" >/dev/null
file "$output" | grep -q 'Mach-O universal binary'
