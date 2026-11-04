"""Check Godot imports, script parsing, and behavior tests; engine errors fail the command."""

import fcntl
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from emblem_dev.paths import GAME, GODOT
from emblem_dev.process import owned_process, stop

ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR|ERROR):")


_isolation_depth = 0


class _Cancelled(Exception):
    pass


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
    project: Path | None = None,
    cancelled: threading.Event | None = None,
) -> None:
    # This is an error protocol, so consume the engine's unfiltered output.
    command = ["godot", "--headless", "--path", str(project or GAME), *args]
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
                if cancelled is not None and cancelled.is_set():
                    stop(process)
                    process.communicate()
                    raise _Cancelled()
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
    jobs: int | None = None,
) -> int:
    if sum((parse_only, bool(tests), tests_only)) > 1:
        raise ValueError("parse_only, tests and tests_only are mutually exclusive")
    if jobs is not None and not 1 <= jobs <= 12:
        raise ValueError("jobs must be between 1 and 12")
    for test in tests:
        if Path(test).name != test or not test.startswith("test_") or not test.endswith(".gd"):
            raise ValueError("--test expects a test file name, not a path")
    intervals = []
    started = time.perf_counter()
    exit_code = 1
    try:
        with isolated_project():
            run_checks(parse_only, tests, tests_only, intervals, jobs)
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


def run_checks(
    parse_only: bool, tests: tuple[str, ...], tests_only: bool, intervals: list, jobs: int | None
) -> None:
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
        if jobs is not None and jobs > 1 and len(tests) > 1:
            _parallel_tests(list(tests), jobs, intervals)
            return
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
    workers = jobs if jobs is not None else min(12, (os.cpu_count() or 1) + 2)
    if workers > 1 and (jobs is not None or len(scripts) >= 12):
        _parallel_tests([script.name for script in scripts], workers, intervals)
    else:
        for index, script in enumerate(scripts, 1):
            print(f"[TEST {index}/{len(scripts)}] {script.name}", flush=True)
            check(script.name, "--script", str(script.relative_to(GAME)))
    print("[SMOKE] Main scene", flush=True)
    check("main-smoke", "--quit-after", "5")


def _parallel_tests(tests: list[str], jobs: int, intervals: list) -> None:
    """Run separate engines in independent project and user directories."""
    linked = next((path for path in GAME.rglob("*") if path.is_symlink()), None)
    if linked is not None:
        raise RuntimeError(f"Parallel checks refuse project symlinks: {linked}; use --jobs 1")
    cancelled = threading.Event()
    workers: queue.Queue[Path] = queue.Queue()
    with tempfile.TemporaryDirectory(prefix="emblem-check-workers-") as directory:

        def prepare(index: int) -> Path:
            project = Path(directory) / f"worker-{index}"
            _copy_test_project(project)
            config = project / "project.godot"
            text = config.read_text()
            name = f"emblem-check-{uuid.uuid4().hex}"
            text, count = re.subn(r"(?m)^config/name=.*$", f'config/name="{name}"', text)
            if count != 1:
                raise RuntimeError("Expected one config/name in copied project.godot")
            text = re.sub(
                r"(?m)^config/use_custom_user_dir=.*$", "config/use_custom_user_dir=false", text
            )
            config.write_text(text)
            return project

        with ThreadPoolExecutor(max_workers=min(jobs, len(tests))) as setup:
            for project in setup.map(prepare, range(min(jobs, len(tests)))):
                workers.put(project)

        def run(index: int, test: str) -> None:
            project = workers.get()
            started = time.perf_counter()
            finished = False
            try:
                print(f"[TEST {index + 1}/{len(tests)}] {test}", flush=True)
                godot("--script", f"tests/{test}", project=project, cancelled=cancelled)
                finished = True
            finally:
                workers.put(project)
                intervals.append(
                    {
                        "name": test,
                        "seconds": round(time.perf_counter() - started, 3),
                        "finished": finished,
                    }
                )

        with ThreadPoolExecutor(max_workers=jobs) as executor:
            pending = {}
            next_index = 0
            failure = None
            try:
                while next_index < len(tests) or pending:
                    while failure is None and next_index < len(tests) and len(pending) < jobs:
                        future = executor.submit(run, next_index, tests[next_index])
                        pending[future] = next_index
                        next_index += 1
                    if not pending:
                        break
                    done, _ = wait(pending, return_when=FIRST_COMPLETED)
                    for future in done:
                        pending.pop(future)
                        try:
                            future.result()
                        except _Cancelled:
                            pass
                        except BaseException as error:
                            if failure is None:
                                failure = error
                                cancelled.set()
                    if failure is not None and not pending:
                        raise failure
            finally:
                cancelled.set()


def _copy_test_project(project: Path) -> None:
    # macOS can make independent copy-on-write clones without copying every byte.
    if sys.platform == "darwin":
        with owned_process(
            ["cp", "-cR", str(GAME), str(project)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ) as process:
            copied = process.wait() == 0
        if copied:
            recovery = project / ".godot/check-recovery"
            if recovery.is_dir() and not recovery.is_symlink():
                shutil.rmtree(recovery)
            (project / ".godot/check.lock").unlink(missing_ok=True)
            return
        if project.exists():
            shutil.rmtree(project)
    shutil.copytree(GAME, project, ignore=shutil.ignore_patterns("check.lock", "check-recovery"))
