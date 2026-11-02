"""Check Godot imports, script parsing, and behavior tests; engine errors fail the command."""

import argparse
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import time
import uuid
from contextlib import contextmanager, suppress
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR|ERROR):")


_isolation_depth = 0


@contextmanager
def configuration_lock():
    cache = GAME / ".godot"
    cache.mkdir(exist_ok=True)
    # Lock a stable inode: never unlink it while another runner may be waiting.
    with (cache / "check.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("Another Godot check owns project.godot") from error
        yield cache / "check-recovery"


def restore_configuration(recovery: Path, *, require_inactive_owner: bool = False) -> None:
    if require_inactive_owner:
        owner = json.loads((recovery / "owner.json").read_text())
        try:
            os.kill(owner["pid"], 0)
        except ProcessLookupError:
            pass
        else:
            raise RuntimeError(
                f"Godot check owner {owner['pid']} is still alive. Recovery: {recovery}"
            )
    project = GAME / "project.godot"
    original = (recovery / "original.godot").read_bytes()
    isolated = (recovery / "isolated.godot").read_bytes()
    if project.read_bytes() not in (original, isolated):
        raise RuntimeError(f"project.godot changed; refusing to overwrite it. Recovery: {recovery}")
    project.write_bytes(original)
    if project.read_bytes() != original:
        raise RuntimeError(f"Failed to restore project.godot original bytes. Recovery: {recovery}")
    for name in ("original.godot", "isolated.godot", "owner.json"):
        (recovery / name).unlink()
    recovery.rmdir()


@contextmanager
def isolated_project():
    """Give engine checks a disposable user:// identity; restore exact config bytes."""
    global _isolation_depth
    if _isolation_depth:
        yield
        return
    with configuration_lock() as recovery:
        if recovery.exists():
            raise RuntimeError(
                f"Unfinished Godot check: {recovery}. Run check_godot.py --restore-config first"
            )
        project = GAME / "project.godot"
        original = project.read_bytes()
        text = original.decode()
        name = f"emblem-check-{uuid.uuid4().hex}"
        changed, count = re.subn(r"(?m)^config/name=.*$", f'config/name="{name}"', text)
        if count != 1:
            raise RuntimeError("Expected one config/name in project.godot")
        # A configured custom directory must never override the disposable name.
        changed = re.sub(
            r"(?m)^config/use_custom_user_dir=.*$", "config/use_custom_user_dir=false", changed
        )
        recovery.mkdir()
        (recovery / "original.godot").write_bytes(original)
        (recovery / "isolated.godot").write_bytes(changed.encode())
        (recovery / "owner.json").write_text(
            json.dumps(
                {
                    "pid": os.getpid(),
                    "project": str(project),
                    "identity": name,
                    "startedAt": datetime.now(ZoneInfo("Asia/Shanghai")).strftime(
                        "%Y-%m-%d %H:%M:%S"
                    ),
                },
                indent=2,
            )
            + "\n"
        )
        _isolation_depth = 1
        try:
            project.write_bytes(changed.encode())
            yield
        finally:
            _isolation_depth = 0
            restore_configuration(recovery)


def godot(
    *args: str,
    timeout_seconds: float = 60,
    ready_file: Path | None = None,
    startup_seconds: float = 30,
) -> None:
    # This is an error protocol, so consume the engine's unfiltered output.
    command = ["godot", "--headless", "--path", str(GAME), *args]
    with (
        isolated_project(),
        subprocess.Popen(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        ) as process,
    ):
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
    group.add_argument("--restore-config", action="store_true", help="Restore an interrupted check")
    parser.add_argument("--timings", type=Path, default=os.environ.get("EMBLEM_CHECK_TIMINGS"))
    args = parser.parse_args()
    if args.restore_config:
        with configuration_lock() as recovery:
            restore_configuration(recovery, require_inactive_owner=True)
        print("RESTORED project.godot original bytes")
        return
    intervals = []
    started = time.perf_counter()
    exit_code = 1
    try:
        with isolated_project():
            run_checks(args, parser, intervals)
        exit_code = 0
    except SystemExit as error:
        exit_code = error.code if isinstance(error.code, int) else 1
        raise
    except KeyboardInterrupt:
        exit_code = 130
        raise
    finally:
        if args.timings:
            args.timings.parent.mkdir(parents=True, exist_ok=True)
            args.timings.write_text(
                json.dumps(
                    {
                        "exitCode": exit_code,
                        "seconds": round(time.perf_counter() - started, 3),
                        "intervals": intervals,
                    },
                    indent=2,
                )
                + "\n"
            )


def run_checks(args: argparse.Namespace, parser: argparse.ArgumentParser, intervals: list) -> None:
    def check(name: str, *command: str) -> None:
        started = time.perf_counter()
        finished = False
        try:
            godot(*command)
            finished = True
        finally:
            intervals.append(
                {
                    "name": name,
                    "seconds": round(time.perf_counter() - started, 3),
                    "finished": finished,
                }
            )

    if args.test:
        for test in args.test:
            if Path(test).name != test or not test.startswith("test_") or not test.endswith(".gd"):
                parser.error("--test expects a test file name, not a path")
            print(f"[TEST] {test}", flush=True)
            check(test, "--script", f"tests/{test}")
        return
    if not args.tests_only:
        print("[IMPORT] Project resources", flush=True)
        check("import", "--editor", "--import")
        scripts = [
            os.path.relpath(script, GAME)
            for script in sorted([*GAME.rglob("*.gd"), *(ROOT / "tools").glob("*.gd")])
            if ".godot" not in script.parts
        ]
        print(f"[PARSE] {len(scripts)} scripts in one engine", flush=True)
        check("parse", "--script", "../tools/parse_scripts.gd", "--", *scripts)
    if args.parse_only:
        return
    scripts = sorted((GAME / "tests").glob("test_*.gd"))
    for index, script in enumerate(scripts, 1):
        print(f"[TEST {index}/{len(scripts)}] {script.name}", flush=True)
        check(script.name, "--script", str(script.relative_to(GAME)))
    print("[SMOKE] Main scene", flush=True)
    check("main-smoke", "--quit-after", "5")


if __name__ == "__main__":
    main()
