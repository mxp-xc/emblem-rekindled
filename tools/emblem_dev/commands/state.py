"""读取 Android 状态或显式修改速率。"""

import json
from typing import Annotated

import typer

from emblem_dev.qa import client

app = typer.Typer(help="读取 Android 状态或显式修改速率。")

SPEED_HELP = "合法速率：(" + ",".join(map(str, client.SPEEDS)) + ")"


def speed_parameter(value: int) -> int:
    """Validate speed during Typer parsing, before device operations."""
    try:
        return client.validate_speed(value)
    except ValueError as error:
        raise typer.BadParameter(str(error)) from error


@app.command("read")
def state_read(
    serial: str | None = None, adb: str = "adb", ready: bool = False, timeout: float = 30
) -> None:
    """读取实时状态，不保存游戏。"""
    typer.echo(
        json.dumps(
            client.Playtest(serial, adb).read(ready=ready, timeout=timeout),
            ensure_ascii=False,
            indent=2,
        )
    )


@app.command("speed")
def state_speed(
    value: Annotated[int, typer.Argument(callback=speed_parameter, help=SPEED_HELP)],
    serial: str | None = None,
    adb: str = "adb",
) -> None:
    client.validate_speed(value)
    state = client.AndroidInput(client.Playtest(serial, adb)).set_speed(value)
    typer.echo(json.dumps(state, ensure_ascii=False, indent=2))
