"""Fast actual-ADB first-battle regression: live queries, real input, one save per round."""

import json
import logging
import re
import subprocess
import time
import uuid
import zipfile
from pathlib import Path
from typing import Annotated

import typer

from emblem_dev.commands.state import SPEED_HELP, speed_parameter
from emblem_dev.paths import GAME, GODOT, ROOT
from emblem_dev.qa.android import install_captured_apk, record_session
from emblem_dev.qa.client import PACKAGE, AndroidInput, Playtest, validate_speed

app = typer.Typer()

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
                "godot",
                "--headless",
                "--path",
                str(GAME),
                "--script",
                str(GODOT / "plan_first_battle.gd"),
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

    def play(self, speed: int = 32) -> dict:
        self.client.adb("shell", "am", "start", "-n", PACKAGE + "/com.godot.game.GodotAppLauncher")
        self.set_speed(speed)
        self.key(4)
        state = self.title_entry("开始游戏")
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


@app.command("first-battle")
def run_playtest(
    *,
    speed: Annotated[int, typer.Option(callback=speed_parameter, help=SPEED_HELP)] = 32,
    serial: str | None = None,
    apk: Path | None = None,
    keep_emulator: bool = False,
) -> None:
    """通过真实 ADB 输入执行受记录保护的首关自然回归。"""
    validate_speed(speed)
    apk = apk or ROOT / "build/android/emblem-rekindled.apk"
    client = Playtest(serial)
    if not apk.is_file():
        raise ValueError("Export the debug APK first or provide --apk")
    with zipfile.ZipFile(apk) as archive:
        build_id = json.loads(archive.read("assets/content/build_info.json"))["buildId"]
    output = ROOT / "temp" / "playtest" / uuid.uuid4().hex[:8]
    output.mkdir(parents=True)
    print("OUTPUT", output, flush=True)
    try:
        client.adb("wait-for-device")
        installed = client.adb("shell", "pm", "list", "packages", PACKAGE).splitlines()
        first_install = ("package:" + PACKAGE).encode() not in installed
        if first_install:
            install_captured_apk(client, apk, output, build_id)
            client.adb("shell", "am", "force-stop", PACKAGE)
            client.adb("shell", "run-as", PACKAGE, "mkdir", "-p", "files")
        with record_session(client, output / "records") as protection:
            started = time.monotonic()
            if not first_install:
                install_captured_apk(client, apk, output, build_id)
            run = Run(client, output)
            try:
                state = run.play(speed)
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
                            "shell",
                            "run-as",
                            PACKAGE,
                            "cat",
                            "files/playtest_state.json",
                            check=False,
                        )
                    )
                    pid = client.adb("shell", "pidof", PACKAGE).decode().strip()
                    (output / "process-log.txt").write_bytes(
                        client.adb("logcat", "-d", "--pid=" + pid)
                    )
                except Exception:
                    logging.exception("Could not capture playtest failure evidence")
                raise
        print("ORIGINAL_JSON_RESTORED", flush=True)
        (output / "result.json").write_text(
            json.dumps(
                {
                    "passed": True,
                    "buildId": build_id,
                    "restoreSeconds": protection["restoreSeconds"],
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
        if not keep_emulator:
            client.adb("emu", "kill")
