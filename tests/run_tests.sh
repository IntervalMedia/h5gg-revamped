#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-memory-results.XXXXXX")"
bridge_docs_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-bridge-docs.XXXXXX")"
plugin_test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-plugin-loader.XXXXXX")"
gv_protocol_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-gv-protocol.XXXXXX")"
runtime_test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-runtime-coordinator.XXXXXX")"
freezer_test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-freezer-controller.XXXXXX")"
picker_test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-file-picker-request.XXXXXX")"
preferences_test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-preferences-store.XXXXXX")"
dump_test_output="$(mktemp "${TMPDIR:-/tmp}/h5gg-dump-controller.XXXXXX")"
trap 'rm -f "$test_output" "$bridge_docs_output" "$plugin_test_output" "$gv_protocol_output" "$runtime_test_output" "$freezer_test_output" "$picker_test_output" "$preferences_test_output" "$dump_test_output"' EXIT

"${CXX:-c++}" \
  -std=c++17 \
  -Wall \
  -Wextra \
  -Werror \
  "$repo_root/tests/MemoryResultsTests.cpp" \
  "$repo_root/MemoryResults.cpp" \
  "$repo_root/MemoryValue.cpp" \
  "$repo_root/MemoryReader.cpp" \
  "$repo_root/PointerSearch.cpp" \
  "$repo_root/BridgeMethods.cpp" \
  "$repo_root/FileNames.cpp" \
  "$repo_root/MemoryFilter.cpp" \
  "$repo_root/MemoryPage.cpp" \
  "$repo_root/MemoryDump.cpp" \
  "$repo_root/DylibTemplate.cpp" \
  "$repo_root/DylibBuilder.cpp" \
  "$repo_root/TextEncoding.cpp" \
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
  "$repo_root/tests/GVProtocolTests.cpp" \
  "$repo_root/globalview/GVProtocol.cpp" \
  -o "$gv_protocol_output"
"$gv_protocol_output"
"${CXX:-c++}" \
  -std=c++17 \
  -Wall \
  -Wextra \
  -Werror \
  "$repo_root/tests/BridgeSchemaDocs.cpp" \
  "$repo_root/BridgeMethods.cpp" \
  -o "$bridge_docs_output"
"$bridge_docs_output" "$repo_root/docs/javascript-api.md"
if [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]] ||
   [[ -x "/Applications/Chromium.app/Contents/MacOS/Chromium" ]] ||
   command -v google-chrome >/dev/null 2>&1 ||
   command -v chromium >/dev/null 2>&1; then
  bash "$repo_root/tests/run_ui_bug_repros.sh"
else
  echo "Skipping UI browser regressions: Chrome/Chromium not installed"
fi
if command -v xcrun >/dev/null 2>&1 &&
   xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  xcrun --sdk macosx clang \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -Werror \
    "$repo_root/tests/RuntimeCoordinatorTests.m" \
    "$repo_root/RuntimeCoordinator.m" \
    -framework Foundation \
    -o "$runtime_test_output"
  "$runtime_test_output"
  xcrun --sdk macosx clang++ \
    -std=c++17 \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -Werror \
    "$repo_root/tests/FreezerControllerTests.mm" \
    "$repo_root/FreezerController.mm" \
    "$repo_root/MemoryValue.cpp" \
    -framework Foundation \
    -o "$freezer_test_output"
  "$freezer_test_output"
  xcrun --sdk macosx clang \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -Werror \
    "$repo_root/tests/FilePickerRequestTests.m" \
    "$repo_root/FilePickerRequest.m" \
    -framework Foundation \
    -o "$picker_test_output"
  "$picker_test_output"
  xcrun --sdk macosx clang \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -Werror \
    "$repo_root/tests/PreferencesStoreTests.m" \
    "$repo_root/PreferencesStore.m" \
    -framework Foundation \
    -o "$preferences_test_output"
  "$preferences_test_output"
  xcrun --sdk macosx clang++ \
    -std=c++17 \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -Werror \
    "$repo_root/tests/DumpControllerTests.mm" \
    "$repo_root/DumpController.mm" \
    "$repo_root/MemoryDump.cpp" \
    "$repo_root/MemoryReader.cpp" \
    "$repo_root/MemoryValue.cpp" \
    "$repo_root/FileNames.cpp" \
    -framework Foundation \
    -o "$dump_test_output"
  "$dump_test_output"
  xcrun --sdk macosx clang \
    -fobjc-arc \
    -fblocks \
    -Wall \
    -Wextra \
    -Werror \
    "$repo_root/tests/PluginLoaderTests.m" \
    "$repo_root/PluginLoader.m" \
    -framework Foundation \
    -o "$plugin_test_output"
  "$plugin_test_output"
else
  echo "Skipping Foundation contract tests because the macOS SDK is unavailable"
fi
node "$repo_root/tests/ResultActionsTests.js"
node "$repo_root/tests/ModalHierarchyTests.js"
node "$repo_root/tests/WindowActionDispatchTests.js"
node --check "$repo_root/examples-JavaScript/h5ggV8/phase2DeviceValidation.js"
node "$repo_root/tests/Phase2DeviceValidationTests.js"
node "$repo_root/tests/check_javascript_api_docs.js"
bash "$repo_root/tests/check_build_variants.sh"
bash "$repo_root/tests/check_deployment_baseline.sh"
bash "$repo_root/tests/check_dylib_generation.sh"
