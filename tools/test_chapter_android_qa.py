"""Exercise shared QA contracts using an in-memory device and tiny captured APKs."""

import json
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from chapter_android_qa import Flow, main, run_cases


class Device:
    def __init__(self, apk):
        self.apk = apk
        self.records = {"battle_save.json": b" original bytes\n"}
        self.rotation = {"accelerometer_rotation": "1", "user_rotation": "0"}
        self.commands = []
        self.fail_backup = False
        self.fail_restore = False

    def record_names(self):
        if self.fail_backup:
            raise OSError("enumeration failed")
        return list(self.records)

    def record_exists(self, name):
        return name in self.records

    def read_record(self, name):
        return self.records[name]

    def write_record(self, name, data):
        if self.fail_restore:
            raise OSError("restore failed")
        self.records[name] = data

    def remove_record(self, name):
        del self.records[name]

    def adb(self, *args, **kwargs):
        self.commands.append(args)
        if args[:3] == ("shell", "getprop", "sys.boot_completed"):
            return b"1"
        if args[:3] == ("shell", "settings", "get"):
            return self.rotation[args[-1]].encode()
        if args[:3] == ("shell", "settings", "put"):
            self.rotation[args[-2]] = args[-1]
        if args[:3] == ("shell", "pm", "path"):
            return b"package:/device/base.apk\n"
        if args[0] == "pull":
            shutil.copy2(self.apk, args[2])
        return b""


class ChapterAndroidQaTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apk = self.root / "candidate.apk"
        self.make_apk(self.apk, "fixed")
        self.client = Device(self.apk)
        self.flow = Flow(self.client, self.root / "batch", {}, {}, "fixed")
        # Failure evidence is irrelevant to these storage contracts; no live state exists.
        self.flow.capture = lambda *args: None

    def make_apk(self, path, build):
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("assets/content/build_info.json", json.dumps({"buildId": build}))

    def run_case(self, handler):
        run_cases(self.flow, ["case"], {"case": handler}, self.apk)

    def test_double_cell_scrolls_then_sends_same_point_taps_without_intervening_read(self):
        events = []
        center = [0, 0]

        def read():
            events.append(("read",))
            return {
                "window": [200, 200],
                "viewport": [200, 200],
                "map": {"origin": [0, 0], "size": [200, 200], "center": center, "zoom": 1},
            }

        def adb(*args):
            events.append(args)
            if args[:3] == ("shell", "input", "swipe"):
                center[0] = 10
            return b""

        self.client.read = read
        self.client.adb = adb
        with patch("android_playtest.time.sleep"):
            self.flow.cell(10, 0, double=True)
        taps = [("shell", "input", "tap", "112", "112")] * 2
        self.assertEqual(events[-2:], taps)
        self.assertEqual(
            [event for event in events if event[:3] == ("shell", "input", "tap")], taps
        )
        self.assertTrue(any(event[:3] == ("shell", "input", "swipe") for event in events))

    def test_case_failure_restores_all_original_bytes_rotation_and_retains_backup(self):
        def fail(flow):
            flow.client.records["battle_save.json"] = b"changed"
            flow.client.records["extra.json"] = b"extra"
            flow.client.rotation["user_rotation"] = "1"
            raise RuntimeError("case failed")

        with self.assertRaisesRegex(RuntimeError, "case failed"):
            self.run_case(fail)
        self.assertEqual(self.client.records, {"battle_save.json": b" original bytes\n"})
        self.assertEqual(self.client.rotation["user_rotation"], "0")
        result = json.loads((self.flow.output / "result.json").read_text())
        self.assertFalse(result["passed"])
        self.assertEqual(result["completedCases"], [])
        self.assertTrue((self.flow.output / "records/backup.json").exists())

    def test_backup_failure_never_installs_or_enters_case(self):
        self.client.fail_backup = True
        with self.assertRaisesRegex(OSError, "enumeration failed"):
            self.run_case(lambda _: self.fail("Entered case without backup"))
        self.assertFalse(any(c[0] == "install" for c in self.client.commands))
        self.assertFalse((self.flow.output / "result.json").exists())

    def test_restore_failure_keeps_extras_backup_and_never_reports_success(self):
        def mutate(flow):
            flow.client.records["extra.json"] = b"extra"
            flow.client.fail_restore = True
            flow.client.rotation["user_rotation"] = "1"

        with self.assertRaisesRegex(OSError, "restore failed"):
            self.run_case(mutate)
        self.assertIn("extra.json", self.client.records)
        self.assertTrue((self.flow.output / "records/backup.json").exists())
        self.assertFalse((self.flow.output / "result.json").exists())
        self.assertEqual(self.client.rotation["user_rotation"], "0")

    def test_requested_and_installed_build_mismatches_stop_before_case(self):
        self.flow.build_id = "wrong"
        with self.assertRaisesRegex(ValueError, "Captured APK"):
            self.run_case(lambda _: self.fail("Entered mismatched build"))
        self.assertEqual(self.client.commands, [])
        self.flow.build_id = "fixed"
        other = self.root / "other.apk"
        self.make_apk(other, "stale")
        self.client.apk = other
        with self.assertRaisesRegex(RuntimeError, "APK identity mismatch"):
            self.run_case(lambda _: self.fail("Entered stale installed build"))
        self.assertEqual(self.client.records, {"battle_save.json": b" original bytes\n"})

    def test_wait_checks_runtime_identity_and_uses_remaining_monotonic_deadline(self):
        self.client.read = lambda **kwargs: {"build": {"buildId": "stale"}}
        with self.assertRaises(AssertionError):
            self.flow.wait(lambda _: True)
        with patch("chapter_android_qa.time.monotonic", side_effect=[1, 3]):
            with self.assertRaises(TimeoutError):
                self.flow.wait(lambda _: False, timeout=1)

    def test_success_marks_completed_case_only_after_return(self):
        self.run_case(lambda flow: flow.client.records.update({"new.json": b"new"}))
        result = json.loads((self.flow.output / "result.json").read_text())
        self.assertTrue(result["passed"])
        self.assertEqual(result["completedCases"], ["case"])
        self.assertNotIn("new.json", self.client.records)

    def test_cli_loads_explicit_case_module_and_fixture_without_history_scripts(self):
        fixtures = self.root / "fixtures"
        fixtures.mkdir()
        (fixtures / "fixtures.json").write_text(json.dumps({"target": {"value": 7}}))
        (fixtures / "manifest.json").write_text(json.dumps({"expected": 7}))
        module = self.root / "cases.py"
        module.write_text(
            "def fixture_case(flow):\n"
            "    assert flow.fixtures['target']['value'] == flow.manifest['expected']\n"
            "    flow.client.records['new.json'] = b'fixture'\n"
            "CASES = {'fixture': fixture_case}\n"
        )
        argv = [
            "chapter_android_qa.py",
            "--apk",
            str(self.apk),
            "--build",
            "fixed",
            "--fixtures",
            str(fixtures),
            "--cases",
            str(module),
            "--case",
            "fixture",
            "--output",
            str(self.flow.output),
            "--serial",
            "fixture-device",
        ]
        with (
            patch("sys.argv", argv),
            patch("chapter_android_qa.Playtest", return_value=self.client),
        ):
            main()
        result = json.loads((self.flow.output / "result.json").read_text())
        self.assertTrue(result["passed"])
        self.assertEqual(result["completedCases"], ["fixture"])
        self.assertNotIn("new.json", self.client.records)


if __name__ == "__main__":
    unittest.main()
