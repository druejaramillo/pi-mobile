#!/usr/bin/env python3
"""Exercise the iPhone build metadata checker through its public CLI."""

import json
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import final, override

CHECKER = Path(__file__).with_name("check-iphone-build-metadata.py")


@final
class IPhoneBuildMetadataTests(unittest.TestCase):
    """A modern plist cannot disguise legacy linked-SDK compatibility behavior."""

    @override
    def __init__(self, methodName: str = "runTest") -> None:
        super().__init__(methodName)
        self.root = Path()
        self.app = Path()
        self.settings = Path()
        self.info: dict[str, str | bool] = {}

    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.app = self.root / "PiMobile.app"
        self.app.mkdir()
        self.settings = self.root / "SDKSettings.json"
        _ = self.settings.write_text(json.dumps({"Version": "27.0", "CanonicalName": "iphoneos27.0"}))
        self.info = {
            "CFBundleExecutable": "PiMobile",
            "MinimumOSVersion": "17.0",
            "DTSDKName": "iphoneos27.0",
            "DTPlatformVersion": "27.0",
        }

    def write_app(self, sdk: int = 27, minimum: int = 17, command_size: int = 24) -> None:
        header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 1, 24, 0, 0)
        command = struct.pack("<6I", 0x32, command_size, 2, minimum << 16, sdk << 16, 0)
        _ = (self.app / "PiMobile").write_bytes(header + command)
        _ = (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def run_checker(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECKER), str(self.app), "--sdk-settings", str(self.settings)],
            capture_output=True, text=True, check=False,
        )

    def test_modern_sdk_keeps_ios17_minimum(self) -> None:
        self.write_app()
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("linked SDK 27.0.0; minimum iOS 17.0.0", result.stdout)

    def test_legacy_executable_fails_even_with_modern_plist(self) -> None:
        self.write_app(sdk=17)
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("linked SDK is 17.0.0", result.stderr)

    def test_linked_sdk_must_match_supplied_apple_sdk(self) -> None:
        self.write_app(sdk=26)
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("linked SDK differs from the supplied Apple SDK", result.stderr)

    def test_sdk_fix_cannot_silently_raise_minimum_ios(self) -> None:
        self.write_app(minimum=27)
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("minimum iOS differs", result.stderr)

    def test_compatibility_opt_out_is_rejected(self) -> None:
        self.info["UIDesignRequiresCompatibility"] = True
        self.write_app()
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("opts out of Liquid Glass", result.stderr)

    def test_truncated_load_command_is_rejected(self) -> None:
        self.write_app(command_size=8)
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("truncated LC_BUILD_VERSION", result.stderr)


if __name__ == "__main__":
    _ = unittest.main(verbosity=2)
