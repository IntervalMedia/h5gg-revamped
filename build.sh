#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

H5GG_CLEAN_ARTIFACT_DIR=""
if [ -n "${ARTIFACT_DIR:-}" ]; then
  mkdir -p "$ARTIFACT_DIR"
else
  old_umask="$(umask)"
  umask 077
  ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/h5gg-release-artifacts.XXXXXX")"
  umask "$old_umask"
  H5GG_CLEAN_ARTIFACT_DIR="$ARTIFACT_DIR"
fi

H5GG_PACKAGE_BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/h5gg-package-build.XXXXXX")"
H5GG_COLLECTED_DIR="$H5GG_PACKAGE_BUILD_ROOT/collected"
mkdir -p "$H5GG_COLLECTED_DIR"
cleanup() {
  rm -rf "$H5GG_PACKAGE_BUILD_ROOT"
  if [ -n "$H5GG_CLEAN_ARTIFACT_DIR" ]; then
    rm -rf "$H5GG_CLEAN_ARTIFACT_DIR"
  fi
}
trap cleanup EXIT

collect_variant_artifacts() (
  local variant="$1"
  local package_dir="$2"
  shopt -s nullglob
  local artifacts=("$package_dir"/*.deb)
  if [ ${#artifacts[@]} -eq 0 ]; then
    echo "No deb artifacts found for ${variant}" >&2
    return 1
  fi

  local artifact
  for artifact in "${artifacts[@]}"; do
    cp "$artifact" "$H5GG_COLLECTED_DIR/${variant}-$(basename "$artifact")"
  done
)

publish_artifact() {
  local artifact="$1"
  local destination_dir="$2"
  local filename
  local destination

  filename="$(basename "$artifact")"
  destination="$destination_dir/$filename"
  mkdir -p "$destination_dir"

  if [ -e "$destination" ]; then
    if cmp -s "$artifact" "$destination"; then
      return 0
    fi
    local digest
    digest="$(shasum -a 256 "$artifact" | awk '{print substr($1, 1, 12)}')"
    destination="$destination_dir/${filename%.deb}-${digest}.deb"
    if [ -e "$destination" ]; then
      if cmp -s "$artifact" "$destination"; then
        return 0
      fi
      echo "Artifact collision at ${destination}" >&2
      return 1
    fi
  fi

  cp "$artifact" "$destination"
}

publish_collected_artifacts() (
  shopt -s nullglob
  local artifacts=("$H5GG_COLLECTED_DIR"/*.deb)

  if [ ${#artifacts[@]} -eq 0 ]; then
    echo "No collected deb artifacts found in ${H5GG_COLLECTED_DIR}" >&2
    return 1
  fi

  local artifact
  for artifact in "${artifacts[@]}"; do
    publish_artifact "$artifact" "$ARTIFACT_DIR"
    publish_artifact "$artifact" "$ROOT_DIR/packages/release-artifacts"
  done
)

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
  local package_dir="$H5GG_PACKAGE_BUILD_ROOT/$variant"

  preflight_check_variant "$variant"
  mkdir -p "$package_dir"

  case "$variant" in
    normal|rootless|roothide)
      echo "==> Building ${variant} package"
      make -j1 "package-${variant}" FINALPACKAGE=1 THEOS_PACKAGE_DIR="$package_dir"
      ;;
    *)
      echo "Unsupported build variant: $variant" >&2
      return 1
      ;;
  esac
  collect_variant_artifacts "$variant" "$package_dir"
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
