"""Run native check phases once, optionally retaining structured timings and output."""

import json
import sys
import time
import unittest
from contextlib import nullcontext, redirect_stderr, redirect_stdout
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from emblem_dev.checks import godot, helpers
from emblem_dev.paths import GAME, ROOT, TESTS
from emblem_dev.process import run


def lint() -> int:
    commands = (
        ["gdlint", "game", "tools"],
        None,
        ["gdformat", "--check", "--line-length", "100", "game", "tools"],
        ["ruff", "check", "tools", "tests"],
        ["ruff", "format", "--check", "tools", "tests"],
        [
            str(ROOT / "node_modules" / ".bin" / "prettier"),
            "--check",
            "tools/**/*.java",
            "tools/**/*.js",
            "tests/**/*.mjs",
            "game/**/*.json",
            "package.json",
            ".prettierrc.json",
        ],
    )
    for command in commands:
        code = helpers.check(GAME) if command is None else run(command, cwd=ROOT, stdout=sys.stdout)
        if code:
            return code
    return 0


def tools() -> int:
    suite = unittest.defaultTestLoader.discover(str(TESTS), pattern="test_*.py")
    result = unittest.TextTestRunner(stream=sys.stderr).run(suite)
    return 0 if result.wasSuccessful() else 1


def check(mode: str = "quick", output: Path | None = None) -> int:
    if mode not in {"quick", "full"}:
        raise ValueError("check mode must be quick or full")
    if output is not None:
        output = output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    started_at = datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y-%m-%d %H:%M:%S")
    started = time.perf_counter()
    intervals = []
    exit_code = 1
    timings = output / "godot-timings.json" if output else None
    phases = [("lint", lint), ("tools", tools)]
    if mode == "full":
        phases.append(("game", lambda: godot.check(timings=timings)))
    try:
        with (output / "integrated-check.log").open("x") if output else nullcontext() as log:
            for name, phase in phases:
                print(
                    f"[CHECK] {name}" + (f": {output / 'integrated-check.log'}" if output else ""),
                    flush=True,
                )
                begin = time.perf_counter()
                finished = False
                exit_code = 1
                try:
                    with (
                        redirect_stdout(log) if log else nullcontext(),
                        redirect_stderr(log) if log else nullcontext(),
                    ):
                        if log:
                            print(f"[CHECK] {name}", flush=True)
                        try:
                            exit_code = phase()
                        except SystemExit as error:
                            exit_code = error.code if isinstance(error.code, int) else 1
                    finished = exit_code == 0
                finally:
                    intervals.append(
                        {
                            "name": name,
                            "seconds": round(time.perf_counter() - begin, 3),
                            "finished": finished,
                        }
                    )
                if not finished:
                    break
    except KeyboardInterrupt:
        exit_code = 130
        raise
    except SystemExit as error:
        exit_code = error.code if isinstance(error.code, int) else 1
        raise
    finally:
        if output:
            result = {
                "startedAt": started_at,
                "exitCode": exit_code,
                "seconds": round(time.perf_counter() - started, 3),
                "intervals": intervals,
                "godot": json.loads(timings.read_text()) if timings.exists() else None,
                "measurement": (
                    "Wall time around each stage and Godot invocation; no extra execution"
                ),
            }
            (output / "timings.json").write_text(json.dumps(result, indent=2) + "\n")
    return exit_code
