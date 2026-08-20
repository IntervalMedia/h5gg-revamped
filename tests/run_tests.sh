#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-memory-results.XXXXXX")"
bridge_docs_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-bridge-docs.XXXXXX")"
trap 'rm -f "$test_output" "$bridge_docs_output"' EXIT

"${CXX:-c++}" \
  -std=c++17 \
  -Wall \
  -Wextra \
  -Werror \
  "$repo_root/tests/MemoryResultsTests.cpp" \
  "$repo_root/MemoryResults.cpp" \
  "$repo_root/MemoryValue.cpp" \
  "$repo_root/BridgeMethods.cpp" \
  "$repo_root/FileNames.cpp" \
  "$repo_root/MemoryFilter.cpp" \
  "$repo_root/MemoryPage.cpp" \
  "$repo_root/MemoryDump.cpp" \
  "$repo_root/DylibTemplate.cpp" \
  "$repo_root/TargetSession.cpp" \
  "$repo_root/ModalRequestQueue.cpp" \
  "$repo_root/ScriptStore.cpp" \
  -o "$test_output"

"$test_output"
"${CXX:-c++}" \
  -std=c++17 \
  -Wall \
  -Wextra \
  -Werror \
  "$repo_root/tests/BridgeSchemaDocs.cpp" \
  "$repo_root/BridgeMethods.cpp" \
  -o "$bridge_docs_output"
"$bridge_docs_output" "$repo_root/docs/javascript-api.md"
node "$repo_root/tests/ResultActionsTests.js"
node "$repo_root/tests/check_javascript_api_docs.js"
bash "$repo_root/tests/check_build_variants.sh"
bash "$repo_root/tests/check_dylib_generation.sh"
