"""Record protection contracts, including empty-list, I/O and recovery failures."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from emblem_dev.commands.qa import restore_records as restore_records_command
from emblem_dev.qa.records import backup_records, preserve_records, restore_records


class Store:
    def __init__(self, directory: Path):
        self.directory = directory
        directory.mkdir()
        self.hidden = False
        self.fail = ""

    def record_names(self):
        if self.fail == "list":
            raise OSError("list failed")
        return [] if self.hidden else [p.name for p in self.directory.iterdir()]

    def record_exists(self, name):
        return (self.directory / name).exists()

    def read_record(self, name):
        if self.fail == "read":
            raise OSError("read failed")
        return (self.directory / name).read_bytes()

    def write_record(self, name, data):
        if self.fail == "write":
            raise OSError("write failed")
        if self.fail in ("partial", "mismatch"):
            (self.directory / name).write_bytes(data[:1])
            if self.fail == "partial":
                raise OSError("partial write")
            return
        (self.directory / name).write_bytes(data)

    def remove_record(self, name):
        if self.fail == "delete":
            raise OSError("delete failed")
        (self.directory / name).unlink()


class RecordsTest(unittest.TestCase):
    def test_native_restore_validates_backup_before_creating_device_client(self):
        with tempfile.TemporaryDirectory() as directory:
            backup = Path(directory) / "backup.json"
            backup.write_text("{}")
            with (
                patch("emblem_dev.commands.qa.Playtest") as client,
                self.assertRaises(ValueError),
            ):
                restore_records_command(backup, serial="device")
            client.assert_not_called()

    def test_native_restore_stops_app_and_restores_verified_backup(self):
        self.store.write_record("battle_save.json", b"original")
        backup = backup_records(self.store, self.backup)
        self.store.write_record("battle_save.json", b"changed")
        self.store.adb = Mock()
        with patch("emblem_dev.commands.qa.Playtest", return_value=self.store) as client:
            restore_records_command(backup, serial="device")
        client.assert_called_once_with("device")
        self.store.adb.assert_called_once_with(
            "shell", "am", "force-stop", "io.github.mxpxc.emblemrekindled"
        )
        self.assertEqual(self.store.read_record("battle_save.json"), b"original")
        self.assertTrue((self.backup / "restored.json").exists())

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = Store(self.root / "records")
        self.backup = self.root / "backup"

    def test_restore_exact_bytes_after_action_failure(self):
        self.store.write_record("battle_save.json", b' {"original":true}\n')
        self.store.write_record("settings.json", b'{"music":false}')
        with self.assertRaisesRegex(RuntimeError, "action failed"):
            with preserve_records(self.store, self.backup):
                self.store.write_record("battle_save.json", b"changed")
                self.store.write_record("new.json", b"new")
                raise RuntimeError("action failed")
        self.assertEqual(set(self.store.record_names()), {"battle_save.json", "settings.json"})
        self.assertEqual(self.store.read_record("battle_save.json"), b' {"original":true}\n')
        self.assertEqual(self.store.read_record("settings.json"), b'{"music":false}')
        self.assertTrue((self.backup / "restored.json").exists())

    def test_genuinely_empty_install_can_restore_empty(self):
        with preserve_records(self.store, self.backup):
            self.store.write_record("new.json", b"new")
        self.assertEqual(self.store.record_names(), [])

    def test_listing_and_read_failures_never_enter_mutating_body(self):
        self.store.write_record("battle_save.json", b"original")
        for failure in ("list", "read", "hidden"):
            with self.subTest(failure=failure):
                self.store.fail = failure
                self.store.hidden = failure == "hidden"
                with self.assertRaises((OSError, RuntimeError)):
                    with preserve_records(self.store, self.root / failure):
                        self.fail("Backup failure entered mutating body")
                self.assertEqual(
                    (self.store.directory / "battle_save.json").read_bytes(), b"original"
                )

    def test_restore_failure_retains_backup_and_extras_until_originals_verified(self):
        self.store.write_record("battle_save.json", b"original")
        path = backup_records(self.store, self.backup)
        self.store.write_record("battle_save.json", b"changed")
        self.store.write_record("new.json", b"new")
        self.store.fail = "write"
        with self.assertRaises(OSError):
            restore_records(self.store, path)
        self.assertTrue(self.store.record_exists("new.json"))
        self.assertTrue(path.exists())
        self.assertFalse((self.backup / "restored.json").exists())
        self.store.fail = "delete"
        with self.assertRaises(OSError):
            restore_records(self.store, path)
        self.assertEqual(self.store.read_record("battle_save.json"), b"original")
        self.assertFalse((self.backup / "restored.json").exists())
        self.store.fail = ""
        restore_records(self.store, path)
        self.assertEqual(self.store.record_names(), ["battle_save.json"])

    def test_invalid_backup_is_rejected_without_mutation(self):
        path = self.root / "bad.json"
        for manifest in ({}, {"version": 1, "complete": False, "records": {}}):
            path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                restore_records(self.store, path)
            self.assertEqual(self.store.record_names(), [])

    def test_partial_and_silently_corrupt_restore_can_be_recovered(self):
        self.store.write_record("battle_save.json", b"original")
        path = backup_records(self.store, self.backup)
        for failure in ("partial", "mismatch"):
            with self.subTest(failure=failure):
                self.store.write_record("new.json", b"new")
                self.store.fail = failure
                with self.assertRaises((OSError, RuntimeError)):
                    restore_records(self.store, path)
                self.assertEqual(self.store.read_record("battle_save.json"), b"o")
                self.assertTrue(self.store.record_exists("new.json"))
                self.assertFalse((self.backup / "restored.json").exists())
                self.store.fail = ""
                restore_records(self.store, path)
                self.assertEqual(self.store.read_record("battle_save.json"), b"original")
                self.assertFalse(self.store.record_exists("new.json"))


if __name__ == "__main__":
    unittest.main()
