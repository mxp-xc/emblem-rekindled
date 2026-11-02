"""Shared real-input chapter QA; cases and fixtures are supplied by the caller."""

import json
import logging
import shutil
import subprocess
import time
import uuid
import zipfile
from contextlib import contextmanager
from pathlib import Path

from emblem_dev.delivery import verify_apk
from emblem_dev.qa.client import PACKAGE, AndroidInput
from emblem_dev.qa.records import backup_records, restore_records


class Flow(AndroidInput):
    death_cases = ()

    def __init__(self, client, output, fixtures, manifest, build_id):
        super().__init__(client)
        if not build_id:
            raise ValueError("Explicit captured buildId required")
        self.output = Path(output)
        self.build_id = build_id
        self.fixtures = fixtures
        self.manifest = manifest
        self.timings = {}
        self.inputs = []
        self.checkpoints = []
        self.dialogues = 0

    def key(self, *codes):
        self.inputs.append({"key": codes})
        super().key(*codes)

    def tap(self, x, y):
        self.inputs.append({"tap": [x, y]})
        super().tap(x, y)

    @contextmanager
    def phase(self, name):
        start = time.perf_counter()
        try:
            yield
        finally:
            self.timings[name] = round(time.perf_counter() - start, 3)

    def capture(self, name, state=None):
        state = self.client.read() if state is None else state
        (self.output / f"{name}.json").write_text(json.dumps(state, ensure_ascii=False, indent=2))
        (self.output / f"{name}.png").write_bytes(self.client.adb("exec-out", "screencap", "-p"))
        self.checkpoints.append(name)
        print("CHECKPOINT", name, state["snapshot"]["battleId"], flush=True)
        return state

    def start(self, record=None):
        self.client.adb("shell", "am", "force-stop", PACKAGE)
        if record is not None:
            if "version" not in record:
                record = {
                    "version": 1,
                    "chapterId": "chapter_1",
                    "battleId": record["completedBattle"],
                    "progress": record,
                }
            self.client.write_record("battle_save.json", json.dumps(record).encode())
        self.client.adb("shell", "am", "start", "-n", PACKAGE + "/com.godot.game.GodotAppLauncher")
        state = self.wait(lambda s: s["ui"]["title"])
        assert state["speed"] == 1, "Cold process must default to 1x"
        return state

    def speed_and_continue(self):
        self.set_speed(32)
        self.key(4)
        self.title_entry("读取进度")
        return self.wait(lambda s: s["ready"] or s["ui"]["worldReady"], advance=True)

    def cell(self, x, y, *, double=False):
        for _ in range(5):
            state = self.client.read()
            view = state["map"]
            scale = [state["window"][i] / state["viewport"][i] for i in range(2)]
            origin = [view["origin"][i] * scale[i] for i in range(2)]
            size = [view["size"][i] * scale[i] for i in range(2)]
            point = [
                origin[i]
                + size[i] / 2
                + ((x if i == 0 else y) + 0.5 - view["center"][i]) * 24 * view["zoom"] * scale[i]
                for i in range(2)
            ]
            if all(origin[i] + 20 <= point[i] <= origin[i] + size[i] - 20 for i in range(2)):
                break
            delta = [
                max(-size[i] + 72, min(size[i] - 72, origin[i] + size[i] / 2 - point[i]))
                for i in range(2)
            ]
            start = [
                origin[i] + (size[i] - 36 if delta[i] < 0 else 36)
                if abs(delta[i]) > 1
                else origin[i] + size[i] / 2
                for i in range(2)
            ]
            end = [start[i] + delta[i] for i in range(2)]
            self.inputs.append(
                {"swipe": [start, end], "purpose": "Bring target cell into actual map viewport"}
            )
            self.client.adb(
                "shell", "input", "swipe", *(str(round(n)) for n in (*start, *end)), "220"
            )
        else:
            raise AssertionError(f"Target cell remains outside viewport: {(x, y)}")
        super().cell(x, y, double=double)

    def wait(self, predicate, *, advance=False, timeout=45, observe_dialogues=False):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.client.read(timeout=max(0.1, deadline - time.monotonic()))
            assert state["build"]["buildId"] == self.build_id
            if predicate(state):
                return state
            if advance and state["ui"]["commander"]:
                self.key(4)
            elif advance and (
                state["ui"]["dialogue"]
                or state["ui"]["prologue"]
                or state["ui"]["feedback"] == "tutorial"
            ):
                if observe_dialogues and state["ui"]["dialogue"]:
                    self.dialogues += 1
                    self.capture(f"dialogue-{self.dialogues:02d}", state)
                self.key(66)
        raise TimeoutError("Expected business boundary not reached")

    def fixture(self, key):
        self.start(self.fixtures[key])
        return self.speed_and_continue()

    def map_speed(self, speed):
        self.set_speed(speed)
        for _ in range(4):
            state = self.client.read()
            if not state["ui"]["menu"]:
                return state
            self.key(4)
        raise AssertionError("Speed settings did not close")

    def save_cold(self, name):
        expected = self.client.read()["snapshot"]["state"]
        if not self.client.read()["ui"]["menu"]:
            self.click(name="Menu")
        self.click("保存进度")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            self.client.read()
            record = json.loads(self.client.read_record("battle_save.json"))
            if record.get("state") == expected:
                break
        else:
            raise TimeoutError("Save input did not persist the intended state")
        (self.output / f"{name}-saved.json").write_text(
            json.dumps(record, ensure_ascii=False, indent=2)
        )
        self.start()
        assert self.client.read()["speed"] == 1
        state = self.speed_and_continue()
        assert state["snapshot"]["state"] == expected
        self.capture(name + "-cold-equal", state)
        return state

    @contextmanager
    def video(self, name):
        """Keep original device motion evidence; no runtime presentation probes."""
        remote = f"/data/local/tmp/emblem-qa-{uuid.uuid4().hex}.mp4"
        process = subprocess.Popen(
            [
                *self.client.command,
                "shell",
                "screenrecord",
                "--time-limit",
                "90",
                "--bit-rate",
                "3000000",
                remote,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        pid = ""
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError("Android screenrecord ended before recording the action")
                pid = self.client.adb("shell", "pidof", "screenrecord").decode().strip()
                if pid and self.client.adb(
                    "shell", "stat", "-c", "%s", remote, check=False
                ).strip() not in (b"", b"0"):
                    break
            else:
                raise TimeoutError("Native screen recording did not produce its output header")
            yield
        finally:
            if pid and process.poll() is None:
                self.client.adb("shell", "kill", "-2", *pid.split())
            try:
                stdout, stderr = process.communicate(timeout=15)
            except subprocess.TimeoutExpired:
                process.terminate()
                stdout, stderr = process.communicate(timeout=5)
            (self.output / f"{name}-recording.log").write_bytes(stdout + stderr)
            data = self.client.adb("exec-out", "cat", remote, check=False)
            if data:
                (self.output / f"{name}.mp4").write_bytes(data)
                self.client.adb("shell", "rm", remote)
            else:
                raise AssertionError(
                    "No motion evidence was copied; preserve the batch and inspect recording log"
                )

    def named_world_cold(self, progress):
        battle_id = progress["completedBattle"]
        if not any(c.get("text") == "记录存档" for c in self.client.read()["controls"]):
            self.key(66)
        self.click("记录存档")
        # Both presses are real inputs: an occupied slot requires overwrite confirmation.
        self.key(66)
        self.key(66)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if self.client.record_exists("battle_save_slot_1.json"):
                named = json.loads(self.client.read_record("battle_save_slot_1.json"))
                if named.get("progress") == progress:
                    break
            self.client.read()
        else:
            raise TimeoutError(f"New {battle_id} named world slot did not persist")
        (self.output / f"{battle_id}-named-world-slot.json").write_text(
            json.dumps(named, ensure_ascii=False, indent=2)
        )
        self.start()
        self.set_speed(32)
        self.key(4)
        self.title_entry("读取存档")
        before = self.client.read_record("battle_save.json")
        self.key(66)
        state = self.wait(lambda s: s["ui"]["worldReady"], advance=True)
        assert self.client.read_record("battle_save.json") == before
        assert state["world"] == named["progress"]
        assert state["world"]["route"] == progress["route"]
        assert state["world"]["worldStep"] == progress["worldStep"]
        assert state["world"]["gold"] == progress["gold"]
        self.capture(f"{battle_id}-named-world-cold-no-repeat-reward", state)


def run_cases(flow, cases, handlers, apk, *, stop_emulator=False):
    """Install a fixed package only after full backup; recover even when a case fails."""
    if not cases or any(case not in handlers for case in cases):
        raise ValueError("Select at least one known case")
    with zipfile.ZipFile(apk) as archive:
        identity = json.loads(archive.read("assets/content/build_info.json"))
    if identity["buildId"] != flow.build_id:
        raise ValueError("Captured APK differs from requested buildId")
    flow.output.mkdir(parents=True, exist_ok=False)
    client = flow.client
    backup, rotation, passed = None, {}, False
    completed = []
    try:
        client.adb("wait-for-device", timeout=60)
        deadline = time.monotonic() + 60
        while client.adb("shell", "getprop", "sys.boot_completed").strip() != b"1":
            if time.monotonic() >= deadline:
                raise TimeoutError("Android boot did not finish")
            time.sleep(0.2)
        client.adb("shell", "am", "force-stop", PACKAGE)
        backup = backup_records(client, flow.output / "records")
        for key in ("accelerometer_rotation", "user_rotation"):
            rotation[key] = client.adb("shell", "settings", "get", "system", key).decode().strip()
        (flow.output / "original-rotation.json").write_text(json.dumps(rotation))
        captured = flow.output / "captured.apk"
        shutil.copy2(apk, captured)
        client.adb("install", "-r", str(captured), timeout=60)
        paths = client.adb("shell", "pm", "path", PACKAGE).decode().splitlines()
        installed = next(
            (p.removeprefix("package:") for p in paths if p.endswith("/base.apk")), None
        )
        if installed is None:
            raise RuntimeError("Installed base APK not found")
        installed_copy = flow.output / "installed.apk"
        client.adb("pull", installed, str(installed_copy))
        verify_apk(installed_copy, flow.build_id)
        for case in cases:
            with flow.phase(case):
                handlers[case](flow)
            completed.append(case)
        passed = True
    except BaseException:
        if backup is not None:
            try:
                flow.capture("failure")
                pid = client.adb("shell", "pidof", PACKAGE).decode().strip()
                (flow.output / "failure-log.txt").write_bytes(
                    client.adb("logcat", "-d", "--pid=" + pid)
                )
            except Exception:
                logging.exception("Could not capture chapter QA failure")
        raise
    finally:
        try:
            if backup is not None:
                with flow.phase("restoreOriginalRecordsAndRotation"):
                    client.adb("shell", "am", "force-stop", PACKAGE)
                    try:
                        restore_records(client, backup)
                    finally:
                        for key, value in rotation.items():
                            client.adb("shell", "settings", "put", "system", key, value)
                            actual = client.adb("shell", "settings", "get", "system", key)
                            if actual.decode().strip() != value:
                                raise RuntimeError(f"Rotation restoration failed: {key}")
                (flow.output / "result.json").write_text(
                    json.dumps(
                        {
                            "passed": passed,
                            "buildId": flow.build_id,
                            "cases": cases,
                            "completedCases": completed,
                            "timings": flow.timings,
                            "inputs": flow.inputs,
                            "checkpoints": flow.checkpoints,
                            "allOriginalNamesBytesAndRotationRestored": True,
                            "deathVisualReviewRequired": any(
                                c in flow.death_cases for c in completed
                            ),
                        },
                        ensure_ascii=False,
                        indent=2,
                    )
                )
        finally:
            if stop_emulator:
                client.adb("emu", "kill")
