#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/h5gg-release-artifacts-$$}"
mkdir -p "$ARTIFACT_DIR"

collect_variant_artifacts() {
  local variant="$1"
  shopt -s nullglob
  local artifacts=(packages/*.deb)
  shopt -u nullglob
  if [ ${#artifacts[@]} -eq 0 ]; then
    echo "No deb artifacts found for ${variant}" >&2
    return 1
  fi

  local artifact
  for artifact in "${artifacts[@]}"; do
    cp "$artifact" "${ARTIFACT_DIR}/${variant}-$(basename "$artifact")"
  done
}

publish_collected_artifacts() {
  mkdir -p packages/release-artifacts
  rm -f packages/release-artifacts/*.deb
  cp "$ARTIFACT_DIR"/*.deb packages/release-artifacts/
}

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
  collect_variant_artifacts "$variant"
}

mode="${1:-all}"
case "$mode" in
  all)
    build_variant normal
    build_variant rootless
    build_variant roothide
    publish_collected_artifacts
    ;;
  normal|rootless|roothide)
    build_variant "$mode"
    publish_collected_artifacts
    ;;
  *)
    echo "Usage: ./build.sh [all|normal|rootless|roothide]" >&2
    exit 1
    ;;
esac
