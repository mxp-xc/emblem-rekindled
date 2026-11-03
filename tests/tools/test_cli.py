"""Public command contracts, native operations, and interruption cleanup."""

import contextlib
import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from unittest.mock import MagicMock, Mock, patch

from emblem_dev import cli, delivery, workspace
from emblem_dev.checks import godot, pipeline
from emblem_dev.commands import build, first_battle, qa, root, verify
from emblem_dev.commands import workspace as workspace_commands
from emblem_dev.content import chapter1, configuration
from emblem_dev.paths import ROOT
from emblem_dev.qa import android, client
from typer.testing import CliRunner


class NativeCliTest(unittest.TestCase):
    def setUp(self):
        self.runner = CliRunner()
        temporary = tempfile.TemporaryDirectory(prefix="emblem-native-cli-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name).resolve()

    def invoke(self, *args):
        return self.runner.invoke(cli.app, list(args))

    def test_help_needs_no_checkout_or_environment_and_runs_no_business(self):
        with contextlib.chdir(self.directory), patch.object(workspace_commands, "status") as status:
            commands = (
                (),
                ("workspace",),
                ("check",),
                ("qa",),
                ("qa", "state"),
                ("build",),
                ("verify",),
                ("import",),
                ("setup",),
                ("serve",),
                ("source-context",),
                ("qa", "android"),
                ("check", "game"),
                ("import", "chapter-1"),
            )
            for command in commands:
                args = (*command, "--help")
                result = self.runner.invoke(cli.app, args)
                self.assertEqual(result.exit_code, 0, result.output)
            status.assert_not_called()
            self.assertEqual(list(self.directory.iterdir()), [])

    def test_repeated_tests_and_paths_call_native_godot_and_propagate_failure(self):
        with patch.object(godot, "check", return_value=7) as check:
            result = self.invoke(
                "check",
                "game",
                "--test",
                "first.gd",
                "--test",
                "second.gd",
                "--tests-only",
                "--timings",
                "batch with spaces/time.json",
            )
            self.assertEqual(result.exit_code, 7, result.output)
            check.assert_called_once_with(
                tests=["first.gd", "second.gd"],
                tests_only=True,
                timings=Path("batch with spaces/time.json"),
            )

    def test_game_jobs_are_forwarded(self):
        with patch.object(godot, "check", return_value=0) as check:
            result = self.invoke("check", "game", "--jobs", "2", "--test", "test_first.gd")
        self.assertEqual(result.exit_code, 0, result.output)
        check.assert_called_once_with(
            tests=["test_first.gd"], tests_only=False, timings=None, jobs=2
        )

    def test_invalid_parameters_stop_before_business(self):
        with patch.object(godot, "check") as check:
            for args in (
                ("check", "game", "--unknown"),
                ("check", "game", "--test"),
                ("serve", "--port", "wrong"),
                ("run", "arbitrary.py"),
            ):
                result = self.invoke(*args)
                self.assertEqual(result.exit_code, 2, result.output)
            check.assert_not_called()

    def test_workspace_default_and_explicit_target(self):
        with patch.object(workspace_commands, "status") as status:
            self.assertEqual(self.invoke("workspace").exit_code, 0)
            status.assert_called_once_with()
        with patch.object(workspace, "setup") as setup:
            result = self.invoke("workspace", "init", "other checkout", "--hooks")
            self.assertEqual(result.exit_code, 0, result.output)
            setup.assert_called_once_with(Path("other checkout"), hooks=True)

    def test_check_phases_are_native_and_full_preserves_output(self):
        with patch.object(pipeline, "check", return_value=4) as check:
            result = self.invoke("check", "full", "--output", "new batch")
            self.assertEqual(result.exit_code, 4)
            check.assert_called_once_with("full", output=Path("new batch"))
        with patch.object(pipeline, "tools", return_value=0) as tools:
            self.assertEqual(self.invoke("check", "tools").exit_code, 0)
            tools.assert_called_once_with()

    def test_flattened_root_commands_preserve_parameters_and_native_calls(self):
        with patch.object(workspace, "setup") as setup:
            result = self.invoke("setup", "--hooks")
            self.assertEqual(result.exit_code, 0, result.output)
            setup.assert_called_once_with(hooks=True)
        web = self.directory / "build/web"
        web.mkdir(parents=True)
        (web / "index.html").touch()
        with (
            patch.object(root, "ROOT", self.directory),
            patch.object(root, "ThreadingHTTPServer") as server,
        ):
            result = self.invoke("serve", "--port", "8877")
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertEqual(server.call_args.args[0], ("127.0.0.1", 8877))
            server.return_value.__enter__.return_value.serve_forever.assert_called_once_with()
        source = self.directory / "source with spaces.js"
        source.write_text("prefix needle suffix")
        result = self.invoke(
            "source-context", str(source), "needle", "--radius", "2", "--limit", "1"
        )
        self.assertEqual(result.exit_code, 0, result.output)
        self.assertEqual(result.output, "offset 7: x needle s\n")

    def test_build_and_verify_groups_preserve_native_targets_and_paths(self):
        for platform in ("web", "android"):
            with self.subTest(platform=platform), patch.object(build, "export") as export:
                result = self.invoke("build", platform)
                self.assertEqual(result.exit_code, 0, result.output)
                export.assert_called_once_with(platform)
        tpz = self.directory / "template archive.tpz"
        with zipfile.ZipFile(tpz, "w") as archive:
            for name in build.FILES:
                archive.writestr(
                    "templates/" + name, "4.7.2.stable" if name == "version.txt" else name
                )
        with (
            patch.object(build, "ROOT", self.directory),
            patch.object(build.hashlib, "file_digest") as digest,
        ):
            digest.return_value.hexdigest.return_value = build.TEMPLATE_SHA
            result = self.invoke("build", "templates", str(tpz))
            self.assertEqual(result.exit_code, 0, result.output)
        self.assertEqual(
            {p.name for p in (self.directory / "build/templates/4.7.2.stable").iterdir()},
            set(build.FILES),
        )
        with patch.object(delivery, "verify_android") as check:
            result = self.invoke("verify", "android", "--serial", "fixture", "--apk", "current.apk")
            self.assertEqual(result.exit_code, 0, result.output)
            check.assert_called_once_with(serial="fixture", apk=Path("current.apk"))

    def test_verify_web_uses_selected_origin_and_shared_pack_verification(self):
        web = self.directory / "build/web"
        web.mkdir(parents=True)
        (web / "build-info.json").write_text('{"buildId":"fixture"}')
        html, pack = MagicMock(), MagicMock()
        for response in (html, pack):
            response.__enter__.return_value = response
            response.headers = {"Cache-Control": "no-store"}
        html.read.return_value = b'<base href="./fixture/">'
        pack.read.side_effect = [b"fixture pack", b""]
        with (
            patch.object(verify, "ROOT", self.directory),
            patch.object(verify, "urlopen", side_effect=[html, pack]) as fetch,
            patch.object(delivery, "verify_pack") as check,
        ):
            result = self.invoke("verify", "web", "--origin", "http://127.0.0.1:8877")
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertEqual(
                [call.args[0] for call in fetch.call_args_list],
                ["http://127.0.0.1:8877/", "http://127.0.0.1:8877/fixture/index.pck"],
            )
            self.assertEqual(check.call_args.args[0].name, "index.pck")
            self.assertEqual(check.call_args.args[1], "fixture")

    def test_android_batch_requires_explicit_case_and_preserves_options(self):
        fixtures = self.directory / "fixtures"
        fixtures.mkdir()
        (fixtures / "fixtures.json").write_text('{"fixture":true}')
        (fixtures / "manifest.json").write_text('{"expected":true}')
        module = self.directory / "case.py"
        module.write_text("CASES = {'a': None, 'b': None}\n")
        with (
            patch.object(qa, "Playtest") as device,
            patch.object(android, "Flow") as flow,
            patch.object(android, "run_cases") as run,
        ):
            result = self.invoke(
                "qa",
                "android",
                "--apk",
                "package.apk",
                "--build",
                "id",
                "--fixtures",
                str(fixtures),
                "--cases",
                str(module),
                "--case",
                "a",
                "--case",
                "b",
                "--output",
                "evidence",
                "--serial",
                "device",
                "--stop-emulator",
            )
            self.assertEqual(result.exit_code, 0, result.output)
            device.assert_called_once_with("device", "adb")
            flow.assert_called_once_with(
                device.return_value, Path("evidence"), {"fixture": True}, {"expected": True}, "id"
            )
            run.assert_called_once_with(
                flow.return_value,
                ["a", "b"],
                {"a": None, "b": None},
                Path("package.apk"),
                stop_emulator=True,
            )

    def test_state_and_import_emit_structured_business_results(self):
        with patch.object(client, "Playtest") as device:
            read = device.return_value.read
            read.return_value = {"ready": True}
            result = self.invoke("qa", "state", "read", "--ready", "--serial", "fixture")
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertEqual(json.loads(result.output), {"ready": True})
            device.assert_called_once_with("fixture", "adb")
            read.assert_called_once_with(ready=True, timeout=30)
        chapter = self.directory / "chapter"
        (chapter / "authored/battles").mkdir(parents=True)
        (chapter / "authored/battles/m13.json").touch()
        with (
            patch.object(configuration, "normalize_deployment"),
            patch("emblem_dev.content.definitions.read_deployment"),
            patch.object(chapter1, "update_chapter", return_value={"contexts": []}) as importer,
        ):
            result = self.invoke(
                "import",
                "chapter-1",
                "--battle",
                "m13",
                "--emulator",
                "emulator.jar",
                "--chapter",
                str(chapter),
                "--native-input",
                "one",
                "--native-input",
                "two",
            )
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertEqual(json.loads(result.output), {"contexts": []})
            self.assertEqual(importer.call_args.args[5], [Path("one"), Path("two")])

    def test_first_battle_keeps_existing_natural_regression_options(self):
        apk = self.directory / "current.apk"
        with zipfile.ZipFile(apk, "w") as archive:
            archive.writestr("assets/content/build_info.json", json.dumps({"buildId": "fixed"}))
        play = Mock(journal=[], saves=0)
        play.play.return_value = {"world": {"gold": 6000, "route": 0}, "speed": 1}
        with (
            patch.object(first_battle, "ROOT", self.directory),
            patch.object(first_battle, "Playtest") as device,
            patch.object(first_battle, "Run", return_value=play),
            patch.object(first_battle, "install_captured_apk") as check,
            patch.object(first_battle, "record_session") as protection,
        ):
            protection.return_value.__enter__.return_value = {"restoreSeconds": 0.0}
            device.return_value.adb.return_value = b""
            result = self.invoke(
                "qa",
                "first-battle",
                "--speed",
                "1",
                "--serial",
                "fixture",
                "--apk",
                str(apk),
                "--keep-emulator",
            )
            self.assertEqual(result.exit_code, 0, result.output)
            device.assert_called_once_with("fixture")
            self.assertEqual(check.call_args.args[1], apk)
            self.assertEqual(check.call_args.args[3], "fixed")
            play.play.assert_called_once_with(1)
            self.assertNotIn((("emu", "kill"), {}), device.return_value.adb.call_args_list)

    def test_speed_parameters_reject_unsupported_values_before_business(self):
        with (
            patch.object(first_battle, "Playtest") as play,
            patch.object(client, "Playtest") as device,
        ):
            for value in ("0", "3", "64"):
                for args in (
                    ("qa", "first-battle", "--speed", value),
                    ("qa", "state", "speed", value),
                ):
                    with self.subTest(args=args):
                        result = self.invoke(*args)
                        self.assertEqual(result.exit_code, 2, result.output)
            play.assert_not_called()
            device.assert_not_called()

    def test_speed_help_and_valid_values_keep_public_contract(self):
        for args in (("qa", "first-battle", "--help"), ("qa", "state", "speed", "--help")):
            result = self.invoke(*args)
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertIn("(1,2,4,8,16,32)", result.output)
        for value in (1, 2, 4, 8, 16, 32):
            with (
                self.subTest(speed=value),
                patch.object(first_battle, "Playtest", side_effect=ValueError("parsed")) as play,
            ):
                result = self.invoke("qa", "first-battle", "--speed", str(value))
                self.assertEqual(result.exit_code, 1, result.output)
                self.assertEqual(str(result.exception), "parsed")
                play.assert_called_once_with(None)
            with (
                self.subTest(speed=value),
                patch.object(client, "Playtest"),
                patch.object(client, "AndroidInput") as inputs,
            ):
                inputs.return_value.set_speed.return_value = {}
                result = self.invoke("qa", "state", "speed", str(value))
                self.assertEqual(result.exit_code, 0, result.output)
                inputs.return_value.set_speed.assert_called_once_with(value)

    def test_main_formats_usage_and_operational_failures_with_exit_status(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(cli.main(["serve", "--invalid"]), 2)
            with patch.object(root, "ROOT", self.directory):
                self.assertEqual(cli.main(["serve"]), 1)
            with patch.object(godot, "check", return_value=9):
                self.assertEqual(cli.main(["check", "game"]), 9)

    def test_real_signals_unwind_native_finally_and_remove_owned_external_processes(self):
        # Python is only a fixture substitute for an external engine executable.
        game = self.directory / "game"
        game.mkdir()
        project = game / "project.godot"
        original = b'config_version=5\r\n[application]\r\nconfig/name="cli-fixture"\r\n'
        project.write_bytes(original)
        ready = self.directory / "ready.json"
        external = (
            "import json,os,subprocess,sys,time;from pathlib import Path;"
            "child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(60)']);"
            f"Path({str(ready)!r}).write_text(json.dumps([os.getpid(),child.pid]));"
            "time.sleep(60)"
        )
        code = f"""import sys, subprocess
from pathlib import Path
from emblem_dev import cli
from emblem_dev.checks import godot
godot.GAME = Path({str(game)!r})
popen = subprocess.Popen
godot.subprocess.Popen = lambda command, **kwargs: popen(
    [sys.executable, '-c', {external!r}], **kwargs)
sys.exit(cli.main(['check', 'game', '--test', 'test_fixture.gd']))
"""
        for signum, expected in ((signal.SIGINT, 130), (signal.SIGTERM, 143)):
            with self.subTest(signal=signum):
                ready.unlink(missing_ok=True)
                process = subprocess.Popen(
                    [sys.executable, "-c", code],
                    cwd=ROOT,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                pids = []
                try:
                    deadline = time.monotonic() + 5
                    while (
                        not ready.exists()
                        and process.poll() is None
                        and time.monotonic() < deadline
                    ):
                        time.sleep(0.01)
                    self.assertTrue(ready.exists(), "external fixture did not become ready")
                    self.assertNotEqual(project.read_bytes(), original)
                    pids = json.loads(ready.read_text())
                    os.kill(process.pid, signum)
                    _, stderr = process.communicate(timeout=10)
                    self.assertEqual(process.returncode, expected, stderr)
                    self.assertEqual(project.read_bytes(), original, stderr)
                    self.assertFalse((game / ".godot/check-recovery").exists(), stderr)
                    for pid in pids:
                        deadline = time.monotonic() + 3
                        while time.monotonic() < deadline:
                            try:
                                os.kill(pid, 0)
                            except ProcessLookupError:
                                break
                            time.sleep(0.01)
                        else:
                            self.fail(f"owned external process survived: {pid}")
                finally:
                    for pid in pids:
                        with contextlib.suppress(ProcessLookupError):
                            os.kill(pid, signal.SIGKILL)
                    if process.poll() is None:
                        process.kill()
                    process.communicate()


if __name__ == "__main__":
    unittest.main()
