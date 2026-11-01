"""A completed game must not publish overall success when record recovery fails."""

import json
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch

import playtest_first_battle
from android_playtest import Playtest
from test_qa_records import Store


class PlaytestDriverTest(unittest.TestCase):
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
                patch("sys.argv", ["playtest", "--apk", str(apk)]),
                redirect_stdout(output),
                self.assertRaisesRegex(OSError, "write failed"),
            ):
                playtest_first_battle.main()
            batches = list((root / "temp/playtest").iterdir())
            self.assertEqual(len(batches), 1)
            self.assertTrue((batches[0] / "records/backup.json").is_file())
            self.assertFalse((batches[0] / "records/restored.json").exists())
            self.assertFalse((batches[0] / "result.json").exists())
            self.assertNotIn("PASS", output.getvalue())
            store.adb.assert_any_call("emu", "kill")


if __name__ == "__main__":
    unittest.main()
