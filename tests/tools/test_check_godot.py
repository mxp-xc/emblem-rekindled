"""Exercise engine errors, reporting, timeouts, and owned-process cleanup."""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout, suppress
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from emblem_dev.checks import godot as check_godot
from emblem_dev.checks.godot import (
    configuration_lock,
    godot,
    isolated_project,
    restore_configuration,
)


class GodotFixtureTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="emblem-engine-fixture-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.game = self.directory / "game"
        self.game.mkdir()
        (self.game / "project.godot").write_text('[application]\nconfig/name="fixture"\n')
        game = patch("emblem_dev.checks.godot.GAME", self.game)
        game.start()
        self.addCleanup(game.stop)
        self.pid_file = self.directory / "process_id"
        self.executable = self.directory / "engine.py"
        self.addCleanup(self.cleanup_processes)
        popen = subprocess.Popen
        engine = patch(
            "emblem_dev.checks.godot.subprocess.Popen",
            side_effect=lambda command, **kwargs: popen(
                [sys.executable, str(self.executable), *command[1:]], **kwargs
            ),
        )
        engine.start()
        self.addCleanup(engine.stop)

    def cleanup_processes(self) -> None:
        if self.pid_file.exists():
            with suppress(ProcessLookupError):
                os.killpg(int(self.pid_file.read_text()), signal.SIGKILL)

    def write_fixture(self, source: str) -> None:
        self.executable.write_text(
            "import os, subprocess, sys, time\n"
            "from pathlib import Path\n"
            f"directory = Path({str(self.directory)!r})\n"
            "(directory / 'process_id').write_text(str(os.getpid()))\n" + source
        )

    def assert_owned_processes_stopped(self) -> None:
        process_ids = [int(self.pid_file.read_text())]
        child_file = self.directory / "child_id"
        if child_file.exists():
            process_ids.append(int(child_file.read_text()))
        for process_id in process_ids:
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                try:
                    os.kill(process_id, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.02)
            else:
                self.fail(f"Owned process {process_id} survived cleanup")

    def test_engine_error_fails_quickly_and_retains_delayed_stack(self) -> None:
        self.write_fixture(
            "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
            "(directory / 'child_id').write_text(str(child.pid))\n"
            "print('SCRIPT ERROR: fixture runtime fault', file=sys.stderr, flush=True)\n"
            "time.sleep(0.15)\n"
            "print('  at: delayed_trace (fixture.gd:12) 中文', file=sys.stderr, flush=True)\n"
            "time.sleep(0.03)\n"
            "print('  at: caller (fixture.gd:20)', file=sys.stderr, flush=True)\n"
            "time.sleep(60)\n"
        )
        errors = StringIO()
        started = time.monotonic()
        with self.assertRaises(SystemExit) as failure, redirect_stderr(errors):
            godot("--script", "fixture.gd", timeout_seconds=1.2)
        elapsed = time.monotonic() - started
        self.assertEqual(failure.exception.code, 1)
        self.assertLess(elapsed, 0.8, f"Engine error took {elapsed:.3f}s")
        self.assertIn("SCRIPT ERROR: fixture runtime fault", errors.getvalue())
        self.assertIn("delayed_trace (fixture.gd:12) 中文", errors.getvalue())
        self.assertIn("caller (fixture.gd:20)", errors.getvalue())
        self.assertNotIn("timed out", errors.getvalue())
        self.assert_owned_processes_stopped()

    def test_warning_preserves_successful_pass_report(self) -> None:
        self.write_fixture(
            "print('WARNING: harmless fixture warning', file=sys.stderr, flush=True)\n"
            "print('PASS first check', flush=True)\n"
            "time.sleep(0.35)\n"
            "print('PASS completed after warning', flush=True)\n"
        )
        output, errors = StringIO(), StringIO()
        with redirect_stdout(output), redirect_stderr(errors):
            godot("--script", "fixture.gd", timeout_seconds=1)
        self.assertEqual(output.getvalue(), "PASS first check\nPASS completed after warning\n")
        self.assertEqual(errors.getvalue(), "")
        self.assert_owned_processes_stopped()

    def test_success_without_pass_preserves_ok_report(self) -> None:
        self.write_fixture("print('Godot fixture banner')\n")
        output = StringIO()
        with redirect_stdout(output):
            godot("--quit-after", "5", timeout_seconds=1)
        self.assertEqual(output.getvalue(), "OK --quit-after 5\n")

    def test_nonzero_exit_preserves_failure_status_and_output(self) -> None:
        self.write_fixture("print('fixture exit diagnostic', flush=True)\nsys.exit(7)\n")
        errors = StringIO()
        with self.assertRaises(SystemExit) as failure, redirect_stderr(errors):
            godot(timeout_seconds=1)
        self.assertEqual(failure.exception.code, 7)
        self.assertIn("fixture exit diagnostic", errors.getvalue())

    def test_split_engine_error_fails_during_startup(self) -> None:
        self.write_fixture(
            "print('ERR', end='', file=sys.stderr, flush=True)\n"
            "time.sleep(0.15)\n"
            "print('OR: fixture startup fault', file=sys.stderr, flush=True)\n"
            "time.sleep(60)\n"
        )
        errors = StringIO()
        started = time.monotonic()
        with self.assertRaises(SystemExit) as failure, redirect_stderr(errors):
            godot(ready_file=self.directory / "ready", timeout_seconds=1.2, startup_seconds=1.2)
        self.assertLess(time.monotonic() - started, 0.8)
        self.assertEqual(failure.exception.code, 1)
        self.assertIn("ERROR: fixture startup fault", errors.getvalue())
        self.assertNotIn("timed out", errors.getvalue())
        self.assert_owned_processes_stopped()

    def test_error_cleans_child_when_parent_exits_during_drain(self) -> None:
        self.write_fixture(
            "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], "
            "stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
            "(directory / 'child_id').write_text(str(child.pid))\n"
            "print('ERROR: fixture fault before exit', flush=True)\n"
            "time.sleep(0.15)\n"
            "sys.exit(7)\n"
        )
        with self.assertRaises(SystemExit) as failure, redirect_stderr(StringIO()):
            godot(timeout_seconds=1.2)
        self.assertEqual(failure.exception.code, 7)
        self.assert_owned_processes_stopped()

    def test_success_cleans_child_after_parent_exits(self) -> None:
        self.write_fixture(
            "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], "
            "stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n"
            "(directory / 'child_id').write_text(str(child.pid))\n"
            "print('PASS fixture completed', flush=True)\n"
        )
        with redirect_stdout(StringIO()):
            godot(timeout_seconds=1)
        self.assert_owned_processes_stopped()

    def test_runtime_timeout_retains_output_and_cleans_owned_group(self) -> None:
        self.write_fixture(
            "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
            "(directory / 'child_id').write_text(str(child.pid))\n"
            "print('fixture still running 中文', flush=True)\n"
            "time.sleep(60)\n"
        )
        errors = StringIO()
        started = time.monotonic()
        with self.assertRaises(SystemExit) as failure, redirect_stderr(errors):
            godot("--script", "fixture.gd", timeout_seconds=0.25)
        self.assertGreaterEqual(time.monotonic() - started, 0.23)
        self.assertEqual(failure.exception.code, 1)
        self.assertIn("fixture still running 中文", errors.getvalue())
        self.assertIn("Godot runtime timed out: --script fixture.gd", errors.getvalue())
        self.assert_owned_processes_stopped()

    def test_ready_file_uses_startup_timeout_before_engine_is_ready(self) -> None:
        self.write_fixture("print('fixture starting', flush=True)\ntime.sleep(60)\n")
        errors = StringIO()
        started = time.monotonic()
        with self.assertRaises(SystemExit) as failure, redirect_stderr(errors):
            godot(ready_file=self.directory / "ready", timeout_seconds=0.05, startup_seconds=0.25)
        self.assertGreaterEqual(time.monotonic() - started, 0.23)
        self.assertEqual(failure.exception.code, 1)
        self.assertIn("Godot startup timed out:", errors.getvalue())
        self.assert_owned_processes_stopped()

    def test_ready_file_starts_full_runtime_timeout_after_startup(self) -> None:
        self.write_fixture(
            "time.sleep(0.2)\n"
            "(directory / 'ready').touch()\n"
            "print('fixture ready', flush=True)\n"
            "time.sleep(60)\n"
        )
        errors = StringIO()
        started = time.monotonic()
        with self.assertRaises(SystemExit) as failure, redirect_stderr(errors):
            godot(ready_file=self.directory / "ready", timeout_seconds=0.25, startup_seconds=0.8)
        self.assertGreaterEqual(time.monotonic() - started, 0.43)
        self.assertEqual(failure.exception.code, 1)
        self.assertIn("fixture ready", errors.getvalue())
        self.assertIn("Godot runtime timed out:", errors.getvalue())
        self.assert_owned_processes_stopped()


class GodotIsolationTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="emblem-isolation-")
        self.addCleanup(temporary.cleanup)
        self.game = Path(temporary.name)
        self.project = self.game / "project.godot"
        self.original = (
            b'config_version=5\r\n[application]\r\nconfig/name="fixture"\r\n'
            b"config/use_custom_user_dir=true\r\n"
            b'config/custom_user_dir_name="normal-records"\r\n'
        )
        self.project.write_bytes(self.original)
        game = patch("emblem_dev.checks.godot.GAME", self.game)
        game.start()
        self.addCleanup(game.stop)

    def test_nested_isolation_reuses_identity_and_restores_exact_bytes(self) -> None:
        with isolated_project():
            isolated = self.project.read_bytes()
            self.assertIn(b'config/name="emblem-check-', isolated)
            self.assertIn(b"config/use_custom_user_dir=false", isolated)
            with isolated_project():
                self.assertEqual(self.project.read_bytes(), isolated)
            self.assertEqual(self.project.read_bytes(), isolated)
        self.assertEqual(self.project.read_bytes(), self.original)

    def test_exception_and_interrupt_restore_configuration(self) -> None:
        for error in (RuntimeError("fixture"), KeyboardInterrupt(), SystemExit(7)):
            with self.subTest(error=type(error)), self.assertRaises(type(error)):
                with isolated_project():
                    raise error
            self.assertEqual(self.project.read_bytes(), self.original)

    def test_concurrent_owner_is_rejected_before_configuration_write(self) -> None:
        import fcntl

        (self.game / ".godot").mkdir()
        with (self.game / ".godot/check.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(RuntimeError, "Another Godot check"):
                with isolated_project():
                    self.fail("Concurrent owner entered isolated project")
        self.assertEqual(self.project.read_bytes(), self.original)

    def test_invalid_configuration_fails_without_rewriting(self) -> None:
        self.project.write_bytes(b"[application]\n")
        with self.assertRaisesRegex(RuntimeError, "Expected one config/name"):
            with isolated_project():
                self.fail("Missing project identity was accepted")
        self.assertEqual(self.project.read_bytes(), b"[application]\n")

    def test_changed_configuration_is_preserved_with_recovery_evidence(self) -> None:
        changed_by_user = b"user changed configuration\n"
        with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
            with isolated_project():
                evidence = self.game / ".godot/check-recovery"
                self.assertEqual((evidence / "original.godot").read_bytes(), self.original)
                owner = json.loads((evidence / "owner.json").read_text())
                self.assertEqual(owner["pid"], os.getpid())
                self.project.write_bytes(changed_by_user)
        self.assertEqual(self.project.read_bytes(), changed_by_user)
        with self.assertRaisesRegex(RuntimeError, "Unfinished Godot check"):
            with isolated_project():
                self.fail("Stale recovery evidence was ignored")
        with configuration_lock() as evidence:
            with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
                restore_configuration(evidence)
            # Simulate the user first resolving their edits to the retained isolated copy.
            self.project.write_bytes((evidence / "isolated.godot").read_bytes())
            restore_configuration(evidence)
        self.assertEqual(self.project.read_bytes(), self.original)
        self.assertFalse(evidence.exists())

    def test_engine_start_failure_restores_configuration(self) -> None:
        with (
            patch("emblem_dev.checks.godot.subprocess.Popen", side_effect=FileNotFoundError),
            self.assertRaises(FileNotFoundError),
        ):
            godot()
        self.assertEqual(self.project.read_bytes(), self.original)
        self.assertFalse((self.game / ".godot/check-recovery").exists())

    def test_interrupted_recovery_requires_inactive_owner_and_retains_original(self) -> None:
        # Reproduce the on-disk state left by an uncatchable process termination.
        with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
            with isolated_project():
                evidence = self.game / ".godot/check-recovery"
                isolated = self.project.read_bytes()
                self.project.write_bytes(b"later edit\n")
        self.project.write_bytes(isolated)
        with configuration_lock() as evidence:
            with self.assertRaisesRegex(RuntimeError, "still alive"):
                restore_configuration(evidence, require_inactive_owner=True)
            self.assertEqual(self.project.read_bytes(), isolated)
            with patch("emblem_dev.checks.godot.os.kill", side_effect=ProcessLookupError):
                restore_configuration(evidence, require_inactive_owner=True)
        self.assertEqual(self.project.read_bytes(), self.original)
        self.assertFalse(evidence.exists())

    def test_invalid_test_name_is_rejected_before_configuration_write(self) -> None:
        with self.assertRaisesRegex(ValueError, "not a path"):
            check_godot.check(tests=("../test_fixture.gd",))
        self.assertEqual(self.project.read_bytes(), self.original)
        self.assertFalse((self.game / ".godot/check-recovery").exists())

    def test_requested_tests_keep_source_order_without_import(self) -> None:
        with patch("emblem_dev.checks.godot.godot") as engine, redirect_stdout(StringIO()):
            self.assertEqual(check_godot.check(tests=("test_second.gd", "test_first.gd")), 0)
        self.assertEqual(
            [call.args for call in engine.call_args_list],
            [("--script", "tests/test_second.gd"), ("--script", "tests/test_first.gd")],
        )
        self.assertEqual(self.project.read_bytes(), self.original)

    def test_parse_uses_canonical_resource_and_stops_before_behavior_tests(self) -> None:
        with patch("emblem_dev.checks.godot.godot") as engine, redirect_stdout(StringIO()):
            self.assertEqual(check_godot.check(parse_only=True), 0)
        self.assertEqual(engine.call_count, 2)
        self.assertEqual(engine.call_args_list[0].args, ("--editor", "--import"))
        self.assertEqual(
            engine.call_args_list[1].args[:3],
            ("--script", str(check_godot.GODOT / "parse_scripts.gd"), "--"),
        )
        self.assertEqual(self.project.read_bytes(), self.original)

    def test_cli_timings_record_failed_test_and_restore_configuration(self) -> None:
        timings = self.game / "timings.json"
        with (
            patch("emblem_dev.checks.godot.godot", side_effect=SystemExit(7)),
            redirect_stdout(StringIO()),
            self.assertRaises(SystemExit),
        ):
            check_godot.check(tests=("test_fixture.gd",), timings=timings)
        result = json.loads(timings.read_text())
        self.assertNotEqual(result["exitCode"], 0)
        self.assertEqual(result["intervals"][0]["name"], "test_fixture.gd")
        self.assertFalse(result["intervals"][0]["finished"])
        self.assertEqual(self.project.read_bytes(), self.original)


class GodotGateTest(unittest.TestCase):
    def test_runtime_fault_returns_failure_within_timeout(self) -> None:
        with tempfile.TemporaryDirectory(prefix="emblem-bad-script-") as directory:
            game = Path(directory) / "game"
            game.mkdir()
            (game / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="fixture"\n'
            )
            game_patch = patch("emblem_dev.checks.godot.GAME", game)
            game_patch.start()
            self.addCleanup(game_patch.stop)
            script = Path(directory) / "bad.gd"
            pid_file = Path(directory) / "process_id"
            script.write_text(
                "extends SceneTree\n"
                "func _initialize() -> void:\n"
                f"\tvar file := FileAccess.open({json.dumps(str(pid_file))}, FileAccess.WRITE)\n"
                "\tfile.store_string(str(OS.get_process_id()))\n"
                "\tfile.close()\n"
                "\tvar missing: Variant = null\n"
                '\tmissing.call("invalid")\n'
            )
            with self.assertRaises(SystemExit) as failure, redirect_stderr(StringIO()):
                godot("--script", str(script), timeout_seconds=0.2, ready_file=pid_file)
            self.assertEqual(failure.exception.code, 1)
            process_id = int(pid_file.read_text())
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                try:
                    os.kill(process_id, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.02)
            else:
                self.fail(f"Godot process {process_id} survived timeout cleanup")


if __name__ == "__main__":
    unittest.main()
