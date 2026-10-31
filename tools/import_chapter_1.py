"""Import local chapter-1 resources with the pinned, local FreeJ2ME renderer.

Run from any directory with uv run tools/import_chapter_1.py --emulator <jar>.
Does not download, modify source JARs, or read historical snapshots.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from chapter_1_definitions import export_definitions

ROOT = Path(__file__).resolve().parents[1]
EMULATOR_SHA = "9c59b74ae8e4fad205e5ff186940c24c53480918a3b180bb551559db9be3e7ff"


def run(*args: str | Path, cwd: Path) -> None:
    subprocess.run(["rtk", *map(str, args)], cwd=cwd, check=True)


def output_digest(path: Path) -> str:
    data = path.read_bytes()
    if path.suffix == ".json":
        data = json.dumps(json.loads(data), sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulator", type=Path, required=True)
    parser.add_argument(
        "--jdk", type=Path, help="JDK bin directory; defaults to java/javac on PATH"
    )
    args = parser.parse_args()
    emulator = args.emulator.resolve()
    if hashlib.sha256(emulator.read_bytes()).hexdigest() != EMULATOR_SHA:
        raise ValueError("FreeJ2ME-Plus SHA-256 mismatch; use the documented pinned artifact")
    target = ROOT / "game/content/chapter_1/generated"
    java = args.jdk / "java" if args.jdk else "java"
    javac = args.jdk / "javac" if args.jdk else "javac"
    with tempfile.TemporaryDirectory(prefix="emblem-import-") as directory:
        work = Path(directory)
        output = work / "generated"
        export_definitions(ROOT / "reference/original-jars/chapter-1.jar", output)
        spawns = json.loads((output / "spawns.json").read_text())
        allied_pool = {
            int(item) for spawn in spawns if spawn["faction"] != 2 for item in spawn["itemChoices"]
        }
        allied_pool.update(int(spawn["dropTemplateId"]) for spawn in spawns)
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
            cwd=work,
        )
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
            "map_music",
            "battle_music",
            "title_music",
            "world_music",
            "victory_music",
            "defeat_music",
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
        provenance = json.loads((output / "provenance.json").read_text())
        provenance.update(
            emulatorSha256=EMULATOR_SHA,
            audio=(
                "p.mid/battle.mid/title.mid/world.mid/win.mid/over.mid rendered offline "
                "with JDK generated default soundbank; "
                "timbre is not original phone synthesis"
            ),
            jsonDigest="SHA-256 of json.dumps(sort_keys=True, separators=(',', ':')) UTF-8",
        )
        provenance["audioRenderer"] = subprocess.check_output(
            ["rtk", str(java), "-version"], text=True, stderr=subprocess.STDOUT
        ).splitlines()[0]
        provenance["outputs"] = {
            path.relative_to(output).as_posix(): output_digest(path)
            for path in sorted(output.rglob("*"))
            if path.is_file() and path.name != "provenance.json"
        }
        (output / "provenance.json").write_text(
            json.dumps(provenance, ensure_ascii=False, indent=2) + "\n"
        )
        previous = (
            json.loads((target / "provenance.json").read_text()).get("outputs", {})
            if (target / "provenance.json").exists()
            else {}
        )
        stale = [target / name for name in previous if name not in provenance["outputs"]]
        if any(not path.resolve().is_relative_to(target.resolve()) for path in stale):
            raise ValueError("Generated provenance contains a path outside its owned directory")
        shutil.copytree(output, target, dirs_exist_ok=True)
        for path in stale:
            path.unlink(missing_ok=True)
            Path(str(path) + ".import").unlink(missing_ok=True)
    print(f"Imported chapter-1 into {target}")


if __name__ == "__main__":
    main()
