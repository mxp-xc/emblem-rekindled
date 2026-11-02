"""Initialize an existing checkout; never create a worktree or share Python environments."""

import os
import shutil
import subprocess
import tomllib
from pathlib import Path

from .paths import ROOT

CONFIGURATION = (
    "pyproject.toml",
    "uv.lock",
    "package.json",
    "bun.lock",
    ".prettierrc.json",
    ".editorconfig",
    "gdlintrc",
)
JS_CONFIGURATION = ("package.json", "bun.lock", ".prettierrc.json")


def checkout(path: Path) -> Path:
    root = path.resolve(strict=True)
    if not root.is_dir() or not (root / ".git").exists():
        raise ValueError(f"Not an existing checkout: {root}")
    with (root / "pyproject.toml").open("rb") as stream:
        project = tomllib.load(stream).get("project", {})
    if project.get("name") != "emblem-rekindled-tools":
        raise ValueError(f"Not an emblem-rekindled checkout: {root}")
    for name in CONFIGURATION:
        if not (root / name).is_file():
            raise ValueError(f"Missing checkout configuration: {root / name}")
    return root


def ignored(root: Path, names: tuple[str, ...]) -> None:
    # Names without trailing slash: slash-only ignores do not cover symlinks.
    result = subprocess.run(
        ["git", "-C", str(root), "check-ignore", "--no-index", "--stdin"],
        input="\n".join(names) + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode or set(result.stdout.splitlines()) != set(names):
        raise ValueError(f"Paths must be Git-ignored: {names}; {result.stderr.strip()}")


def compatible_js(target: Path, source: Path) -> None:
    source = checkout(source)
    if source == target:
        raise ValueError("Dependency source must be a distinct checkout")
    for name in JS_CONFIGURATION:
        if (target / name).read_bytes() != (source / name).read_bytes():
            raise ValueError(f"Configuration differs: {name}")
    modules = source / "node_modules"
    if modules.is_symlink() or not modules.is_dir():
        raise ValueError(f"Source node_modules must be a real directory: {modules}")
    executable = modules / ".bin/prettier"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError(f"Installed executable is unavailable: {executable}")


def setup(target: Path = ROOT, *, hooks: bool = False) -> None:
    checkout(ROOT)
    root = checkout(target)
    environment = root / ".venv"
    if environment.is_symlink() or (environment.exists() and not environment.is_dir()):
        raise ValueError(f"Python environment must be a real local directory: {environment}")
    modules = root / "node_modules"
    linked_js = modules.is_symlink()
    if linked_js:
        resolved = modules.resolve(strict=True)
        if resolved.name != "node_modules":
            raise ValueError(f"Invalid node_modules link: {modules}")
        compatible_js(root, resolved.parent)
    elif modules.exists() and not modules.is_dir():
        raise ValueError(f"node_modules must be a directory: {modules}")
    for command in ("git", "uv", *(() if linked_js else ("bun",))):
        if not shutil.which(command):
            raise ValueError(f"Required executable is unavailable: {command}")
    ignored(root, (".venv", "node_modules"))
    env = os.environ.copy()
    for name in ("VIRTUAL_ENV", "UV_ACTIVE", "PYTHONHOME", "PYTHONPATH"):
        env.pop(name, None)
    env["UV_PROJECT_ENVIRONMENT"] = str(environment)
    env["UV_PYTHON_DOWNLOADS"] = "never"
    subprocess.run(
        ["uv", "sync", "--locked", "--project", str(root)], cwd=root, env=env, check=True
    )
    if linked_js:
        print(f"Validated node_modules link; installation skipped: {modules} -> {resolved}")
    else:
        subprocess.run(["bun", "install", "--frozen-lockfile"], cwd=root, env=env, check=True)
    if hooks:
        print("Hooks use Git --local config, shared by linked worktrees of this repository.")
        install_hooks(root)


def install_hooks(root: Path = ROOT) -> None:
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
    print("Repository hook path configured; commit and push do not run checks automatically")
