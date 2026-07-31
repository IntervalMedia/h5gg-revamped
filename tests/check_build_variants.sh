#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${THEOS:-}" ]; then
  echo "Skipping build-variant checks because THEOS is not configured"
  exit 0
fi

check_variant() {
  local variant="$1"
  local expected="$2"
  local output

  if [ "$variant" = "normal" ]; then
    output="$(make -Bn -C "$repo_root" 2>&1)"
  else
    output="$(make -Bn -C "$repo_root" "THEOS_PACKAGE_SCHEME=$variant" 2>&1)"
  fi

  local definitions
  definitions="$(printf '%s\n' "$output" |
    grep -o -- '-DH5GG_BUILD_[A-Z]*=1' |
    sort -u || true)"

  if [ "$definitions" != "-D${expected}=1" ]; then
    echo "$variant emitted unexpected H5GG build definitions:" >&2
    printf '%s\n' "${definitions:-<none>}" >&2
    return 1
  fi
}

check_variant normal H5GG_BUILD_NORMAL
check_variant rootless H5GG_BUILD_ROOTLESS
check_variant roothide H5GG_BUILD_ROOTHIDE
