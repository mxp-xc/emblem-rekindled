"""Run actual external programs and clean up only the process groups we own."""

import os
import signal
import subprocess
from contextlib import contextmanager, suppress
from pathlib import Path


def stop(process: subprocess.Popen) -> None:
    if getattr(process, "_emblem_group_stopped", False):
        return
    with suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGKILL)
    process._emblem_group_stopped = True


@contextmanager
def owned_process(command: list[str], **kwargs):
    """Keep descendants from surviving success, failure, or Python interruption."""
    with subprocess.Popen(command, start_new_session=True, **kwargs) as process:
        try:
            yield process
        finally:
            stop(process)
            process.wait()


def run(command: list[str], *, cwd: Path, stdout=None) -> int:
    with owned_process(command, cwd=cwd, stdout=stdout, stderr=subprocess.STDOUT) as process:
        code = process.wait()
    return code if code >= 0 else 128 - code
