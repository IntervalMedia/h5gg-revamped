#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 normal|rootless|roothide PACKAGE.deb" >&2
  exit 2
fi

variant="$1"
package="$2"
case "$variant" in
  normal)
    expected_architecture="iphoneos-arm"
    install_root="."
    ;;
  rootless)
    expected_architecture="iphoneos-arm64"
    install_root="./var/jb"
    ;;
  roothide)
    expected_architecture="iphoneos-arm64e"
    install_root="."
    ;;
  *)
    echo "Unsupported package variant: $variant" >&2
    exit 2
    ;;
esac

if [ ! -f "$package" ]; then
  echo "Package does not exist: $package" >&2
  exit 1
fi

for command_name in ar tar python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Package validation requires $command_name" >&2
    exit 1
  fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/h5gg-package-check.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

(
  cd "$work_dir"
  ar -x "$package"
)

if [ ! -f "$work_dir/debian-binary" ] ||
   [ "$(tr -d '[:space:]' < "$work_dir/debian-binary")" != "2.0" ]; then
  echo "$variant package is not Debian binary format 2.0" >&2
  exit 1
fi

control_archives=("$work_dir"/control.tar.*)
data_archives=("$work_dir"/data.tar.*)
if [ "${#control_archives[@]}" -ne 1 ] || [ ! -f "${control_archives[0]}" ] ||
   [ "${#data_archives[@]}" -ne 1 ] || [ ! -f "${data_archives[0]}" ]; then
  echo "$variant package must contain one control and one data archive" >&2
  exit 1
fi

mkdir -p "$work_dir/control" "$work_dir/data"
tar -xf "${control_archives[0]}" -C "$work_dir/control"
tar -xf "${data_archives[0]}" -C "$work_dir/data"

control_file="$work_dir/control/control"
if [ ! -f "$control_file" ]; then
  echo "$variant package is missing DEBIAN/control" >&2
  exit 1
fi

control_field() {
  local file="$1"
  local field="$2"
  awk -v wanted="$field" '
    BEGIN { FS = ":[[:space:]]*" }
    tolower($1) == tolower(wanted) {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      print
      exit
    }
  ' "$file"
}

expected_package="$(control_field "$repo_root/control" Package)"
expected_version="$(control_field "$repo_root/control" Version)"
actual_package="$(control_field "$control_file" Package)"
actual_version="$(control_field "$control_file" Version)"
actual_architecture="$(control_field "$control_file" Architecture)"
actual_depends="$(control_field "$control_file" Depends)"
installed_size="$(control_field "$control_file" Installed-Size)"

if [ "$actual_package" != "$expected_package" ] ||
   [ "$actual_version" != "$expected_version" ] ||
   [ "$actual_architecture" != "$expected_architecture" ]; then
  echo "$variant package control metadata does not match the release contract" >&2
  echo "  package=$actual_package version=$actual_version architecture=$actual_architecture" >&2
  exit 1
fi
if ! printf '%s\n' "$actual_depends" | grep -Eq '(^|,)[[:space:]]*mobilesubstrate([[:space:](,]|$)'; then
  echo "$variant package is missing its mobilesubstrate dependency" >&2
  exit 1
fi
if ! printf '%s\n' "$installed_size" | grep -Eq '^[1-9][0-9]*$'; then
  echo "$variant package has an invalid Installed-Size" >&2
  exit 1
fi
if [ ! -x "$work_dir/control/preinst" ]; then
  echo "$variant package is missing its executable preinst script" >&2
  exit 1
fi

expected_dylib="$install_root/Library/MobileSubstrate/DynamicLibraries/H5GG.dylib"
expected_plist="$install_root/Library/MobileSubstrate/DynamicLibraries/H5GG.plist"
(
  cd "$work_dir/data"
  find . \( -type f -o -type l \) -print | LC_ALL=C sort
) > "$work_dir/manifest"
printf '%s\n%s\n' "$expected_dylib" "$expected_plist" | LC_ALL=C sort > "$work_dir/expected-manifest"
if ! diff -u "$work_dir/expected-manifest" "$work_dir/manifest"; then
  echo "$variant package contains an unexpected installed-file layout" >&2
  exit 1
fi

dylib_path="$work_dir/data/${expected_dylib#./}"
plist_path="$work_dir/data/${expected_plist#./}"
if [ ! -s "$dylib_path" ] || [ ! -s "$plist_path" ]; then
  echo "$variant package dylib/plist pair is missing or empty" >&2
  exit 1
fi
python3 "$repo_root/tests/check_package_payload.py" "$dylib_path" "$plist_path"

echo "$variant package contents verified: $(basename "$package")"
