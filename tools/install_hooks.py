"""Opt this checkout into repository hooks, preserving any existing hook configuration."""

import argparse
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def install(root: Path) -> None:
    def git(*args):
        return subprocess.run(
            ["git", "-C", str(root), *args], capture_output=True, text=True, check=False
        )

    configured = git("config", "--get", "core.hooksPath")
    if configured.returncode not in (0, 1):
        raise RuntimeError(configured.stderr)
    path = configured.stdout.strip()
    if path and path != ".githooks":
        raise RuntimeError(f"Existing core.hooksPath retained: {path}; integrate hooks manually")
    if not path:
        hooks_result = git("rev-parse", "--git-path", "hooks")
        if hooks_result.returncode:
            raise RuntimeError(hooks_result.stderr)
        hooks = Path(hooks_result.stdout.strip())
        if not hooks.is_absolute():
            hooks = root / hooks
        active = [p.name for p in hooks.glob("*") if p.is_file() and not p.name.endswith(".sample")]
        if active:
            raise RuntimeError(f"Existing hooks retained: {', '.join(active)}; integrate manually")
    for name in ("pre-commit", "pre-push"):
        hook = root / ".githooks" / name
        if not hook.is_file():
            raise RuntimeError(f"Missing repository hook: {hook}")
        hook.chmod(hook.stat().st_mode | 0o111)
    result = git("config", "--local", "core.hooksPath", ".githooks")
    if result.returncode:
        raise RuntimeError(result.stderr)
    print("Repository hooks enabled: pre-commit quick checks; pre-push full checks")


def main() -> None:
    argparse.ArgumentParser(description=__doc__).parse_args()
    install(ROOT)


if __name__ == "__main__":
    main()
