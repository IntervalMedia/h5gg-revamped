#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-memory-results.XXXXXX")"
trap 'rm -f "$test_output"' EXIT

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
  -o "$test_output"

"$test_output"
node "$repo_root/tests/ResultActionsTests.js"
node "$repo_root/tests/check_javascript_api_docs.js"
bash "$repo_root/tests/check_build_variants.sh"
bash "$repo_root/tests/check_dylib_generation.sh"
