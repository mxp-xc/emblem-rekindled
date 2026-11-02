"""Run the complete check once with structured phase timings and a retained log."""

import argparse
import json
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]


def run(output: Path) -> int:
    # Exclusive creation prevents accidental replacement of a previous evidence batch.
    output.mkdir(parents=True, exist_ok=False)
    started_at = datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y-%m-%d %H:%M:%S")
    started = time.perf_counter()
    intervals = []
    exit_code = 1
    environment = dict(os.environ)
    environment["EMBLEM_CHECK_TIMINGS"] = str(output / "godot-timings.json")
    try:
        with (output / "integrated-check.log").open("x") as log:
            for name, command in (
                ("lint", ["bun", "run", "lint"]),
                ("tools", ["bun", "run", "test:tools"]),
                ("game", ["bun", "run", "test:game"]),
            ):
                print(f"[CHECK] {name}: {output / 'integrated-check.log'}", flush=True)
                log.write(f"[CHECK] {name}\n")
                log.flush()
                begin = time.perf_counter()
                finished = False
                exit_code = 1
                try:
                    result = subprocess.run(
                        command,
                        cwd=ROOT,
                        env=environment,
                        stdout=log,
                        stderr=subprocess.STDOUT,
                        check=False,
                    )
                    exit_code = result.returncode
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
    finally:
        timings = output / "godot-timings.json"
        result = {
            "startedAt": started_at,
            "exitCode": exit_code,
            "seconds": round(time.perf_counter() - started, 3),
            "intervals": intervals,
            "godot": json.loads(timings.read_text()) if timings.exists() else None,
            "measurement": "Wall time around each stage and Godot invocation; no extra execution",
        }
        (output / "timings.json").write_text(json.dumps(result, indent=2) + "\n")
    return exit_code


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New evidence batch directory")
    args = parser.parse_args()
    raise SystemExit(run(args.output.resolve()))


if __name__ == "__main__":
    main()
