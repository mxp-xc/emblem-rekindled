"""Fast actual-ADB first-battle regression: live queries, real input, one save per round."""

import argparse
import json
import logging
import re
import subprocess
import time
import uuid
from pathlib import Path

from android_playtest import PACKAGE, AndroidInput, Playtest
from delivery import verify_android
from qa_records import backup_records, restore_records

ROOT = Path(__file__).resolve().parents[1]
LABELS = {"attack": "攻击", "heal": "杖", "wait": "待机", "use_herb": "物品"}


class Run(AndroidInput):
    def __init__(self, client: Playtest, output: Path) -> None:
        super().__init__(client)
        self.output = output
        self.journal: list[dict] = []
        self.saves = 0

    def wait(self, predicate, timeout: float = 60) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.client.read(timeout=max(0.1, deadline - time.monotonic()))
            if predicate(state):
                return state
            if state["ui"]["title"]:
                raise AssertionError("Unexpected title while playing; inspect the last checkpoint")
            if (
                state["ui"]["dialogue"]
                or state["ui"]["choices"]
                or state["ui"]["feedback"] == "tutorial"
            ):
                self.key(66)
            time.sleep(0.03)
        raise TimeoutError("The game did not reach its expected input boundary")

    def checkpoint(self) -> dict:
        self.click(name="Menu")
        self.click("保存进度")
        self.key(4)
        saved = json.loads(
            self.client.adb("exec-out", "run-as", PACKAGE, "cat", "files/battle_save.json")
        )
        self.saves += 1
        (self.output / f"round-{saved['state']['round']:02d}.json").write_text(
            json.dumps(saved, ensure_ascii=False, indent=2)
        )
        return self.client.read()

    def plan(self, state: dict) -> dict:
        snapshot, assignments, plan = [
            self.output / name for name in ("current.json", "assignments.json", "plan.json")
        ]
        snapshot.write_text(json.dumps(state["snapshot"], ensure_ascii=False))
        result = subprocess.run(
            [
                "rtk",
                "proxy",
                "godot",
                "--headless",
                "--path",
                str(ROOT / "game"),
                "--script",
                "../tools/plan_first_battle.gd",
                "--",
                str(snapshot),
                str(assignments),
                str(plan),
            ],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        if result.returncode or re.search(r"SCRIPT ERROR|ERROR:", result.stdout + result.stderr):
            raise RuntimeError(result.stdout + result.stderr)
        return json.loads(plan.read_text())

    def action(self, command: dict) -> dict:
        state = self.client.read()
        if state["ui"]["selectedUnit"] >= 0:
            self.key(4)
        actor = command["actor"]
        moving = command["destination"] != [actor["x"], actor["y"]]
        self.cell(actor["x"], actor["y"], double=not moving)
        if moving:
            self.cell(*command["destination"])
        self.wait(lambda value: value["ui"]["unitMenu"] and not value["busy"])
        if equipped := command.get("equipBeforeMove"):
            self.click("物品")
            self.click("装备")
            options = self.client.read()["itemOptions"]["equip"]
            index = next(i for i, item in enumerate(options) if item["id"] == equipped)
            for _ in range(index):
                self.key(20)
            self.key(66)
            self.key(66)
            self.wait(
                lambda value: (
                    next(u for u in value["snapshot"]["state"]["units"] if u["id"] == actor["id"])[
                        "equippedInstanceId"
                    ]
                    == equipped
                )
            )
            self.key(4)
            self.key(4)
        self.click(LABELS[command["action"]])
        if command["action"] == "use_herb":
            self.key(66)
        if command["action"] != "wait":
            for _ in range(command["itemIndex"]):
                self.key(20)
            self.key(66)
            if command["action"] == "use_herb":
                self.key(66)
            else:
                self.cell(command["target"]["x"], command["target"]["y"])
                if command["action"] == "attack":
                    self.key(66)
        state = self.wait(
            lambda value: (
                bool(value["world"])
                and value["ui"]["worldReady"]
                or value["ready"]
                and next(u for u in value["snapshot"]["state"]["units"] if u["id"] == actor["id"])[
                    "action"
                ]
                == 2
            )
        )
        self.journal.append({"input": command, "observed": state["snapshot"]})
        with (self.output / "journal.jsonl").open("a") as journal:
            journal.write(json.dumps(self.journal[-1], ensure_ascii=False) + "\n")
        (self.output / "assignments.json").write_text(json.dumps(command["assignments"]))
        print(
            "ACTION",
            len(self.journal),
            command["round"],
            actor["id"],
            command["action"],
            flush=True,
        )
        return state

    def play(self) -> dict:
        self.client.adb("shell", "am", "start", "-n", PACKAGE + "/com.godot.game.GodotAppLauncher")
        state = self.client.read(timeout=90)
        while state["ui"]["prologue"] or not state["ui"]["titleOptions"]:
            self.key(66)
            state = self.client.read()
        for _ in range(5):
            if any(item.get("text") == "开始游戏" for item in state["controls"]):
                break
            self.key(22)
            state = self.client.read()
        self.click("开始游戏")
        configured = False
        deadline = time.monotonic() + 60
        while not state["ready"]:
            if time.monotonic() > deadline:
                raise TimeoutError("New game did not reach the first player turn")
            state = self.client.read()
            if state["ui"]["commander"] and not configured:
                self.key(22)
                self.key(4)
                configured = True
            elif state["ui"]["dialogue"] or state["ui"]["choices"]:
                self.key(66)
        if not configured or state["snapshot"]["state"]["commander"] != 0:
            raise AssertionError("Fresh game commander selection was not completed")
        self.click(name="Menu")
        self.click("游戏设置")
        self.click("查看全图")
        state = self.checkpoint()
        (self.output / "assignments.json").write_text("{}")
        for _ in range(180):
            if state["world"] and state["ui"]["worldReady"]:
                return state
            command = self.plan(state)
            if command["kind"] == "end_turn":
                previous_round = state["snapshot"]["state"]["round"]
                self.click(name="Menu")
                self.click("结束回合")
                state = self.wait(
                    lambda value, current_round=previous_round: (
                        bool(value["world"])
                        and value["ui"]["worldReady"]
                        or value["ready"]
                        and value["snapshot"]["state"]["round"] > current_round
                    )
                )
                if not state["world"]:
                    state = self.checkpoint()
                print("ROUND", state["snapshot"]["state"]["round"], flush=True)
            else:
                state = self.action(command)
        raise AssertionError("Playtest exceeded its finite action limit")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--speed", type=float, default=32)
    parser.add_argument("--serial")
    parser.add_argument("--apk", type=Path, default=ROOT / "build/android/emblem-rekindled.apk")
    parser.add_argument("--keep-emulator", action="store_true")
    args = parser.parse_args()
    client = Playtest(args.serial)
    if not args.apk.is_file():
        parser.error("Export the debug APK first or provide --apk")
    output = ROOT / "temp" / "playtest" / uuid.uuid4().hex[:8]
    output.mkdir(parents=True)
    print("OUTPUT", output, flush=True)
    try:
        client.adb("wait-for-device")
        client.adb("install", "-r", str(args.apk))
        verify_android(args.serial, args.apk)
        client.adb("shell", "am", "force-stop", PACKAGE)
        client.adb("shell", "run-as", PACKAGE, "mkdir", "-p", "files")

        backup = backup_records(client, output / "records")
        started = time.monotonic()
        run = Run(client, output)
        try:
            client.enable(args.speed)
            state = run.play()
            progress = state["world"]
            if progress["gold"] != 6000 or progress["route"] != 0:
                raise AssertionError("Unexpected first-battle completion")
            (output / "completed-progress.json").write_text(
                json.dumps(progress, ensure_ascii=False, indent=2)
            )
        except BaseException:
            try:
                (output / "failure.png").write_bytes(client.adb("exec-out", "screencap", "-p"))
                (output / "failure-state.json").write_bytes(
                    client.adb(
                        "shell", "run-as", PACKAGE, "cat", "files/playtest_state.json", check=False
                    )
                )
                pid = client.adb("shell", "pidof", PACKAGE).decode().strip()
                (output / "process-log.txt").write_bytes(client.adb("logcat", "-d", "--pid=" + pid))
            except Exception:
                logging.exception("Could not capture playtest failure evidence")
            raise
        finally:
            client.adb("shell", "am", "force-stop", PACKAGE)
            restore_records(client, backup)
            print("ORIGINAL_JSON_RESTORED", flush=True)
        (output / "result.json").write_text(
            json.dumps(
                {
                    "passed": True,
                    "speed": state["speed"],
                    "playerActions": len(run.journal),
                    "roundCheckpoints": run.saves,
                    "elapsedSeconds": round(time.monotonic() - started, 2),
                    "scope": "Actual ADB from new game; live queries; round saves only",
                },
                indent=2,
            )
        )
        print("PASS", len(run.journal), "actions;", run.saves, "round saves", flush=True)
    finally:
        if not args.keep_emulator:
            client.adb("emu", "kill")


if __name__ == "__main__":
    main()
