#!/usr/bin/env python3

import plistlib
import struct
import sys
from pathlib import Path


CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_MASK = 0x00FFFFFF
CPU_SUBTYPE_ARM64_ALL = 0
CPU_SUBTYPE_ARM64E = 2


def fail(message: str) -> None:
    raise SystemExit(f"package payload validation failed: {message}")


def architecture_name(cpu_type: int, cpu_subtype: int) -> str:
    if cpu_type != CPU_TYPE_ARM64:
        return f"cpu-{cpu_type:#x}-subtype-{cpu_subtype:#x}"
    subtype = cpu_subtype & CPU_SUBTYPE_MASK
    if subtype == CPU_SUBTYPE_ARM64_ALL:
        return "arm64"
    if subtype == CPU_SUBTYPE_ARM64E:
        return "arm64e"
    return f"arm64-subtype-{subtype}"


def fat_architectures(data: bytes, endian: str, is_64_bit: bool) -> list[str]:
    if len(data) < 8:
        fail("truncated fat Mach-O header")
    count = struct.unpack_from(f"{endian}I", data, 4)[0]
    entry_size = 32 if is_64_bit else 20
    if count == 0 or count > 32 or 8 + count * entry_size > len(data):
        fail("invalid fat Mach-O architecture table")

    architectures: list[str] = []
    for index in range(count):
        offset = 8 + index * entry_size
        cpu_type, cpu_subtype = struct.unpack_from(f"{endian}II", data, offset)
        if is_64_bit:
            slice_offset, slice_size = struct.unpack_from(f"{endian}QQ", data, offset + 8)
        else:
            slice_offset, slice_size = struct.unpack_from(f"{endian}II", data, offset + 8)
        if slice_size == 0 or slice_offset > len(data) or slice_size > len(data) - slice_offset:
            fail(f"architecture slice {index} is outside the dylib")
        architectures.append(architecture_name(cpu_type, cpu_subtype))
    return architectures


def macho_architectures(path: Path) -> list[str]:
    data = path.read_bytes()
    if len(data) < 8:
        fail("dylib is empty or truncated")

    magic = data[:4]
    if magic == b"\xca\xfe\xba\xbe":
        return fat_architectures(data, ">", False)
    if magic == b"\xbe\xba\xfe\xca":
        return fat_architectures(data, "<", False)
    if magic == b"\xca\xfe\xba\xbf":
        return fat_architectures(data, ">", True)
    if magic == b"\xbf\xba\xfe\xca":
        return fat_architectures(data, "<", True)
    fail(f"dylib is not a universal Mach-O (magic {magic.hex()})")


def validate_plist(path: Path) -> None:
    try:
        with path.open("rb") as stream:
            plist = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"invalid substrate plist: {error}")

    bundles = plist.get("Filter", {}).get("Bundles") if isinstance(plist, dict) else None
    if not isinstance(bundles, list) or not bundles or any(
        not isinstance(bundle, str) or not bundle for bundle in bundles
    ):
        fail("substrate plist must contain a non-empty Filter.Bundles string list")


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: check_package_payload.py DYLIB PLIST")

    dylib = Path(sys.argv[1])
    plist = Path(sys.argv[2])
    architectures = macho_architectures(dylib)
    if len(architectures) != 2 or set(architectures) != {"arm64", "arm64e"}:
        fail(f"expected arm64 and arm64e slices, found {architectures}")
    validate_plist(plist)


if __name__ == "__main__":
    main()
