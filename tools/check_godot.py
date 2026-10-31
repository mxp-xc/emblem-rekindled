"""Check Godot imports, script parsing, and behavior tests; engine errors fail the command."""

import argparse
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"


def godot(*args: str, timeout_seconds: float = 60) -> None:
    command = ["rtk", "godot", "--headless", "--path", str(GAME), *args]
    with subprocess.Popen(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    ) as process:
        try:
            output, _ = process.communicate(timeout=timeout_seconds)
        except subprocess.TimeoutExpired as error:
            # RTK owns the Godot child: terminate the whole owned process group.
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            print(output, file=sys.stderr)
            print(f"Godot exceeded {timeout_seconds:g}s: {' '.join(args)}", file=sys.stderr)
            raise SystemExit(1) from error
        except KeyboardInterrupt:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise
        if process.returncode or re.search(r"(?:SCRIPT ERROR|ERROR):", output):
            print(output, file=sys.stderr)
            raise SystemExit(process.returncode or 1)
    passes = [line for line in output.splitlines() if line.startswith("PASS ")]
    print("\n".join(passes) if passes else "OK " + " ".join(args))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--parse-only", action="store_true")
    group.add_argument("--test", help="Single test file name under game/tests")
    args = parser.parse_args()
    if args.test:
        if Path(args.test).name != args.test or not args.test.startswith("test_"):
            parser.error("--test expects a test file name, not a path")
        godot("--script", f"tests/{args.test}")
        return
    godot("--editor", "--import")
    for script in sorted(GAME.rglob("*.gd")):
        if ".godot" not in script.parts:
            godot("--check-only", "--script", str(script.relative_to(GAME)))
    if args.parse_only:
        return
    for script in sorted((GAME / "tests").glob("test_*.gd")):
        godot("--script", str(script.relative_to(GAME)))
    godot("--quit-after", "5")


if __name__ == "__main__":
    main()
