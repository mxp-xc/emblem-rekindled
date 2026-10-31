"""A completed game must not publish overall success when record recovery fails."""

import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch

import playtest_first_battle
from test_qa_records import Store


class PlaytestDriverTest(unittest.TestCase):
    def test_restore_failure_keeps_backup_and_never_reports_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "game.apk"
            apk.touch()
            store = Store(root / "records")
            store.write_record("battle_save.json", b"original")
            store.adb = Mock(return_value=b"")
            store.enable = Mock(side_effect=lambda _speed: setattr(store, "fail", "write"))
            run = Mock(journal=[], saves=0)
            run.play.return_value = {"world": {"gold": 6000, "route": 0}, "speed": 32}
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
