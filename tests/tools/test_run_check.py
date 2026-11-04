"""Verify native stages, failure status, and timing evidence without real checks."""

import json
import tempfile
import threading
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from emblem_dev.checks import pipeline


class TimedCheckTest(unittest.TestCase):
    def test_success_runs_each_phase_once_and_includes_engine_intervals(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "check"
            order = []

            def phase(name):
                order.append(name)
                print("fixture output")
                return 0

            def game(*, timings):
                timings.write_text(
                    json.dumps({"intervals": [{"name": "test_fixture.gd", "finished": True}]})
                )
                return phase("game")

            with (
                patch.object(pipeline, "lint", side_effect=lambda: phase("lint")),
                patch.object(pipeline, "tools", side_effect=lambda: phase("tools")),
                patch.object(pipeline.godot, "check", side_effect=game),
                redirect_stdout(StringIO()),
            ):
                self.assertEqual(pipeline.check("full", output), 0)
            self.assertEqual(order, ["lint", "tools", "game"])
            result = json.loads((output / "timings.json").read_text())
            self.assertEqual(result["exitCode"], 0)
            self.assertEqual(result["godot"]["intervals"][0]["name"], "test_fixture.gd")
            self.assertEqual(
                (output / "integrated-check.log").read_text().count("fixture output"), 3
            )

    def test_quick_has_no_engine_stage(self):
        with (
            patch.object(pipeline, "lint", return_value=0),
            patch.object(pipeline, "tools", return_value=0),
            patch.object(pipeline.godot, "check") as game,
            redirect_stdout(StringIO()),
        ):
            self.assertEqual(pipeline.check(), 0)
        game.assert_not_called()

    def test_failure_retains_status_and_stops_later_stages(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "check"
            with (
                patch.object(pipeline, "lint", return_value=7),
                patch.object(pipeline, "tools") as tools,
                redirect_stdout(StringIO()),
            ):
                self.assertEqual(pipeline.check("full", output), 7)
            tools.assert_not_called()
            result = json.loads((output / "timings.json").read_text())
            self.assertEqual(result["exitCode"], 7)
            self.assertFalse(result["intervals"][0]["finished"])

    def test_interrupt_preserves_incomplete_interval(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "check"
            with (
                patch.object(pipeline, "lint", side_effect=KeyboardInterrupt),
                redirect_stdout(StringIO()),
                self.assertRaises(KeyboardInterrupt),
            ):
                pipeline.check("full", output)
            result = json.loads((output / "timings.json").read_text())
            self.assertEqual(result["exitCode"], 130)
            self.assertFalse(result["intervals"][0]["finished"])

    def test_engine_failure_retains_status(self):
        with (
            patch.object(pipeline, "lint", return_value=0),
            patch.object(pipeline, "tools", return_value=0),
            patch.object(pipeline.godot, "check", side_effect=SystemExit(7)),
            redirect_stdout(StringIO()),
        ):
            self.assertEqual(pipeline.check("full"), 7)

    def test_existing_evidence_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(FileExistsError):
            pipeline.check("full", Path(directory))

    def test_lint_uses_external_programs_and_native_helper(self):
        with (
            patch.object(pipeline, "run", return_value=0) as run,
            patch.object(pipeline.helpers, "check", return_value=0) as helper,
        ):
            self.assertEqual(pipeline.lint(), 0)
        helper.assert_called_once()
        programs = [Path(call.args[0][0]).name for call in run.call_args_list]
        self.assertCountEqual(programs, ["gdlint", "gdformat", "ruff", "ruff", "prettier"])
        self.assertFalse(
            any(
                "python" in item or item == "bun"
                for call in run.call_args_list
                for item in call.args[0]
            )
        )

    def test_tools_run_every_discovered_file_and_report_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            tests = Path(directory)
            (tests / "test_first.py").touch()
            (tests / "test_second.py").touch()
            (tests / "not_a_package").mkdir()
            (tests / "not_a_package/test_ignored.py").touch()
            (tests / "package").mkdir()
            (tests / "package/__init__.py").touch()
            (tests / "package/test_nested.py").touch()
            calls = []

            def fake_run(command, *, cwd, stdout):
                pattern = command[-1]
                calls.append(pattern)
                stdout.write(f"ran {pattern}\n")
                return 1 if pattern == "test_second.py" else 0

            output = StringIO()
            with (
                patch.object(pipeline, "TESTS", tests),
                patch.object(pipeline, "run", side_effect=fake_run),
                redirect_stdout(output),
            ):
                self.assertEqual(pipeline.tools(), 1)
            self.assertCountEqual(calls, ["test_first.py", "test_second.py", "test_nested.py"])
            self.assertIn("ran test_first.py", output.getvalue())
            self.assertIn("ran test_second.py", output.getvalue())

    def test_helper_check_overlaps_read_only_format_checks(self):
        formatter_started = threading.Event()

        def helper(_game):
            return 0 if formatter_started.wait(timeout=2) else 7

        def command(_command, *, cwd, stdout):
            formatter_started.set()
            return 0

        with (
            patch.object(pipeline.helpers, "check", side_effect=helper),
            patch.object(pipeline, "run", side_effect=command),
        ):
            self.assertEqual(pipeline.lint(), 0)


if __name__ == "__main__":
    unittest.main()
