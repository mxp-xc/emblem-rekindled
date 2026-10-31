"""Opt-in debug speed and read-only live state through ADB, without saving progress."""

import argparse
import json
import subprocess
import time

from qa_records import record_name

PACKAGE = "io.github.mxpxc.emblemrekindled"
FILES = (
    "playtest.json",
    "playtest_request.json",
    "playtest_state.json",
    "playtest.json.tmp",
    "playtest_request.json.tmp",
    "playtest_state.json.tmp",
)


class Playtest:
    def __init__(self, serial: str | None = None, adb: str = "adb") -> None:
        self.command = ["rtk", "proxy", adb, *(["-s", serial] if serial else [])]

    def adb(self, *args: str, data: bytes | None = None, check: bool = True) -> bytes:
        result = subprocess.run(
            [*self.command, *args], input=data, capture_output=True, timeout=15, check=False
        )
        if result.returncode:
            error = result.stderr.decode(errors="replace")
            if check or "No such file or directory" not in error:
                raise RuntimeError(error)
        return result.stdout if result.returncode == 0 else b""

    def _write(self, name: str, value: dict) -> None:
        self.write_record(name, json.dumps(value).encode())

    def record_names(self) -> list[str]:
        # Shell v2 preserves remote errors. Only an explicit missing directory is empty.
        raw = self.adb("shell", "run-as", PACKAGE, "ls", "-1", "files", check=False)
        return [
            record_name(name)
            for name in raw.decode().splitlines()
            if name.endswith(".json") or name.endswith(".json.tmp")
        ]

    def record_exists(self, name: str) -> bool:
        path = "files/" + record_name(name)
        # stat reports errors distinctly from the sentinel used for missing files.
        result = (
            self.adb(
                "shell",
                "run-as",
                PACKAGE,
                "sh",
                "-c",
                f"'if [ -e {path} ]; then stat {path} >/dev/null && echo PRESENT; "
                f"elif [ -d files ]; then echo ABSENT; else stat files; fi'",
            )
            .decode()
            .strip()
        )
        if result not in ("PRESENT", "ABSENT"):
            raise RuntimeError(f"Unexpected existence response for {name}: {result}")
        return result == "PRESENT"

    def read_record(self, name: str) -> bytes:
        return self.adb("shell", "run-as", PACKAGE, "cat", "files/" + record_name(name))

    def remove_record(self, name: str) -> None:
        self.adb("shell", "run-as", PACKAGE, "rm", "files/" + record_name(name))

    def write_record(self, name: str, data: bytes) -> None:
        record_name(name)
        # tee receives stdin directly; no interpolated shell redirection or host temporary file.
        self.adb(
            "shell",
            "run-as",
            PACKAGE,
            "tee",
            "files/" + name + ".tmp",
            data=data,
        )
        self.adb("shell", "run-as", PACKAGE, "mv", "files/" + name + ".tmp", "files/" + name)

    def enable(self, speed: float = 32) -> None:
        if not 1 <= speed <= 32:
            raise ValueError("Speed must be between 1 and 32")
        self.adb("shell", "run-as", PACKAGE, "mkdir", "-p", "files")
        self._write(FILES[0], {"speed": speed})

    def disable(self) -> None:
        self.adb("shell", "run-as", PACKAGE, "rm", "-f", *("files/" + name for name in FILES))

    def read(self, *, ready: bool = False, timeout: float = 30) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            request = str(time.monotonic_ns())
            self._write(FILES[1], {"requestId": request})
            while time.monotonic() < deadline:
                raw = self.adb("shell", "run-as", PACKAGE, "cat", "files/" + FILES[2], check=False)
                response = json.loads(raw) if raw else {}
                if response.get("requestId") == request:
                    if not response["ok"]:
                        raise RuntimeError(response["error"])
                    if not ready or response["ready"] or response["ui"]["worldReady"]:
                        return response
                    break
                time.sleep(0.03)
            time.sleep(0.03)
        raise TimeoutError("No ready playtest response; enable debug test mode and restart the app")


class AndroidInput:
    """Real input mapped from a fresh read-only response, shared by platform drivers."""

    def __init__(self, client: Playtest) -> None:
        self.client = client

    def key(self, code: int) -> None:
        self.client.adb("shell", "input", "keyevent", str(code))
        # Distinct system Back presses must exceed the game's 100ms notification debounce.
        time.sleep(0.12 if code == 4 else 0.04)

    def tap(self, x: float, y: float) -> None:
        self.client.adb("shell", "input", "tap", str(round(x)), str(round(y)))
        time.sleep(0.04)

    def click(self, text: str = "", *, name: str = "") -> None:
        state = self.client.read()
        item = next(
            (
                item
                for item in state["controls"]
                if item.get("enabled", True)
                and (item.get("text") == text if text else item["name"] == name)
            ),
            None,
        )
        if item is None:
            raise AssertionError(f"Visible control missing: {text or name}")
        x, y, width, height = item["rect"]
        self.tap(
            (x + width / 2) * state["window"][0] / state["viewport"][0],
            (y + height / 2) * state["window"][1] / state["viewport"][1],
        )

    def cell(self, x: int, y: int, *, double: bool = False) -> None:
        state = self.client.read()
        view = state["map"]
        point = [
            view["origin"][axis]
            + view["size"][axis] / 2
            + ((x if axis == 0 else y) + 0.5 - view["center"][axis]) * 24 * view["zoom"]
            for axis in range(2)
        ]
        point = [point[i] * state["window"][i] / state["viewport"][i] for i in range(2)]
        self.tap(*point)
        if double:
            self.tap(*point)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial")
    parser.add_argument("--adb", default="adb")
    commands = parser.add_subparsers(dest="command", required=True)
    enable = commands.add_parser("enable", help="Enable on the next debug app launch")
    enable.add_argument("--speed", type=float, default=32)
    read = commands.add_parser("read", help="Read live state; no menu or progress write")
    read.add_argument("--ready", action="store_true", help="Wait for a player boundary or world")
    read.add_argument("--timeout", type=float, default=30)
    commands.add_parser("disable", help="Remove test files; restart to restore normal speed")
    args = parser.parse_args()
    client = Playtest(args.serial, args.adb)
    if args.command == "enable":
        client.enable(args.speed)
        print("Enabled for next debug launch; restart the app")
    elif args.command == "disable":
        client.disable()
        print("Disabled; restart the app to restore normal speed")
    else:
        print(json.dumps(client.read(ready=args.ready, timeout=args.timeout), ensure_ascii=False))


if __name__ == "__main__":
    main()
