#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for lifecycle_target in all stage package; do
  if ! grep -Eq "^\\.NOTPARALLEL:.*[[:space:]]${lifecycle_target}([[:space:]]|$)" "$repo_root/Makefile"; then
    echo "Theos lifecycle target '$lifecycle_target' must be serialized for parallel MAKEFLAGS" >&2
    exit 1
  fi
done

if [ -z "${THEOS:-}" ]; then
  echo "Skipping build-variant checks because THEOS is not configured"
  exit 0
fi

check_variant() {
  local variant="$1"
  local expected="$2"
  local expected_sdk="$3"
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

  local missing_definition
  missing_definition="$(grep -E '/clang(\+\+)? .* -c ' <<<"$output" |
    grep -v -- "-D${expected}=1" || true)"
  if [ -n "$missing_definition" ]; then
    echo "$variant has compile commands without -D${expected}=1" >&2
    printf '%s\n' "$missing_definition" >&2
    return 1
  fi

  if ! grep -q -- ' -Os ' <<<"$output"; then
    echo "$variant is not using the release optimization flags" >&2
    return 1
  fi

  if ! grep -q -- "iPhoneOS${expected_sdk}.sdk" <<<"$output"; then
    echo "$variant is not using the documented iPhoneOS ${expected_sdk} SDK" >&2
    return 1
  fi

  if [ "$variant" = "roothide" ] &&
     grep -q -- "-L${THEOS}/vendor/lib/iphone/rootless" <<<"$output"; then
    echo "roothide must not add the rootless library search path" >&2
    return 1
  fi
}

check_variant normal H5GG_BUILD_NORMAL 16.5
check_variant rootless H5GG_BUILD_ROOTLESS 16.5
check_variant roothide H5GG_BUILD_ROOTHIDE 16.5

default_output="$(make -Bn -C "$repo_root" 2>&1)"
validation_output="$(make -Bn -C "$repo_root" H5GG_DEVICE_VALIDATION=1 2>&1)"

if grep -q -- 'Phase2DeviceFixture.cpp' <<<"$default_output"; then
  echo "default builds must not compile the Phase 2 device fixture" >&2
  exit 1
fi

if ! grep -q -- 'Phase2DeviceFixture.cpp' <<<"$validation_output" ||
   ! grep -q -- '-DH5GG_DEVICE_VALIDATION=1' <<<"$validation_output"; then
  echo "H5GG_DEVICE_VALIDATION=1 did not enable the Phase 2 device fixture" >&2
  exit 1
fi
