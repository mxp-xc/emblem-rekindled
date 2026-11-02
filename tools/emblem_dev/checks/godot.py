"""Check Godot imports, script parsing, and behavior tests; engine errors fail the command."""

import fcntl
import json
import os
import re
import subprocess
import sys
import time
import uuid
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from emblem_dev.paths import GAME, GODOT
from emblem_dev.process import owned_process, stop

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
                f"Unfinished Godot check: {recovery}. Run er check restore-config first"
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
        owned_process(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
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
                    stop(process)
                    output, _ = process.communicate()
                    print(output, file=sys.stderr)
                    raise SystemExit(failure_code) from None
        except subprocess.TimeoutExpired as error:
            # Terminate the whole owned group, including engine subprocesses.
            stop(process)
            output, _ = process.communicate()
            print(output, file=sys.stderr)
            phase = "runtime" if started else "startup"
            print(f"Godot {phase} timed out: {' '.join(args)}", file=sys.stderr)
            raise SystemExit(1) from error
        except KeyboardInterrupt:
            stop(process)
            process.communicate()
            raise
        if process.returncode or ENGINE_ERROR.search(output):
            print(output, file=sys.stderr)
            raise SystemExit(process.returncode or 1)
    passes = [line for line in output.splitlines() if line.startswith("PASS ")]
    print("\n".join(passes) if passes else "OK " + " ".join(args), flush=True)


def restore_config() -> None:
    with configuration_lock() as recovery:
        restore_configuration(recovery, require_inactive_owner=True)
    print("RESTORED project.godot original bytes")


def check(
    *,
    parse_only: bool = False,
    tests: tuple[str, ...] = (),
    tests_only: bool = False,
    timings: Path | None = None,
) -> int:
    if sum((parse_only, bool(tests), tests_only)) > 1:
        raise ValueError("parse_only, tests and tests_only are mutually exclusive")
    for test in tests:
        if Path(test).name != test or not test.startswith("test_") or not test.endswith(".gd"):
            raise ValueError("--test expects a test file name, not a path")
    intervals = []
    started = time.perf_counter()
    exit_code = 1
    try:
        with isolated_project():
            run_checks(parse_only, tests, tests_only, intervals)
        exit_code = 0
    except SystemExit as error:
        exit_code = error.code if isinstance(error.code, int) else 1
        raise
    except KeyboardInterrupt:
        exit_code = 130
        raise
    finally:
        if timings:
            timings.parent.mkdir(parents=True, exist_ok=True)
            timings.write_text(
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

    return exit_code


def run_checks(parse_only: bool, tests: tuple[str, ...], tests_only: bool, intervals: list) -> None:
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

    if tests:
        for test in tests:
            print(f"[TEST] {test}", flush=True)
            check(test, "--script", f"tests/{test}")
        return
    if not tests_only:
        print("[IMPORT] Project resources", flush=True)
        check("import", "--editor", "--import")
        scripts = [
            os.path.relpath(script, GAME)
            for script in sorted([*GAME.rglob("*.gd"), *GODOT.glob("*.gd")])
            if ".godot" not in script.parts
        ]
        print(f"[PARSE] {len(scripts)} scripts in one engine", flush=True)
        check("parse", "--script", str(GODOT / "parse_scripts.gd"), "--", *scripts)
    if parse_only:
        return
    scripts = sorted((GAME / "tests").glob("test_*.gd"))
    for index, script in enumerate(scripts, 1):
        print(f"[TEST {index}/{len(scripts)}] {script.name}", flush=True)
        check(script.name, "--script", str(script.relative_to(GAME)))
    print("[SMOKE] Main scene", flush=True)
    check("main-smoke", "--quit-after", "5")
