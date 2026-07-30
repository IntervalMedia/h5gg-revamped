#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [ -n "${ARTIFACT_DIR:-}" ]; then
  mkdir -p "$ARTIFACT_DIR"
else
  old_umask="$(umask)"
  umask 077
  ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/h5gg-release-artifacts.XXXXXX")"
  umask "$old_umask"
  trap 'rm -rf "$ARTIFACT_DIR"' EXIT
fi

collect_variant_artifacts() {
  local variant="$1"
  local nullglob_state
  nullglob_state="$(shopt -p nullglob)"
  shopt -s nullglob
  local artifacts=(packages/*.deb)
  eval "$nullglob_state"
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
  local nullglob_state
  nullglob_state="$(shopt -p nullglob)"
  shopt -s nullglob
  local artifacts=("$ARTIFACT_DIR"/*.deb)
  eval "$nullglob_state"

  if [ ${#artifacts[@]} -eq 0 ]; then
    echo "No collected deb artifacts found in ${ARTIFACT_DIR}" >&2
    return 1
  fi

  mkdir -p packages/release-artifacts
  rm -f packages/release-artifacts/*.deb
  cp "${artifacts[@]}" packages/release-artifacts/
}

preflight_check_variant() {
  local variant="$1"

  case "$variant" in
    rootless|roothide)
      local theos_root="${THEOS:-}"
      if [ -z "$theos_root" ]; then
        echo "THEOS is not set. Cannot verify libroot for ${variant} build." >&2
        echo "Set THEOS to your Theos path (example: export THEOS=\"$HOME/theos\")." >&2
        return 1
      fi

      local candidates=(
        "$theos_root/vendor/lib/iphone/rootless/libroot.a"
        "$theos_root/vendor/lib/libroot.a"
      )

      local candidate
      for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
          return 0
        fi
      done

      echo "Missing libroot for ${variant} build (linker requires -lroot)." >&2
      echo "Checked:" >&2
      for candidate in "${candidates[@]}"; do
        echo "  - ${candidate}" >&2
      done
      echo "Install/update roothide/rootless Theos support, then retry." >&2
      return 1
      ;;
  esac
}

build_variant() {
  local variant="$1"

  preflight_check_variant "$variant"

  # Avoid mixing stale artifacts from earlier builds.
  rm -f packages/*.deb

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
