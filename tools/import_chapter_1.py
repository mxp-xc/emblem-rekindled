"""Import local chapter-1 resources with the pinned, local FreeJ2ME renderer.

Run from any directory with uv run tools/import_chapter_1.py --emulator <jar>.
Does not download, modify source JARs, or read historical snapshots.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from chapter_1_definitions import export_definitions
from chapter_assets import (
    owned_output_paths,
    share_textures,
    texture_import_parameters,
    texture_import_settings,
)

ROOT = Path(__file__).resolve().parents[1]
EMULATOR_SHA = "9c59b74ae8e4fad205e5ff186940c24c53480918a3b180bb551559db9be3e7ff"


def run(*args: str | Path, cwd: Path) -> None:
    subprocess.run(["rtk", *map(str, args)], cwd=cwd, check=True)


def rebase_textures(value, source: Path, target: Path):
    """Inherited story PNGs keep their meaning when used by a different battle."""
    if isinstance(value, dict):
        return {key: rebase_textures(item, source, target) for key, item in value.items()}
    if isinstance(value, list):
        return [rebase_textures(item, source, target) for item in value]
    if (
        isinstance(value, str)
        and value.endswith(".png")
        and not value.startswith("res://")
        and (source / value).is_file()
    ):
        return os.path.relpath((source / value).resolve(), target.resolve())
    return value


def finish_second_battle(output: Path) -> None:
    shared = ROOT / "game/content/chapter_1/generated"
    story_path = shared / "story/manifest.json"
    original = json.loads(story_path.read_text())
    target_story = shared / "battles/m1/story"
    inherited = rebase_textures(original, story_path.parent, target_story)
    fragment_path = output / "story/battle.json"
    fragment = json.loads(fragment_path.read_text())
    world = dict(fragment["world"])
    world["texture"] = os.path.relpath(target_story / world["texture"], story_path.parent)
    story = {**inherited, **fragment}
    story["images"] = {**inherited["images"], **fragment["images"]}
    story["sequences"] = {
        key: inherited["sequences"][key] for key in ("boot", "newGame", "defeat")
    } | fragment["sequences"]
    story.pop("reinforcementTrigger", None)
    (output / "story/manifest.json").write_text(
        json.dumps(story, ensure_ascii=False, indent=2) + "\n"
    )
    fragment_path.unlink()
    prefix = "res://content/chapter_1/generated/"
    local = prefix + "battles/m1/"
    entry = {
        "battleId": "m1",
        "map": local + "map.json",
        "units": local + "units.json",
        "rules": prefix + "rules.json",
        "spawns": local + "spawns.json",
        "mapAnimations": local + "map_animations.json",
        "battleArt": local + "battle/manifest.json",
        "battleClips": local + "battle/clips/manifest.json",
        "mapTexture": local + "map.png",
        "spriteDirectory": local,
        "story": local + "story/manifest.json",
        "interface": local + "ui/manifest.json",
        "music": prefix + "map_music.ogg",
        "battleMusic": prefix + "battle_music.ogg",
        "titleMusic": prefix + "title_music.ogg",
        "worldMusic": prefix + "world_music.ogg",
        "victoryMusic": prefix + "victory_music.ogg",
        "defeatMusic": prefix + "defeat_music.ogg",
        "controls": "res://content/chapter_1/authored/controls.json",
    }
    (output / "battle.json").write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n")
    # The shared first-battle story exposes the same proven world graph and event contract.
    original.update(
        world=world,
        worldNode=0,
        battleNumber=1,
        turnEvents=[
            {
                "id": "reinforcements",
                "afterEnemyPhaseOfRound": 1,
                "unitIds": [13, 14, 15],
                "sequence": "reinforcements",
            }
        ],
        aiChanges=[],
    )
    original.pop("reinforcementTrigger", None)
    story_path.write_text(json.dumps(original, ensure_ascii=False, indent=2) + "\n")


def publish_battle(output: Path, target: Path, chapter: Path) -> dict[str, int]:
    """Publish only this owner's files, preserving per-source texture import settings."""
    output, target, chapter = output.resolve(), target.resolve(), chapter.resolve()
    provenance = json.loads((output / "provenance.json").read_text())
    previous = (
        json.loads((target / "provenance.json").read_text())
        if (target / "provenance.json").exists()
        else {"outputs": [], "textureSources": {}}
    )
    before = owned_output_paths(target, previous["outputs"])
    incoming = owned_output_paths(target, provenance["outputs"])
    source_paths = owned_output_paths(output, provenance["outputs"])
    actual_files = {p.resolve() for p in output.rglob("*") if p.is_file()}
    allowed_files = {output / "provenance.json", *source_paths}
    allowed_files.update(Path(str(p) + ".import") for p in source_paths if p.suffix != ".json")
    if not set(source_paths).issubset(actual_files) or not actual_files.issubset(allowed_files):
        raise ValueError("Incoming files disagree with the ownership list")
    sources = {
        name: value
        for name, value in previous.get("textureSources", {}).items()
        if name in provenance["outputs"]
    }
    for name, value in sources.items():
        texture = (chapter / value).resolve()
        if (
            not texture.is_relative_to((chapter / "generated/shared").resolve())
            or not texture.is_file()
        ):
            raise ValueError(f"Invalid shared source texture: {value}")
        owned_output_paths(target, [name])
    # Check the existing chapter before overwriting or removing another owner's files.
    share_textures(chapter, dry_run=True)
    for name, value in sources.items():
        sidecar = Path(str(output / name) + ".import")
        if not sidecar.exists():
            sidecar.write_bytes(
                texture_import_settings(texture_import_parameters(chapter / value, {}))
            )
    provenance["textureSources"] = sources
    (output / "provenance.json").write_text(
        json.dumps(provenance, ensure_ascii=False, indent=2) + "\n"
    )
    shutil.copytree(output, target, dirs_exist_ok=True)
    for path in set(before) - set(incoming):
        path.unlink(missing_ok=True)
        Path(str(path) + ".import").unlink(missing_ok=True)
    return share_textures(chapter)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulator", type=Path, required=True)
    parser.add_argument("--battle", choices=("m0", "m1"), default="m0")
    parser.add_argument(
        "--jdk", type=Path, help="JDK bin directory; defaults to java/javac on PATH"
    )
    args = parser.parse_args()
    emulator = args.emulator.resolve()
    if hashlib.sha256(emulator.read_bytes()).hexdigest() != EMULATOR_SHA:
        raise ValueError("FreeJ2ME-Plus SHA-256 mismatch; use the documented pinned artifact")
    battle = int(args.battle[1:])
    target = ROOT / "game/content/chapter_1/generated"
    if battle:
        target = target / "battles" / args.battle
    if (target / "provenance.json").exists():
        owned_output_paths(target, json.loads((target / "provenance.json").read_text())["outputs"])
    java = args.jdk / "java" if args.jdk else "java"
    javac = args.jdk / "javac" if args.jdk else "javac"
    with tempfile.TemporaryDirectory(prefix="emblem-import-") as directory:
        work = Path(directory)
        output = work / "generated"
        export_definitions(ROOT / "reference/original-jars/chapter-1.jar", output, battle)
        if battle:
            shutil.copytree(
                ROOT / "game/content/chapter_1/generated/story",
                output / "story",
                ignore=shutil.ignore_patterns("*.import", "*.uid"),
            )
        spawns = json.loads((output / "spawns.json").read_text())
        allied_pool = {
            int(item) for spawn in spawns if spawn["faction"] != 2 for item in spawn["itemChoices"]
        }
        allied_pool.update(int(spawn["dropTemplateId"]) for spawn in spawns)
        if battle:
            # A carried/bought weapon may be traded to any compatible ally in the new battle.
            allied_pool.update(range(1, 53))
        lines = []
        for spawn in spawns:
            pool = set(spawn["itemChoices"]) | {spawn["dropTemplateId"]}
            if spawn["faction"] != 2:
                pool |= allied_pool
            weapons = sorted({0} | {int(item) for item in pool if 0 < int(item) <= 52})
            lines.append(f"{spawn['id']}\t{','.join(map(str, weapons))}")
        variants = work / "battle_variants.tsv"
        variants.write_text("\n".join(lines) + "\n")
        run(
            javac,
            "-cp",
            emulator,
            "-d",
            work,
            ROOT / "tools/ImportChapter1.java",
            ROOT / "tools/Chapter1Rules.java",
            ROOT / "tools/Chapter1MapAssets.java",
            ROOT / "tools/Chapter1BattleAssets.java",
            ROOT / "tools/Chapter1BattleClips.java",
            ROOT / "tools/Chapter1Story.java",
            ROOT / "tools/Chapter1Interface.java",
            cwd=work,
        )
        run(
            java,
            "-Djava.awt.headless=true",
            "-Dfile.encoding=ISO_8859_1",
            "-cp",
            f"{work}:{emulator}",
            "ImportChapter1",
            ROOT / "reference/original-jars/chapter-1.jar",
            output,
            variants,
            str(battle),
            cwd=work,
        )
        if not battle:
            exports = "java.desktop/com.sun.media.sound=ALL-UNNAMED"
            run(
                javac,
                "--add-exports",
                exports,
                "-d",
                work,
                ROOT / "tools/RenderMidi.java",
                cwd=work,
            )
        for stem in (
            ()
            if battle
            else (
                "map_music",
                "battle_music",
                "title_music",
                "world_music",
                "victory_music",
                "defeat_music",
            )
        ):
            run(
                java,
                "--add-exports",
                exports,
                "-cp",
                work,
                "RenderMidi",
                output / f"{stem}.mid",
                work / f"{stem}.wav",
                cwd=work,
            )
            run(
                "ffmpeg",
                "-v",
                "error",
                "-y",
                "-i",
                work / f"{stem}.wav",
                "-c:a",
                "vorbis",
                "-strict",
                "-2",
                "-q:a",
                "4",
                output / f"{stem}.ogg",
                cwd=work,
            )
            (output / f"{stem}.mid").unlink()
        if battle:
            finish_second_battle(output)
        provenance = json.loads((output / "provenance.json").read_text())
        provenance.update(
            emulatorSha256=EMULATOR_SHA,
            audio=(
                "References existing shared chapter-1 Ogg tracks; no audio is regenerated for m1"
                if battle
                else "p.mid/battle.mid/title.mid/world.mid/win.mid/over.mid rendered offline "
                "with JDK generated default soundbank; timbre is not original phone synthesis"
            ),
        )
        java_runtime = subprocess.check_output(
            ["rtk", str(java), "-version"], text=True, stderr=subprocess.STDOUT
        ).splitlines()[0]
        provenance["javaRuntime"] = java_runtime
        provenance["audioRenderer"] = (
            json.loads((ROOT / "game/content/chapter_1/generated/provenance.json").read_text())[
                "audioRenderer"
            ]
            if battle
            else java_runtime
        )
        provenance["outputs"] = [
            path.relative_to(output).as_posix()
            for path in sorted(output.rglob("*"))
            if path.is_file() and path.name != "provenance.json"
        ]
        (output / "provenance.json").write_text(
            json.dumps(provenance, ensure_ascii=False, indent=2) + "\n"
        )
        shared_result = publish_battle(output, target, ROOT / "game/content/chapter_1")
        print(f"Chapter textures: {shared_result}")
    print(f"Imported chapter-1 into {target}")


if __name__ == "__main__":
    main()
