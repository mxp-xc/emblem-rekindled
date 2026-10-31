"""Exercise the CLI gate against a real Godot runtime fault which does not exit."""

import json
import os
import tempfile
import time
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path

from check_godot import godot


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
                godot("--script", str(script), timeout_seconds=1)
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
