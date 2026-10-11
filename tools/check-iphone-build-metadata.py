#!/usr/bin/env python3
"""Check the linked iPhone SDK that controls native Liquid Glass adoption."""

import argparse
import json
import plistlib
import struct
import sys
from pathlib import Path
from typing import cast


class IPhoneBuildMetadataError(ValueError):
    """Reject stale or malformed iPhone build metadata before signing."""


def parse_iphone_version(value: str) -> tuple[int, int, int]:
    """Normalize SDK and minimum iOS versions without changing their meaning."""
    parts = value.split(".")
    if not 1 <= len(parts) <= 3 or not all(part.isdecimal() for part in parts):
        raise IPhoneBuildMetadataError(f"invalid iOS version: {value!r}")
    padded = parts + ["0"] * (3 - len(parts))
    return int(padded[0]), int(padded[1]), int(padded[2])


def read_iphone_macho_versions(executable: Path) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    """Read minimum iOS and linked SDK from the actual arm64 executable, not its plist."""
    with executable.open("rb") as source:
        header = source.read(32)
        if len(header) != 32:
            raise IPhoneBuildMetadataError("truncated Mach-O header")
        magic, cpu, _, file_type, command_count, command_bytes, _, _ = struct.unpack("<8I", header)
        if magic != 0xFEEDFACF or cpu != 0x0100000C or file_type != 2:
            raise IPhoneBuildMetadataError("expected a thin arm64 Mach-O executable")
        if not 1 <= command_count <= 4096 or not 8 <= command_bytes <= 1_048_576:
            raise IPhoneBuildMetadataError("invalid Mach-O load-command bounds")
        commands = source.read(command_bytes)
        if len(commands) != command_bytes:
            raise IPhoneBuildMetadataError("truncated Mach-O load commands")
    offset = 0
    for _ in range(command_count):
        if offset + 8 > len(commands):
            raise IPhoneBuildMetadataError("missing Mach-O load command")
        command, size = struct.unpack_from("<2I", commands, offset)
        if size < 8 or offset + size > len(commands):
            raise IPhoneBuildMetadataError("invalid Mach-O load-command size")
        if command == 0x32:  # LC_BUILD_VERSION
            if size < 24:
                raise IPhoneBuildMetadataError("truncated LC_BUILD_VERSION")
            platform, minimum, sdk, _ = struct.unpack_from("<4I", commands, offset + 8)
            if platform != 2:
                raise IPhoneBuildMetadataError("executable does not target physical iOS")
            minimum_version = (minimum >> 16, (minimum >> 8) & 255, minimum & 255)
            sdk_version = (sdk >> 16, (sdk >> 8) & 255, sdk & 255)
            return minimum_version, sdk_version
        offset += size
    raise IPhoneBuildMetadataError("missing iOS LC_BUILD_VERSION")


def require_iphone_metadata_text(values: dict[str, object], key: str) -> str:
    """Reject missing or non-text SDK metadata instead of trusting dynamic file values."""
    value = values.get(key)
    if not isinstance(value, str) or not value:
        raise IPhoneBuildMetadataError(f"missing or invalid metadata field: {key}")
    return value


def check_iphone_build_metadata(app: Path, sdk_settings: Path | None) -> str:
    """Fail when native bars would see a legacy SDK, even if glass API calls compile."""
    info_object = cast(object, plistlib.loads((app / "Info.plist").read_bytes()))
    if not isinstance(info_object, dict):
        raise IPhoneBuildMetadataError("Info.plist is not a dictionary")
    info = cast(dict[str, object], info_object)
    minimum, sdk = read_iphone_macho_versions(app / require_iphone_metadata_text(info, "CFBundleExecutable"))
    if sdk < (26, 0, 0):
        raise IPhoneBuildMetadataError(
            f"linked SDK is {'.'.join(map(str, sdk))}; native Liquid Glass requires SDK 26+"
        )
    if minimum != parse_iphone_version(require_iphone_metadata_text(info, "MinimumOSVersion")):
        raise IPhoneBuildMetadataError("Mach-O minimum iOS differs from MinimumOSVersion")
    if info.get("UIDesignRequiresCompatibility") is True:
        raise IPhoneBuildMetadataError("UIDesignRequiresCompatibility opts out of Liquid Glass")
    if sdk_settings is not None:
        settings_object = cast(object, json.loads(sdk_settings.read_text()))
        if not isinstance(settings_object, dict):
            raise IPhoneBuildMetadataError("SDK settings are not a dictionary")
        settings = cast(dict[str, object], settings_object)
        if sdk != parse_iphone_version(require_iphone_metadata_text(settings, "Version")):
            raise IPhoneBuildMetadataError("Mach-O linked SDK differs from the supplied Apple SDK")
        if info.get("DTSDKName") != settings["CanonicalName"]:
            raise IPhoneBuildMetadataError("DTSDKName differs from the supplied Apple SDK")
        if info.get("DTPlatformVersion") != settings["Version"]:
            raise IPhoneBuildMetadataError("DTPlatformVersion differs from the supplied Apple SDK")
    return f"linked SDK {'.'.join(map(str, sdk))}; minimum iOS {'.'.join(map(str, minimum))}"


class IPhoneMetadataArguments(argparse.Namespace):
    """The checker accepts local app and SDK paths, never signing credentials."""

    app: Path = Path()
    sdk_settings: Path | None = None


def main() -> int:
    """Validate an unsigned or staged iPhone app without executing or modifying it."""
    parser = argparse.ArgumentParser(description=__doc__)
    _ = parser.add_argument("app", type=Path)
    _ = parser.add_argument("--sdk-settings", type=Path)
    args = parser.parse_args(namespace=IPhoneMetadataArguments())
    try:
        result = check_iphone_build_metadata(args.app, args.sdk_settings)
    except (IPhoneBuildMetadataError, OSError, KeyError, ValueError) as error:
        print(f"Pi Mobile iOS metadata: {error}", file=sys.stderr)
        return 1
    print(f"Pi Mobile iOS metadata: {result}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
