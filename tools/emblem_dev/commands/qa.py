"""平台 QA 与受保护的记录恢复。"""

import importlib.util
import json
import sys
from pathlib import Path
from typing import Annotated

import typer

from emblem_dev.commands import first_battle, state, web_bridge
from emblem_dev.qa import android, records
from emblem_dev.qa.client import PACKAGE, Playtest

app = typer.Typer(help="平台 QA 与受保护的记录恢复。")
app.add_typer(state.app, name="state")
app.add_typer(first_battle.app)
app.add_typer(web_bridge.app)


@app.command("android")
def qa_android(
    apk: Annotated[Path, typer.Option()],
    build: Annotated[str, typer.Option()],
    fixtures: Annotated[Path, typer.Option()],
    cases: Annotated[Path, typer.Option()],
    case: Annotated[list[str], typer.Option()],
    output: Annotated[Path, typer.Option()],
    serial: Annotated[str, typer.Option()],
    adb: str = "adb",
    stop_emulator: bool = False,
) -> None:
    """运行显式指定可信 case 的 Android 批次。"""
    spec = importlib.util.spec_from_file_location("chapter_qa_cases", cases)
    if spec is None or spec.loader is None:
        raise ValueError("Could not load case module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    flow = getattr(module, "Flow", android.Flow)(
        Playtest(serial, adb),
        output,
        json.loads((fixtures / "fixtures.json").read_text()),
        json.loads((fixtures / "manifest.json").read_text()),
        build,
    )
    android.run_cases(flow, case, module.CASES, apk, stop_emulator=stop_emulator)
    print("PASS protected Android", case, flush=True)


@app.command("restore-records")
def restore_records(backup: Path, serial: str | None = None) -> None:
    records.load_backup(backup)
    client = Playtest(serial)
    client.adb("shell", "am", "force-stop", PACKAGE)
    records.restore_records(client, backup)
    print("Original record bytes restored and verified")
