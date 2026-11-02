"""查看或初始化已有 checkout。"""

import os
import sys
from pathlib import Path
from typing import Annotated

import typer

from emblem_dev import workspace

app = typer.Typer(help="查看或初始化已有 checkout。")

LOCAL_FILES = ("AGENTS.local.md",)


def status() -> None:
    root = workspace.ROOT
    print(f"Checkout: {root}\nBootstrap source: {Path(workspace.__file__).resolve()}")
    print(f"Python executable: {sys.executable}\nPython prefix: {sys.prefix}")
    for name in (".venv", "node_modules"):
        path = root / name
        state = (
            f"link -> {path.readlink()}"
            if path.is_symlink()
            else (
                "directory" if path.is_dir() else "missing" if not path.exists() else "invalid file"
            )
        )
        print(f"{name}: {state}")
    for name in (".venv/bin/python", ".venv/bin/ruff", "node_modules/.bin/prettier"):
        path = root / name
        available = path.is_file() and os.access(path, os.X_OK)
        print(f"{name}: {'available' if available else 'missing or not executable'}")
    print(f"CodeGraph: {'present' if (root / '.codegraph').is_dir() else 'absent'}")


@app.callback(invoke_without_command=True)
def workspace_default(ctx: typer.Context) -> None:
    if ctx.invoked_subcommand is None:
        status()


@app.command("status")
def workspace_status() -> None:
    """只读查看本 checkout 的依赖状态。"""
    status()


@app.command("init")
def workspace_init(target: Path, hooks: bool = False) -> None:
    """从当前安装初始化另一个已有 checkout，不执行目标 Python 文件。"""
    workspace.setup(target, hooks=hooks)


@app.command("hooks")
def workspace_hooks() -> None:
    """显式安装仓库 hooks。"""
    workspace.install_hooks()


@app.command("reuse-js")
def reuse_js(source: Annotated[Path, typer.Option()]) -> None:
    """显式复用兼容的 node_modules。"""
    root = workspace.checkout(workspace.ROOT)
    source = workspace.checkout(source)
    destination = root / "node_modules"
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(f"Refusing to replace {destination}")
    workspace.compatible_js(root, source)
    workspace.ignored(root, ("node_modules",))
    destination.symlink_to(source / "node_modules", target_is_directory=True)
    typer.echo(f"LINK {destination} -> {destination.readlink()}")


@app.command("copy-local")
def copy_local(source: Annotated[Path, typer.Option()]) -> None:
    """按白名单复制本机配置，拒绝覆盖。"""
    root, source = workspace.checkout(workspace.ROOT), workspace.checkout(source)
    if source == root:
        raise ValueError("Local configuration source must be a distinct checkout")
    # Preflight the complete whitelist before creating any destination.
    for name in LOCAL_FILES:
        origin, destination = source / name, root / name
        if origin.is_symlink() or not origin.is_file():
            raise ValueError(f"Missing real local configuration file: {origin}")
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(f"Refusing to replace {destination}")
    workspace.ignored(root, LOCAL_FILES)
    created = []
    try:
        for name in LOCAL_FILES:
            destination = root / name
            with destination.open("xb") as stream:
                created.append(destination)
                stream.write((source / name).read_bytes())
    except BaseException:
        for destination in reversed(created):
            destination.unlink()
        raise
    for path in created:
        typer.echo(f"COPY {path}")
