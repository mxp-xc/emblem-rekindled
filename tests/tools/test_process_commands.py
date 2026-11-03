"""External tools receive their native argv and preserve transport/error contracts."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from emblem_dev.commands import first_battle as playtest_first_battle
from emblem_dev.content import chapter1 as import_chapter_1
from emblem_dev.content import configuration as chapter_configuration
from emblem_dev.qa import client as android_playtest


class ProcessCommandsTest(unittest.TestCase):
    def test_adb_preserves_custom_executable_serial_binary_io_and_timeout(self):
        client = android_playtest.Playtest(serial="device-42", adb="/sdk with spaces/adb")
        data = b"\x00\xffrecord\r\n"
        result = subprocess.CompletedProcess([], 0, data, b"")
        with patch.object(android_playtest.subprocess, "run", return_value=result) as run:
            self.assertEqual(client.adb("exec-out", "cat", "file", data=data, timeout=2.5), data)
        run.assert_called_once_with(
            ["/sdk with spaces/adb", "-s", "device-42", "exec-out", "cat", "file"],
            input=data,
            capture_output=True,
            timeout=2.5,
            check=False,
        )

    def test_adb_without_serial_only_tolerates_explicit_missing_files(self):
        client = android_playtest.Playtest()
        with patch.object(android_playtest.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 1, b"", b"No such file or directory")
            self.assertEqual(client.adb("shell", "cat", "missing", check=False), b"")
            self.assertEqual(run.call_args.args[0], ["adb", "shell", "cat", "missing"])
            with self.assertRaisesRegex(RuntimeError, "No such file"):
                client.adb("shell", "cat", "missing")
            run.return_value = subprocess.CompletedProcess([], 1, b"", b"device offline")
            with self.assertRaisesRegex(RuntimeError, "device offline"):
                client.adb("shell", "cat", "missing", check=False)

    def test_import_command_preserves_paths_cwd_and_process_failure(self):
        work = Path("/work with spaces")
        command = ["/jdk with spaces/java", "-cp", "/a jar/emulator.jar", "ImportChapter1"]
        with patch.object(import_chapter_1.subprocess, "run") as run:
            import_chapter_1.run(Path(command[0]), *command[1:], cwd=work)
            run.assert_called_once_with(command, cwd=work, check=True)
            run.side_effect = subprocess.CalledProcessError(3, command)
            with self.assertRaises(subprocess.CalledProcessError):
                import_chapter_1.run(*command, cwd=work)

    def test_formatter_runs_bun_directly_and_keeps_failure_output(self):
        with tempfile.TemporaryDirectory() as directory:
            chapter = Path(directory) / "chapter with spaces"
            chapter.mkdir()
            generated = chapter / "chapter.json"
            generated.write_text('{"id":"chapter_1"}')
            root = chapter_configuration.ROOT
            with patch.object(chapter_configuration.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, "formatted", "")
                self.assertEqual(chapter_configuration.format_changed_json(chapter, {}), 1)
                run.assert_called_once_with(
                    [
                        "bun",
                        "x",
                        "prettier",
                        "--ignore-path",
                        chapter_configuration.os.devnull,
                        "--config",
                        str(root / ".prettierrc.json"),
                        "--write",
                        str(generated),
                    ],
                    cwd=root,
                    capture_output=True,
                    text=True,
                )
                run.return_value = subprocess.CompletedProcess([], 1, "partial\n", "failed\n")
                with self.assertRaisesRegex(RuntimeError, "Project JSON formatting failed"):
                    chapter_configuration.format_changed_json(chapter, {})
                self.assertEqual(
                    (chapter.parent / "format-error.log").read_text(), "partial\nfailed\n"
                )

    def test_planner_preserves_paths_timeout_and_parses_its_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "batch with spaces"
            output.mkdir()
            driver = playtest_first_battle.Run(Mock(), output)
            plan = {"commands": []}

            def respond(*_args, **_kwargs):
                (output / "plan.json").write_text(json.dumps(plan))
                return subprocess.CompletedProcess([], 0, "", "")

            with patch.object(playtest_first_battle.subprocess, "run", side_effect=respond) as run:
                self.assertEqual(driver.plan({"snapshot": {"round": 1}}), plan)
            run.assert_called_once_with(
                [
                    "godot",
                    "--headless",
                    "--path",
                    str(playtest_first_battle.GAME),
                    "--script",
                    str(playtest_first_battle.GODOT / "plan_first_battle.gd"),
                    "--",
                    str(output / "current.json"),
                    str(output / "assignments.json"),
                    str(output / "plan.json"),
                ],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertEqual(json.loads((output / "current.json").read_text()), {"round": 1})
            for code, stdout, stderr in ((1, "", "failed"), (0, "SCRIPT ERROR: invalid", "")):
                with (
                    self.subTest(code=code, stdout=stdout),
                    patch.object(
                        playtest_first_battle.subprocess,
                        "run",
                        return_value=subprocess.CompletedProcess([], code, stdout, stderr),
                    ),
                    self.assertRaises(RuntimeError),
                ):
                    driver.plan({"snapshot": {}})


if __name__ == "__main__":
    unittest.main()
