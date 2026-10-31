"""Check opt-in hook setup in real isolated git repositories."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from install_hooks import install


class HooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init")
        (self.root / ".githooks").mkdir()
        for name in ("pre-commit", "pre-push"):
            (self.root / ".githooks" / name).write_text("#!/bin/sh\nexit 0\n")

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", str(self.root), *args], capture_output=True, text=True, check=True
        ).stdout.strip()

    def test_install_is_local_and_idempotent(self):
        install(self.root)
        install(self.root)
        self.assertEqual(self.git("config", "--local", "--get", "core.hooksPath"), ".githooks")

    def test_custom_configuration_is_retained(self):
        self.git("config", "--local", "core.hooksPath", "custom-hooks")
        with self.assertRaisesRegex(RuntimeError, "retained"):
            install(self.root)
        self.assertEqual(self.git("config", "--local", "--get", "core.hooksPath"), "custom-hooks")

    def test_existing_hook_is_retained(self):
        hook = self.root / ".git/hooks/pre-commit"
        hook.write_text("custom\n")
        with self.assertRaisesRegex(RuntimeError, "retained"):
            install(self.root)
        self.assertEqual(hook.read_text(), "custom\n")


if __name__ == "__main__":
    unittest.main()
