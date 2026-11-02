"""Reuse compatible installed dependencies in an existing checkout without installing."""

import argparse
import os
import shutil
import subprocess
from pathlib import Path

CONFIGURATION = (
    "pyproject.toml",
    "uv.lock",
    "package.json",
    "bun.lock",
    ".prettierrc.json",
    ".editorconfig",
    "gdlintrc",
)
EXECUTABLES = (
    ".venv/bin/python",
    ".venv/bin/ruff",
    ".venv/bin/gdformat",
    ".venv/bin/gdlint",
    "node_modules/.bin/prettier",
)
DEPENDENCIES = (".venv", "node_modules")


def prepare(target: Path, source: Path) -> list[Path]:
    target, source = target.resolve(strict=True), source.resolve(strict=True)
    if not target.is_dir() or not source.is_dir() or target == source:
        raise ValueError("Target and dependency source must be distinct existing directories")
    for name in DEPENDENCIES:
        destination = target / name
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(f"Refusing to replace {destination}")
        if not (source / name).is_dir():
            raise ValueError(f"Missing installed dependency directory: {source / name}")
    for name in CONFIGURATION:
        if (target / name).read_bytes() != (source / name).read_bytes():
            raise ValueError(f"Configuration differs: {name}")
    for command in ("git", "uv", "bun", "godot"):
        if not shutil.which(command):
            raise ValueError(f"Required executable is unavailable: {command}")
    for name in EXECUTABLES:
        executable = source / name
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError(f"Installed executable is unavailable: {executable}")
    # Check names without trailing slash: slash-only ignores do not cover symlinks.
    result = subprocess.run(
        ["git", "-C", str(target), "check-ignore", "--no-index", "--stdin"],
        input="\n".join(DEPENDENCIES) + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode or set(result.stdout.splitlines()) != set(DEPENDENCIES):
        raise ValueError(f"Dependency links must be Git-ignored: {result.stderr.strip()}")
    created = []
    try:
        for name in DEPENDENCIES:
            destination = target / name
            destination.symlink_to(source / name, target_is_directory=True)
            created.append(destination)
    except BaseException:
        for destination in reversed(created):
            destination.unlink()
        raise
    return created


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=Path, help="Existing checkout; creates no Git worktree")
    parser.add_argument(
        "--source", type=Path, required=True, help="Checkout with installed dependencies"
    )
    args = parser.parse_args()
    for link in prepare(args.target, args.source):
        print(f"LINK {link} -> {link.readlink()}")


if __name__ == "__main__":
    main()
