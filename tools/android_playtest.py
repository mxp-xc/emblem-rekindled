"""Opt-in debug speed and read-only live state through ADB, without saving progress."""

import argparse
import json
import subprocess
import time

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
        # tee receives stdin directly; no interpolated shell redirection or host temporary file.
        self.adb(
            "shell",
            "run-as",
            PACKAGE,
            "tee",
            "files/" + name + ".tmp",
            data=json.dumps(value).encode(),
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
