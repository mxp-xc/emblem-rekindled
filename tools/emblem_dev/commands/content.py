"""显式导入原始内容。"""

import json
from pathlib import Path
from typing import Annotated

import typer

from emblem_dev.content import chapter1, configuration, definitions
from emblem_dev.paths import ROOT

app = typer.Typer(help="显式导入原始内容。")


@app.command("chapter-1")
def import_chapter(
    emulator: Path | None = None,
    battle: Annotated[str | None, typer.Option(help="初章关卡 m0～m19。")] = None,
    route: int | None = None,
    chapter: Path = ROOT / "game/content/chapter_1",
    native_input: Annotated[list[Path] | None, typer.Option()] = None,
    report: Path | None = None,
    jdk: Path | None = None,
    native_output: Path | None = None,
    plan: bool = False,
    refresh_motion: bool = False,
    adaptive: bool = False,
    evidence_output: Path | None = None,
    encounter_step: Annotated[
        int | None, typer.Option(help="遭遇战采样时已完成的主线节点数。")
    ] = None,
) -> None:
    """导入初章资源，或只输出计划。"""
    native_input = native_input or ()
    chapter = chapter.resolve()
    if plan:
        requirements = configuration.motion_requirements(chapter)
        requirements["missingProfiles"] = configuration.recruit_binding_plan(chapter)[
            "missingProfiles"
        ]
        if battle in configuration.ENCOUNTER_BATTLES:
            requirements["encounterContexts"] = configuration.recruit_contexts(chapter, battle)
        typer.echo(json.dumps(requirements, ensure_ascii=False, indent=2))
        return
    if not battle or not emulator:
        raise ValueError("--battle and --emulator are required when not using --plan")
    extra_sampling = battle in configuration.ENCOUNTER_BATTLES and native_output is not None
    if battle not in tuple(f"m{index}" for index in range(20)):
        raise ValueError(f"Unverified chapter-1 battle: {battle}")
    if extra_sampling and route is None:
        raise ValueError("Encounter sampling requires an explicit route")
    if encounter_step is not None and not extra_sampling:
        raise ValueError("--encounter-step requires isolated encounter sampling")
    if extra_sampling and adaptive and battle != "m19":
        raise ValueError("Encounter adaptive sampling is not verified")
    if route is not None and route not in range(8):
        raise ValueError(f"Unverified chapter-1 route: {route}")
    if extra_sampling and encounter_step is not None:
        entry = json.loads((chapter / "chapter.json").read_text())
        bank = json.loads((chapter.parents[1] / entry["library"][6:]).read_text())
        route_length = len(bank["storyCommon"]["world"]["routes"][route])
        if not 6 <= encounter_step <= route_length:
            raise ValueError(f"Invalid encounter world step: {encounter_step}")
    if native_output and native_input:
        raise ValueError("--native-output and --native-input are separate workflows")
    if native_input and refresh_motion:
        raise ValueError("--refresh-motion requires fresh native sampling, not prepared inputs")
    if adaptive and (not native_output or native_input or refresh_motion):
        raise ValueError("--adaptive requires isolated --native-output")
    if evidence_output and native_output:
        raise ValueError("--evidence-output requires a chapter update")
    reuse_chapter = None if refresh_motion else chapter
    source = ROOT / "reference/original-jars/chapter-1.jar"
    deployment = configuration.normalize_deployment(
        chapter, definitions.read_deployment(source, int(battle[1:]))
    )
    if native_output:
        route = (
            route
            if route is not None
            else configuration.recruit_contexts(chapter, battle)[0]["route"]
        )
        chapter1.export_native(
            source,
            native_output.resolve(),
            emulator.resolve(),
            deployment,
            route,
            jdk,
            reuse_chapter,
            adaptive=adaptive,
            encounter_step=encounter_step,
        )
        typer.echo(json.dumps({"nativeOutput": str(native_output)}, ensure_ascii=False, indent=2))
        return
    authored = chapter / "authored/battles" / f"{battle}.json"
    if not authored.is_file():
        raise ValueError(f"Create and verify the authored configuration first: {authored}")
    result = chapter1.update_chapter(
        chapter,
        battle,
        emulator.resolve(),
        route,
        jdk,
        native_input,
        refresh_motion=refresh_motion,
        evidence_output=evidence_output,
    )
    if report:
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    summary = {key: value for key, value in result.items() if key != "contexts"}
    summary["contexts"] = [
        {
            "battleId": context["battleId"],
            "route": context["route"],
            "preparedInput": context["preparedInput"],
            **{
                key: value
                for key, value in context["presentation"].items()
                if key not in ("bindings", "recipes")
            },
        }
        for context in result["contexts"]
    ]
    typer.echo(json.dumps(summary, ensure_ascii=False, indent=2))


@app.command("deployment")
def import_deployment(source: Path, output: Path, battle: Annotated[int, typer.Option()]) -> None:
    """从定义文件导出关卡部署。"""
    deployment = definitions.read_deployment(source, battle)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(deployment["units"], ensure_ascii=False, indent=2) + "\n")
    typer.echo(json.dumps(deployment, ensure_ascii=False, indent=2))
