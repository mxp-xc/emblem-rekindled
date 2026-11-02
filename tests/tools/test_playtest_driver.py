"""A completed game must not publish overall success when record recovery fails."""

import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch

from emblem_dev.commands import first_battle as playtest_first_battle
from emblem_dev.commands.state import state_read, state_speed
from emblem_dev.qa.client import AndroidInput, Playtest
from test_qa_records import Store


class PlaytestDriverTest(unittest.TestCase):
    def test_invalid_first_battle_speed_rejected_before_device_or_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "game.apk"
            apk.touch()
            for speed in (0, 3, -1):
                with (
                    self.subTest(speed=speed),
                    patch.object(playtest_first_battle, "ROOT", root),
                    patch.object(
                        playtest_first_battle,
                        "Playtest",
                        side_effect=AssertionError("device access"),
                    ) as client,
                    patch.object(playtest_first_battle, "verify_android") as verify,
                    self.assertRaisesRegex(ValueError, "Speed must be one of"),
                ):
                    playtest_first_battle.run_playtest(speed=speed, apk=apk)
                client.assert_not_called()
                verify.assert_not_called()
                self.assertEqual(list(root.iterdir()), [apk])

    def test_invalid_speed_rejected_before_device_or_game_input(self):
        for speed in (0, 3, -1):
            with self.subTest(speed=speed):
                with (
                    patch(
                        "emblem_dev.qa.client.Playtest", side_effect=AssertionError("device access")
                    ) as constructor,
                    self.assertRaisesRegex(ValueError, "Speed must be one of"),
                ):
                    state_speed(speed)
                constructor.assert_not_called()
                client = Mock()
                client.read.side_effect = AssertionError("game input")
                with self.assertRaisesRegex(ValueError, "Speed must be one of"):
                    AndroidInput(client).set_speed(speed)
                self.assertEqual(client.mock_calls, [])

    def test_native_queries_return_state_and_preserve_device_options(self):
        client = Mock()
        client.read.return_value = {"ready": True}
        with patch("emblem_dev.qa.client.Playtest", return_value=client) as constructor:
            output = StringIO()
            with redirect_stdout(output):
                state_read(serial="device", adb="/sdk/adb", ready=True, timeout=4.5)
            self.assertEqual(json.loads(output.getvalue()), {"ready": True})
        constructor.assert_called_once_with("device", "/sdk/adb")
        client.read.assert_called_once_with(ready=True, timeout=4.5)
        for speed in (1, 2, 4, 8, 16, 32):
            with (
                self.subTest(speed=speed),
                patch("emblem_dev.qa.client.Playtest", return_value=client),
                patch("emblem_dev.qa.client.AndroidInput") as inputs,
            ):
                inputs.return_value.set_speed.return_value = {"speed": speed}
                output = StringIO()
                with redirect_stdout(output):
                    state_speed(speed, serial="device")
                self.assertEqual(json.loads(output.getvalue()), {"speed": speed})
            inputs.assert_called_once_with(client)
            inputs.return_value.set_speed.assert_called_once_with(speed)

    def test_transport_deadline_is_reported_as_a_read_timeout(self):
        client = Playtest()
        client.adb = Mock(side_effect=subprocess.TimeoutExpired("adb", 0.2))
        with self.assertRaises(TimeoutError) as caught:
            client.read(timeout=0.2)
        self.assertIsInstance(caught.exception.__cause__, subprocess.TimeoutExpired)
        self.assertGreater(client.adb.call_args.kwargs["timeout"], 0)
        self.assertLessEqual(client.adb.call_args.kwargs["timeout"], 0.2)

    def test_read_waits_for_the_requested_ready_state(self):
        replies = [
            {"pending": True},
            {"ok": True, "ready": False, "ui": {"worldReady": False}},
            {"ok": True, "ready": True, "ui": {"worldReady": False}, "speed": 32},
        ]
        client = Playtest()

        def respond(*_args, data, **_kwargs):
            query = json.loads(data)
            return json.dumps({**replies.pop(0), "requestId": query["requestId"]}).encode()

        client.adb = respond
        self.assertEqual(client.read(ready=True)["speed"], 32)

    def test_read_rejects_stale_or_failed_responses(self):
        client = Playtest()
        client.adb = lambda *_args, **_kwargs: b'{"requestId":"old","ok":true}'
        with self.assertRaisesRegex(RuntimeError, "does not match"):
            client.read()

        def failed(*_args, data, **_kwargs):
            return json.dumps({**json.loads(data), "ok": False, "error": "FAILED"}).encode()

        client.adb = failed
        with self.assertRaisesRegex(RuntimeError, "FAILED"):
            client.read()

    def test_restore_failure_keeps_backup_and_never_reports_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "game.apk"
            apk.touch()
            store = Store(root / "records")
            store.write_record("battle_save.json", b"original")
            store.adb = Mock(return_value=b"")
            run = Mock(journal=[], saves=0)

            def complete(_speed):
                store.fail = "write"
                return {"world": {"gold": 6000, "route": 0}, "speed": 32}

            run.play.side_effect = complete
            output = StringIO()
            with (
                patch.object(playtest_first_battle, "ROOT", root),
                patch.object(playtest_first_battle, "Playtest", return_value=store),
                patch.object(playtest_first_battle, "Run", return_value=run),
                patch.object(playtest_first_battle, "verify_android"),
                redirect_stdout(output),
                self.assertRaisesRegex(OSError, "write failed"),
            ):
                playtest_first_battle.run_playtest(apk=apk)
            batches = list((root / "temp/playtest").iterdir())
            self.assertEqual(len(batches), 1)
            self.assertTrue((batches[0] / "records/backup.json").is_file())
            self.assertFalse((batches[0] / "records/restored.json").exists())
            self.assertFalse((batches[0] / "result.json").exists())
            self.assertNotIn("PASS", output.getvalue())
            store.adb.assert_any_call("emu", "kill")


if __name__ == "__main__":
    unittest.main()
