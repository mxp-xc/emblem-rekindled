"""Read debug state and operate the session speed setting through real ADB input."""

import argparse
import json
import shlex
import subprocess
import time

from qa_records import record_name

PACKAGE = "io.github.mxpxc.emblemrekindled"


class Playtest:
    def __init__(self, serial: str | None = None, adb: str = "adb") -> None:
        self.command = [adb, *(["-s", serial] if serial else [])]

    def adb(
        self, *args: str, data: bytes | None = None, check: bool = True, timeout: float = 15
    ) -> bytes:
        result = subprocess.run(
            [*self.command, *args], input=data, capture_output=True, timeout=timeout, check=False
        )
        if result.returncode:
            error = result.stderr.decode(errors="replace")
            if check or "No such file or directory" not in error:
                raise RuntimeError(error)
        return result.stdout if result.returncode == 0 else b""

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

    def read(self, *, ready: bool = False, timeout: float = 30) -> dict:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            request = str(time.monotonic_ns())
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            # One ADB round trip publishes the request and waits for its matching response.
            # The host still parses and verifies correlation before returning authority.
            marker = shlex.quote('"requestId":"' + request + '"')
            script = (
                "cat > files/playtest_request.json.tmp && "
                "mv files/playtest_request.json.tmp files/playtest_request.json && "
                "until=$(( SECONDS + 2 )); "
                "while true; do "
                "if [ -f files/playtest_state.json ] && "
                f"grep -Fq {marker} files/playtest_state.json; then "
                "cat files/playtest_state.json; exit 0; fi; "
                "[ $SECONDS -ge $until ] && break; sleep 0.01; done; "
                f'echo \'{{"pending":true,"requestId":"{request}"}}\''
            )
            try:
                raw = self.adb(
                    "shell",
                    "run-as",
                    PACKAGE,
                    "sh",
                    "-c",
                    shlex.quote(script),
                    data=json.dumps({"requestId": request}).encode(),
                    timeout=remaining,
                )
            except subprocess.TimeoutExpired as error:
                raise TimeoutError(
                    "The debug app did not respond within the requested timeout"
                ) from error
            response = json.loads(raw)
            if response.get("requestId") != request:
                raise RuntimeError("Debug response does not match the current request")
            if response.get("pending") is True:
                continue
            if not response["ok"]:
                raise RuntimeError(response["error"])
            if not ready or response["ready"] or response["ui"]["worldReady"]:
                return response
        raise TimeoutError("The debug app did not reach a ready input boundary")


class AndroidInput:
    """Real input mapped from a fresh read-only response, shared by platform drivers."""

    def __init__(self, client: Playtest) -> None:
        self.client = client

    def key(self, *codes: int) -> None:
        if not codes:
            return
        if len(codes) > 1 and 4 in codes:
            for code in codes:
                self.key(code)
            return
        self.client.adb("shell", "input", "keyevent", *(str(code) for code in codes))
        # Distinct system Back presses must exceed the game's 100ms notification debounce.
        time.sleep(0.12 if codes[0] == 4 else 0.04)

    def tap(self, x: float, y: float) -> None:
        self.client.adb("shell", "input", "tap", str(round(x)), str(round(y)))
        time.sleep(0.04)

    def click(self, text: str = "", *, name: str = "", state: dict | None = None) -> None:
        state = self.client.read() if state is None else state
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

    def set_speed(self, speed: int) -> dict:
        """Select a visible rate in the game's settings, leaving that settings page open."""
        state = self.client.read()
        if state["ui"]["title"]:
            self.title_entry("游戏设置")
        else:
            if not state["ui"]["menu"]:
                self.click(name="Menu", state=state)
                state = self.client.read()
            if state["ui"]["menuPage"] != "settings":
                self.click("游戏设置", state=state)
        self.click(name="GameSpeed")
        self.click(name=f"Speed_{speed}")
        state = self.client.read()
        if state["speed"] != speed:
            raise RuntimeError("The game did not apply the selected session speed")
        return state

    def title_entry(self, text: str) -> dict:
        """Use the actual title order to take the shorter real-key path to an entry."""
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            state = self.client.read()
            if not state["ui"]["title"]:
                raise RuntimeError("The title selector is not open")
            if not state["ui"]["prologue"] and state["ui"]["titleOptions"]:
                break
            self.key(66)
        else:
            raise TimeoutError("The title did not become interactive")
        entries = state["ui"]["titleEntries"]
        current = next(c["text"] for c in state["controls"] if c.get("text") in entries)
        forward = (entries.index(text) - entries.index(current)) % len(entries)
        backward = (entries.index(current) - entries.index(text)) % len(entries)
        self.key(*([22] * forward if forward <= backward else [21] * backward))
        state = self.client.read()
        self.click(text, state=state)
        return self.client.read()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial")
    parser.add_argument("--adb", default="adb")
    commands = parser.add_subparsers(dest="command", required=True)
    speed = commands.add_parser(
        "speed", help="Select the current session rate through game settings"
    )
    speed.add_argument("value", type=int)
    read = commands.add_parser("read", help="Read live state; no menu or progress write")
    read.add_argument("--ready", action="store_true", help="Wait for a player boundary or world")
    read.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    client = Playtest(args.serial, args.adb)
    if args.command == "speed":
        print(json.dumps(AndroidInput(client).set_speed(args.value), ensure_ascii=False))
    else:
        print(json.dumps(client.read(ready=args.ready, timeout=args.timeout), ensure_ascii=False))


if __name__ == "__main__":
    main()
