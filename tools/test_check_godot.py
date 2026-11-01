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

from check_godot import godot


class GodotFixtureTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="emblem-engine-fixture-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.pid_file = self.directory / "process_id"
        self.executable = self.directory / "engine.py"
        self.addCleanup(self.cleanup_processes)
        popen = subprocess.Popen
        engine = patch(
            "check_godot.subprocess.Popen",
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


class GodotGateTest(unittest.TestCase):
    def test_runtime_fault_returns_failure_within_timeout(self) -> None:
        with tempfile.TemporaryDirectory(prefix="emblem-bad-script-") as directory:
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
