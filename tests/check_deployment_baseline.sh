#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected="15.0"

for makefile in "$repo_root/appstand/Makefile" "$repo_root/globalview/Makefile"; do
  if ! grep -Eq "^TARGET[[:space:]]*=[[:space:]]*iphone:([^:]+:)?[^:]+:${expected}$" "$makefile"; then
    echo "$(basename "$(dirname "$makefile")") does not target iOS ${expected}" >&2
    exit 1
  fi
done

project="$repo_root/h5ggapp-src/h5ggapp.xcodeproj/project.pbxproj"
if grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 12.0;' "$project"; then
  echo "h5ggapp Xcode settings still contain the unsupported iOS 12 baseline" >&2
  exit 1
fi

target_count="$(grep -c "IPHONEOS_DEPLOYMENT_TARGET = ${expected};" "$project")"
if [ "$target_count" -ne 4 ]; then
  echo "expected four iOS ${expected} Xcode deployment settings, found ${target_count}" >&2
  exit 1
fi

for plist in \
  "$repo_root/appstand/H5GGApp_layout/Applications/h5ggapp.app/Info.plist" \
  "$repo_root/globalview/H5GGApp_layout/Applications/h5ggapp.app/Info.plist"; do
  actual="$(plutil -extract MinimumOSVersion raw -o - "$plist")"
  if [ "$actual" != "$expected" ]; then
    echo "$plist advertises iOS ${actual}; expected ${expected}" >&2
    exit 1
  fi
done

echo "All distribution adapters use the iOS ${expected} deployment baseline"
