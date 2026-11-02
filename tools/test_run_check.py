"""Verify structured check timing without launching the project checks."""

import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from run_check import run


class TimedCheckTest(unittest.TestCase):
    def test_success_runs_each_phase_once_and_includes_engine_intervals(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "check"

            def execute(command, **kwargs):
                kwargs["stdout"].write("fixture output\n")
                if command[-1] == "test:game":
                    Path(kwargs["env"]["EMBLEM_CHECK_TIMINGS"]).write_text(
                        json.dumps({"intervals": [{"name": "test_fixture.gd", "finished": True}]})
                    )
                return subprocess.CompletedProcess(command, 0)

            with (
                patch("run_check.subprocess.run", side_effect=execute) as calls,
                redirect_stdout(StringIO()),
            ):
                self.assertEqual(run(output), 0)
            self.assertEqual(
                [call.args[0][-1] for call in calls.call_args_list],
                ["lint", "test:tools", "test:game"],
            )
            result = json.loads((output / "timings.json").read_text())
            self.assertEqual(result["exitCode"], 0)
            self.assertEqual(result["godot"]["intervals"][0]["name"], "test_fixture.gd")
            self.assertEqual(
                (output / "integrated-check.log").read_text().count("fixture output"), 3
            )

    def test_failure_retains_status_and_does_not_run_later_stages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "check"
            with (
                patch(
                    "run_check.subprocess.run", return_value=subprocess.CompletedProcess([], 7)
                ) as calls,
                redirect_stdout(StringIO()),
            ):
                self.assertEqual(run(output), 7)
            self.assertEqual(calls.call_count, 1)
            result = json.loads((output / "timings.json").read_text())
            self.assertEqual(result["exitCode"], 7)
            self.assertFalse(result["intervals"][0]["finished"])

    def test_exception_preserves_incomplete_interval(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "check"
            with (
                patch("run_check.subprocess.run", side_effect=KeyboardInterrupt),
                redirect_stdout(StringIO()),
                self.assertRaises(KeyboardInterrupt),
            ):
                run(output)
            result = json.loads((output / "timings.json").read_text())
            self.assertNotEqual(result["exitCode"], 0)
            self.assertFalse(result["intervals"][0]["finished"])

    def test_existing_evidence_is_never_replaced(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileExistsError):
                run(Path(directory))


if __name__ == "__main__":
    unittest.main()
