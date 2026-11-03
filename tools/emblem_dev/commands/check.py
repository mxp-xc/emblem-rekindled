"""Lint、工具测试及隔离的 Godot 检查。"""

from pathlib import Path
from typing import Annotated

import typer

from emblem_dev.checks import godot, helpers, pipeline

app = typer.Typer(help="Lint、工具测试及隔离的 Godot 检查。")


@app.command("quick")
def check_quick() -> None:
    """执行一次 lint 与工具测试。"""
    raise typer.Exit(pipeline.check("quick"))


@app.command("full")
def check_full(output: Annotated[Path | None, typer.Option()] = None) -> None:
    """执行一次完整检查，可保存计时证据。"""
    raise typer.Exit(pipeline.check("full", output=output))


@app.command("lint")
def check_lint() -> None:
    """检查所有维护的工具、测试和游戏源码格式。"""
    raise typer.Exit(pipeline.lint())


@app.command("tools")
def check_tools() -> None:
    """运行工具行为测试。"""
    raise typer.Exit(pipeline.tools())


@app.command("helpers")
def check_helpers() -> None:
    """检查 Godot 测试 helper 的使用边界。"""
    raise typer.Exit(helpers.check())


@app.command("parse")
def check_parse(timings: Annotated[Path | None, typer.Option()] = None) -> None:
    """导入资源并解析脚本。"""
    raise typer.Exit(godot.check(parse_only=True, timings=timings))


@app.command("game")
def check_game(
    test: Annotated[list[str] | None, typer.Option(help="可重复指定行为测试文件")] = None,
    tests_only: Annotated[bool, typer.Option()] = False,
    timings: Annotated[Path | None, typer.Option()] = None,
    jobs: Annotated[
        int | None, typer.Option(min=1, max=8, help="并行测试工程数；1 表示串行")
    ] = None,
) -> None:
    """执行隔离的 Godot 检查。"""
    options = {"jobs": jobs} if jobs is not None else {}
    raise typer.Exit(
        godot.check(tests=test or (), tests_only=tests_only, timings=timings, **options)
    )


@app.command("restore-config")
def restore_config() -> None:
    """按保护条件恢复中断检查的工程配置。"""
    godot.restore_config()
