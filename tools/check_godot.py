"""Check Godot imports, script parsing, and behavior tests; engine errors fail the command."""

import argparse
import os
import re
import signal
import subprocess
import sys
import time
from contextlib import suppress
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR|ERROR):")


def godot(
    *args: str,
    timeout_seconds: float = 60,
    ready_file: Path | None = None,
    startup_seconds: float = 30,
) -> None:
    # This is an error protocol, so consume the engine's unfiltered output.
    command = ["godot", "--headless", "--path", str(GAME), *args]
    with subprocess.Popen(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    ) as process:
        try:
            deadline = time.monotonic() + (startup_seconds if ready_file else timeout_seconds)
            started = ready_file is None
            while True:
                if not started and ready_file.is_file():
                    started = True
                    deadline = time.monotonic() + timeout_seconds
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, timeout_seconds)
                try:
                    output, _ = process.communicate(timeout=min(0.1, remaining))
                    break
                except subprocess.TimeoutExpired as error:
                    partial_output = error.output or ""
                    if isinstance(partial_output, bytes):
                        partial_output = partial_output.decode(errors="replace")
                    if not ENGINE_ERROR.search(partial_output):
                        continue
                    # Stack frames can follow the first error line in later writes.
                    drain_seconds = min(0.2, max(0, deadline - time.monotonic()))
                    try:
                        output, _ = process.communicate(timeout=drain_seconds)
                    except subprocess.TimeoutExpired:
                        pass
                    failure_code = process.returncode or 1
                    with suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGKILL)
                    output, _ = process.communicate()
                    print(output, file=sys.stderr)
                    raise SystemExit(failure_code) from None
        except subprocess.TimeoutExpired as error:
            # Terminate the whole owned group, including engine subprocesses.
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            print(output, file=sys.stderr)
            phase = "runtime" if started else "startup"
            print(f"Godot {phase} timed out: {' '.join(args)}", file=sys.stderr)
            raise SystemExit(1) from error
        except KeyboardInterrupt:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise
        if process.returncode or ENGINE_ERROR.search(output):
            print(output, file=sys.stderr)
            raise SystemExit(process.returncode or 1)
    passes = [line for line in output.splitlines() if line.startswith("PASS ")]
    print("\n".join(passes) if passes else "OK " + " ".join(args), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--parse-only", action="store_true")
    group.add_argument("--test", action="append", help="Test name under game/tests; repeatable")
    group.add_argument("--tests-only", action="store_true", help="Behavior tests without reimport")
    args = parser.parse_args()
    if args.test:
        for test in args.test:
            if Path(test).name != test or not test.startswith("test_") or not test.endswith(".gd"):
                parser.error("--test expects a test file name, not a path")
            print(f"[TEST] {test}", flush=True)
            godot("--script", f"tests/{test}")
        return
    if not args.tests_only:
        print("[IMPORT] Project resources", flush=True)
        godot("--editor", "--import")
        scripts = [
            os.path.relpath(script, GAME)
            for script in sorted([*GAME.rglob("*.gd"), *(ROOT / "tools").glob("*.gd")])
            if ".godot" not in script.parts
        ]
        print(f"[PARSE] {len(scripts)} scripts in one engine", flush=True)
        godot("--script", "../tools/parse_scripts.gd", "--", *scripts)
    if args.parse_only:
        return
    scripts = sorted((GAME / "tests").glob("test_*.gd"))
    for index, script in enumerate(scripts, 1):
        print(f"[TEST {index}/{len(scripts)}] {script.name}", flush=True)
        godot("--script", str(script.relative_to(GAME)))
    print("[SMOKE] Main scene", flush=True)
    godot("--quit-after", "5")


if __name__ == "__main__":
    main()
