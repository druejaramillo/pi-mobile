#!/usr/bin/env python3
"""Exercise the user-wide host installer through its public CLI in isolated account directories."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import final, override

ROOT = Path(__file__).resolve().parent.parent
INSTALLER = ROOT / "tools/install-host.sh"


@final
class HostInstallTests(unittest.TestCase):
    """Installation must be checkout-independent and never overwrite unrelated account state."""

    @override
    def __init__(self, methodName: str = "runTest") -> None:
        super().__init__(methodName)
        self.home = Path()
        self.host = Path()
        self.loader = Path()
        self.env: dict[str, str] = {}

    @override
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory(prefix="pi-mobile-host-install-")
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name) / "account with spaces"
        self.home.mkdir()
        self.host = self.home / ".local/share/pi-mobile/host"
        self.loader = self.home / ".pi/agent/extensions/pi-mobile.ts"
        self.env = {**os.environ, "HOME": str(self.home)}
        _ = self.env.pop("PI_CODING_AGENT_DIR", None)

    def install_host(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(INSTALLER), *arguments],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_installed_runtime_and_global_loader_do_not_depend_on_checkout(
        self,
    ) -> None:
        result = self.install_host()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            {path.name for path in self.host.iterdir()},
            {"bridge-cli.mjs", "pi-mobile-extension.ts", "package.json", "lib"},
        )
        for source in (ROOT / "host/lib").iterdir():
            self.assertEqual(
                source.read_bytes(), (self.host / "lib" / source.name).read_bytes()
            )
        for name in ("bridge-cli.mjs", "pi-mobile-extension.ts", "package.json"):
            self.assertEqual(
                (ROOT / "host" / name).read_bytes(), (self.host / name).read_bytes()
            )
        self.assertNotIn(str(ROOT), self.loader.read_text())

    def test_installed_global_factory_loads_without_starting_a_session(self) -> None:
        node_major = int(
            subprocess.check_output(
                ["node", "-p", "process.versions.node.split('.')[0]"], text=True
            )
        )
        if node_major >= 26:
            self.skipTest(
                "Node 26 removed the transformation flag; Pi uses jiti, while this direct factory probe uses Node 24."
            )
        result = self.install_host()
        self.assertEqual(result.returncode, 0, result.stderr)
        probe = subprocess.run(
            [
                "node",
                "--experimental-transform-types",
                "--input-type=module",
                "-e",
                (
                    "const {default: factory} = await import(process.argv[1]); const events = new Set(); "
                    "factory({on(name) { events.add(name); }}); "
                    "if (!events.has('session_start') || !events.has('session_shutdown') || events.size !== 12) throw Error('factory load failed');"
                ),
                self.loader.as_uri(),
            ],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(probe.returncode, 0, probe.stderr)

    def test_matching_repeat_is_a_noop(self) -> None:
        self.assertEqual(self.install_host().returncode, 0)
        previous = (
            self.loader.stat().st_mtime_ns,
            (self.host / "bridge-cli.mjs").stat().st_mtime_ns,
        )
        result = self.install_host()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nothing changed", result.stdout)
        self.assertEqual(
            previous,
            (
                self.loader.stat().st_mtime_ns,
                (self.host / "bridge-cli.mjs").stat().st_mtime_ns,
            ),
        )

    def test_existing_host_is_preserved_without_creating_loader(self) -> None:
        self.host.mkdir(parents=True)
        sentinel = self.host / "keep.txt"
        _ = sentinel.write_text("unrelated installation")
        self.assertEqual(self.install_host().returncode, 2)
        self.assertEqual(sentinel.read_text(), "unrelated installation")
        self.assertFalse(self.loader.exists())

    def test_existing_extension_is_preserved_without_installing_host(self) -> None:
        self.loader.parent.mkdir(parents=True)
        _ = self.loader.write_text("existing extension")
        self.assertEqual(self.install_host().returncode, 2)
        self.assertEqual(self.loader.read_text(), "existing extension")
        self.assertFalse(self.host.exists())

    def test_symlink_parent_is_refused(self) -> None:
        outside = self.home.parent / "outside"
        outside.mkdir()
        (self.home / ".pi").symlink_to(outside, target_is_directory=True)
        self.assertEqual(self.install_host().returncode, 2)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse(self.host.exists())

    def test_dangling_symlink_target_is_refused(self) -> None:
        self.loader.parent.mkdir(parents=True)
        self.loader.symlink_to(self.home / "missing")
        self.assertEqual(self.install_host().returncode, 2)
        self.assertTrue(self.loader.is_symlink())
        self.assertFalse(self.host.exists())

    def test_unknown_argument_and_custom_agent_directory_are_refused(self) -> None:
        self.assertEqual(self.install_host("--yes").returncode, 2)
        self.env["PI_CODING_AGENT_DIR"] = str(self.home / "another-agent")
        self.assertEqual(self.install_host().returncode, 2)
        self.assertFalse(self.host.exists())
        self.assertFalse(self.loader.exists())


if __name__ == "__main__":
    _ = unittest.main(verbosity=2)
