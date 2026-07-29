#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

build_variant() {
  local variant="$1"
  case "$variant" in
    normal)
      echo "==> Building normal (rootful) package"
      make clean package FINALPACKAGE=1
      ;;
    rootless|roothide)
      echo "==> Building ${variant} package"
      make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$variant"
      ;;
    *)
      echo "Unsupported build variant: $variant" >&2
      return 1
      ;;
  esac
}

mode="${1:-all}"
case "$mode" in
  all)
    build_variant normal
    build_variant rootless
    build_variant roothide
    ;;
  normal|rootless|roothide)
    build_variant "$mode"
    ;;
  *)
    echo "Usage: ./build.sh [all|normal|rootless|roothide]" >&2
    exit 1
    ;;
esac
