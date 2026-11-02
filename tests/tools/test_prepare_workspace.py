"""Validate workspace initialization without installing real dependencies."""

import contextlib
import io
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from emblem_dev import workspace
from emblem_dev.commands import workspace as workspace_commands


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="emblem-workspace-")
        self.addCleanup(temporary.cleanup)
        self.target = Path(temporary.name).resolve() / "target with spaces"
        self.source = Path(temporary.name).resolve() / "source"
        for directory in (self.target, self.source):
            directory.mkdir()
            (directory / ".git").write_text("gitdir: fixture\n")
            for name in workspace.CONFIGURATION:
                (directory / name).write_bytes(b"fixture\n")
            (directory / "pyproject.toml").write_text(
                '[project]\nname = "emblem-rekindled-tools"\n'
            )
        executable = self.source / "node_modules/.bin/prettier"
        executable.parent.mkdir(parents=True)
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        for name, value in (("ROOT", self.target),):
            mocked = patch.object(workspace, name, value)
            mocked.start()
            self.addCleanup(mocked.stop)
        which = patch.object(workspace.shutil, "which", return_value="/fixture/tool")
        which.start()
        self.addCleanup(which.stop)
        run = patch.object(workspace.subprocess, "run", side_effect=self.run_command)
        self.run = run.start()
        self.addCleanup(run.stop)

    @staticmethod
    def run_command(argv, **kwargs):
        return subprocess.CompletedProcess(argv, 0, kwargs.get("input", ""), "")

    def test_setup_reuses_real_environment_and_locks_destination(self):
        (self.target / ".venv").mkdir()
        (self.target / "node_modules").mkdir()
        with patch.dict(
            os.environ,
            {
                "UV_PROJECT_ENVIRONMENT": str(self.source / ".venv"),
                "VIRTUAL_ENV": str(self.source / ".venv"),
                "UV_ACTIVE": "true",
                "PYTHONPATH": str(self.source),
                "UV_CACHE_DIR": "/cache",
            },
        ):
            workspace.setup(self.target)
        uv, bun = self.run.call_args_list[1:]
        self.assertEqual(uv.args[0], ["uv", "sync", "--locked", "--project", str(self.target)])
        self.assertEqual(bun.args[0], ["bun", "install", "--frozen-lockfile"])
        for call in (uv, bun):
            self.assertEqual(call.kwargs["cwd"], self.target)
            self.assertTrue(call.kwargs["check"])
            env = call.kwargs["env"]
            self.assertEqual(env["UV_PROJECT_ENVIRONMENT"], str(self.target / ".venv"))
            self.assertEqual(env["UV_CACHE_DIR"], "/cache")
            for name in ("VIRTUAL_ENV", "UV_ACTIVE", "PYTHONPATH"):
                self.assertNotIn(name, env)

    def test_invalid_target_and_python_links_fail_before_commands(self):
        for origin in (self.source / "node_modules", self.source / "missing"):
            environment = self.target / ".venv"
            environment.symlink_to(origin)
            with self.assertRaisesRegex(ValueError, "real local directory"):
                workspace.setup(self.target)
            self.assertEqual(environment.readlink(), origin)
            environment.unlink()
        (self.target / ".git").unlink()
        with self.assertRaisesRegex(ValueError, "existing checkout"):
            workspace.setup(self.target)
        self.run.assert_not_called()

    def test_reuse_js_only_and_never_overwrites(self):
        workspace_commands.reuse_js(self.source)
        link = self.target / "node_modules"
        self.assertEqual(link.resolve(), self.source / "node_modules")
        self.assertFalse((self.target / ".venv").exists())
        with self.assertRaises(FileExistsError):
            workspace_commands.reuse_js(self.source)
        link.unlink()
        link.symlink_to(self.source / "missing")
        with self.assertRaises(FileExistsError):
            workspace_commands.reuse_js(self.source)

    def test_configuration_conflicts_fail_before_commands(self):
        for name in workspace.JS_CONFIGURATION:
            path = self.target / name
            original = path.read_bytes()
            path.write_bytes(original + b"#different\n")
            with (
                self.subTest(name=name),
                self.assertRaisesRegex(ValueError, "Configuration differs"),
            ):
                workspace_commands.reuse_js(self.source)
            self.run.assert_not_called()
            path.write_bytes(original)

    def test_python_configuration_changes_do_not_block_js_reuse(self):
        for name in ("pyproject.toml", "uv.lock", "gdlintrc"):
            path = self.target / name
            path.write_bytes(path.read_bytes() + b"#different\n")
        workspace_commands.reuse_js(self.source)
        link = self.target / "node_modules"
        self.assertEqual(link.resolve(), self.source / "node_modules")

    def test_setup_link_validates_and_skips_bun(self):
        workspace_commands.reuse_js(self.source)
        self.run.reset_mock()
        with contextlib.redirect_stdout(io.StringIO()):
            workspace.setup(self.target)
        self.assertEqual([c.args[0][0] for c in self.run.call_args_list], ["git", "uv"])
        (self.source / "bun.lock").write_text("changed")
        self.run.reset_mock()
        with self.assertRaisesRegex(ValueError, "Configuration differs"):
            workspace.setup(self.target)
        self.run.assert_not_called()
        self.assertEqual((self.source / "bun.lock").read_text(), "changed")

    def test_missing_executable_and_unignored_links_refuse_reuse(self):
        executable = self.source / "node_modules/.bin/prettier"
        executable.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "Installed executable"):
            workspace_commands.reuse_js(self.source)
        self.run.assert_not_called()
        executable.chmod(0o755)
        for result in (
            subprocess.CompletedProcess([], 0, "", ""),
            subprocess.CompletedProcess([], 128, "", "not a repository"),
        ):
            with patch.object(workspace.subprocess, "run", return_value=result):
                with self.assertRaisesRegex(ValueError, "Git-ignored"):
                    workspace_commands.reuse_js(self.source)
            self.assertFalse((self.target / "node_modules").exists())

    def test_copy_local_whitelist_and_no_overwrite(self):
        (self.source / "AGENTS.local.md").write_text("machine settings")
        (self.source / ".secrets").mkdir()
        (self.source / ".secrets/token").write_text("fixture secret")
        workspace_commands.copy_local(self.source)
        copied = [self.target / "AGENTS.local.md"]
        self.assertEqual(copied[0].read_text(), "machine settings")
        self.assertFalse((self.target / ".secrets").exists())
        with self.assertRaises(FileExistsError):
            workspace_commands.copy_local(self.source)
        copied[0].unlink()
        copied[0].symlink_to(self.target / "missing")
        with self.assertRaises(FileExistsError):
            workspace_commands.copy_local(self.source)

    def test_status_is_read_only(self):
        before = list(self.target.iterdir())
        with contextlib.redirect_stdout(io.StringIO()) as output:
            workspace_commands.status()
        self.assertIn(".venv: missing", output.getvalue())
        self.assertEqual(list(self.target.iterdir()), before)
        self.run.assert_not_called()

    def test_missing_host_tool_and_invalid_js_link_fail_before_commands(self):
        with patch.object(workspace.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "Required executable"):
                workspace.setup(self.target)
        link = self.target / "node_modules"
        link.symlink_to(self.source / "missing")
        with self.assertRaises(FileNotFoundError):
            workspace.setup(self.target)
        link.unlink()
        link.symlink_to(self.source)
        with self.assertRaisesRegex(ValueError, "Invalid node_modules"):
            workspace.setup(self.target)
        self.run.assert_not_called()

    def test_hooks_are_explicit_and_explain_shared_config(self):
        with patch.object(workspace, "install_hooks") as install:
            workspace.setup(self.target)
            install.assert_not_called()
            with contextlib.redirect_stdout(io.StringIO()) as output:
                workspace.setup(self.target, hooks=True)
            install.assert_called_once_with(self.target)
            self.assertIn("shared by linked worktrees", output.getvalue())

    def test_other_checkout_uses_native_setup_and_never_target_script(self):
        (self.source / "tools").mkdir()
        (self.source / "tools/prepare_workspace.py").write_text("raise AssertionError('unsafe')")
        workspace.setup(self.source)
        uv, bun = self.run.call_args_list[1:]
        self.assertEqual(uv.kwargs["cwd"], self.source)
        self.assertEqual(bun.kwargs["cwd"], self.source)
        self.assertEqual([c.args[0][0] for c in self.run.call_args_list], ["git", "uv", "bun"])

    def test_failure_and_interrupt_stop_before_bun(self):
        for error in (subprocess.CalledProcessError(23, ["uv"]), KeyboardInterrupt()):

            def fail_uv(argv, _error=error, **kwargs):
                if argv[0] == "uv":
                    raise _error
                return self.run_command(argv, **kwargs)

            self.run.reset_mock()
            self.run.side_effect = fail_uv
            with self.assertRaises(type(error)):
                workspace.setup(self.target)
            self.assertEqual([c.args[0][0] for c in self.run.call_args_list], ["git", "uv"])


if __name__ == "__main__":
    unittest.main()
