"""Validate dependency reuse without installing or changing a real checkout."""

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from prepare_workspace import CONFIGURATION, DEPENDENCIES, EXECUTABLES, prepare


class WorkspaceTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="emblem-workspace-")
        self.addCleanup(temporary.cleanup)
        self.target = Path(temporary.name) / "target"
        self.source = Path(temporary.name) / "source"
        for directory in (self.target, self.source):
            directory.mkdir()
            for name in CONFIGURATION:
                (directory / name).write_bytes(b"fixture configuration\n")
        for name in EXECUTABLES:
            executable = self.source / name
            executable.parent.mkdir(parents=True, exist_ok=True)
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
        for name, value in (
            ("prepare_workspace.shutil.which", "/fixture/tool"),
            (
                "prepare_workspace.subprocess.run",
                subprocess.CompletedProcess([], 0, ".venv\nnode_modules\n", ""),
            ),
        ):
            mocked = patch(name, return_value=value)
            mocked.start()
            self.addCleanup(mocked.stop)

    def assert_no_links(self) -> None:
        for name in DEPENDENCIES:
            self.assertFalse((self.target / name).exists())
            self.assertFalse((self.target / name).is_symlink())

    def test_matching_checkout_reuses_both_directories(self) -> None:
        links = prepare(self.target, self.source)
        self.assertEqual([p.name for p in links], list(DEPENDENCIES))
        for link in links:
            self.assertEqual(link.resolve(), (self.source / link.name).resolve())

    def test_each_configuration_difference_refuses_reuse(self) -> None:
        for name in CONFIGURATION:
            path = self.target / name
            original = path.read_bytes()
            path.write_bytes(b"different\n")
            with (
                self.subTest(name=name),
                self.assertRaisesRegex(ValueError, "Configuration differs"),
            ):
                prepare(self.target, self.source)
            self.assert_no_links()
            path.write_bytes(original)

    def test_existing_directory_and_dangling_link_are_never_replaced(self) -> None:
        destination = self.target / "node_modules"
        destination.mkdir()
        with self.assertRaises(FileExistsError):
            prepare(self.target, self.source)
        self.assertTrue(destination.is_dir())
        self.assertFalse((self.target / ".venv").exists())
        destination.rmdir()
        destination.symlink_to(self.target / "missing")
        with self.assertRaises(FileExistsError):
            prepare(self.target, self.source)
        self.assertEqual(destination.readlink(), self.target / "missing")

    def test_missing_installed_executable_refuses_reuse(self) -> None:
        (self.source / EXECUTABLES[-1]).chmod(0o644)
        with self.assertRaisesRegex(ValueError, "Installed executable"):
            prepare(self.target, self.source)
        self.assert_no_links()

    def test_missing_host_command_refuses_reuse(self) -> None:
        with (
            patch("prepare_workspace.shutil.which", return_value=None),
            self.assertRaisesRegex(ValueError, "Required executable"),
        ):
            prepare(self.target, self.source)
        self.assert_no_links()

    def test_unignored_links_and_git_failure_refuse_reuse(self) -> None:
        for result in (
            subprocess.CompletedProcess([], 0, ".venv\n", ""),
            subprocess.CompletedProcess([], 128, "", "not a repository"),
        ):
            with (
                self.subTest(result=result),
                patch("prepare_workspace.subprocess.run", return_value=result),
                self.assertRaisesRegex(ValueError, "Git-ignored"),
            ):
                prepare(self.target, self.source)
            self.assert_no_links()

    def test_second_link_failure_rolls_back_first(self) -> None:
        symlink = Path.symlink_to

        def fail_second(path, *args, **kwargs):
            if path.name == "node_modules":
                raise OSError("fixture cannot create link")
            return symlink(path, *args, **kwargs)

        with patch.object(Path, "symlink_to", fail_second), self.assertRaises(OSError):
            prepare(self.target, self.source)
        self.assert_no_links()


if __name__ == "__main__":
    unittest.main()
