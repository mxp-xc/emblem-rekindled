"""Update configured chapter-1 maps and the shared presentation bank offline.

Normal Godot runs use the committed chapter snapshot. The pinned original JAR and
FreeJ2ME are only needed here; authored narrative is never generated or replaced.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import traceback
from itertools import combinations
from pathlib import Path

from chapter_1_definitions import SOURCE_SHA, read_deployment
from chapter_configuration import (
    apply_recruit_bindings,
    format_changed_json,
    motion_requirements,
    normalize_deployment,
    prepare_map,
    publish_chapter,
    recruit_binding_plan,
    recruit_contexts,
    write_motion_reuse_plan,
)
from chapter_library import STAGE_FIELDS

ROOT = Path(__file__).resolve().parents[1]
EMULATOR_SHA = "9c59b74ae8e4fad205e5ff186940c24c53480918a3b180bb551559db9be3e7ff"
JAVA_SOURCES = (
    "ImportChapter1.java",
    "Chapter1Rules.java",
    "Chapter1MapAssets.java",
    "Chapter1BattleAssets.java",
    "Chapter1BattleClips.java",
    "Chapter1Story.java",
    "Chapter1Interface.java",
)


def run(*args: str | Path, cwd: Path) -> None:
    subprocess.run(["rtk", *map(str, args)], cwd=cwd, check=True)


def variant_requests(records: list[dict]) -> str:
    """All transferable legal weapons for allies; declared equipment for enemies."""
    # Native weapon 52 is not obtainable from the verified chapter shops/deployments.
    # Keep its template and any explicit enemy request, without synthesizing allied use.
    requests = ["allies\t" + ",".join(map(str, range(52)))]
    for record in records:
        if record["faction"] != 2:
            continue
        choices = {0, *record["itemChoices"], record["dropTemplateId"]}
        weapons = sorted(item for item in choices if 0 <= item <= 52)
        requests.append(f"{record.get('id', record['sourceId'])}\t{','.join(map(str, weapons))}")
    return "\n".join(requests) + "\n"


def sample_spawns(records: list[dict], units: list[dict]) -> list[dict]:
    """Bind native samples by identity/slot, independently of the retained party vector."""
    if len(records) != len(units) or len({unit["id"] for unit in units}) != len(units):
        raise ValueError("Native sample changed deployment count or identities")
    result, used = [], set()
    direct_allies = {
        row["sourceId"] for row in records if row["faction"] == 0 and "deploymentSlot" not in row
    }
    for index, record in enumerate(records):
        if "deploymentSlot" in record:
            candidates = [
                unit
                for unit in units
                if unit["faction"] == 0
                and unit["id"] not in direct_allies
                and unit["nativePolicy"] == record["deploymentSlot"]
            ]
        else:
            candidates = [
                unit
                for unit in units
                if unit["id"] == record.get("id", record["sourceId"])
                and unit["sourceId"] == record["sourceId"]
                and unit["faction"] == record["faction"]
                and unit["classId"] == record["classId"]
                and unit.get("deploymentIndex", index) == index
                and ("id" not in record or unit.get("deploymentIndex") == index)
            ]
        if len(candidates) != 1 or candidates[0]["id"] in used:
            raise ValueError("Native deployment identity/class/slot disagrees with source")
        unit = candidates[0]
        used.add(unit["id"])
        spawn = {**record, "id": unit["id"], "sourceId": unit["sourceId"], "formal": unit["formal"]}
        if (
            "deploymentSlot" in record
            and not unit["formal"]
            and record["deploymentSlot"] != unit["sourceId"]
        ):
            raise ValueError("Native temporary source disagrees with deployment slot")
        result.append(spawn)
    return result


def export_native(
    source: Path,
    output: Path,
    emulator: Path,
    deployment: dict,
    route: int,
    jdk: Path | None = None,
    reuse_chapter: Path | None = None,
) -> None:
    """Keep native threads, RNG and RMS in an isolated temporary working directory."""
    if output.exists():
        raise ValueError(f"Native output must be a new directory: {output}")
    if hashlib.sha256(emulator.read_bytes()).hexdigest() != EMULATOR_SHA:
        raise ValueError("FreeJ2ME-Plus SHA-256 mismatch; use the documented pinned artifact")
    java = jdk / "java" if jdk else "java"
    javac = jdk / "javac" if jdk else "javac"
    with tempfile.TemporaryDirectory(prefix="emblem-native-") as temporary:
        work = Path(temporary)
        native = work / "generated"
        variants = work / "battle_variants.tsv"
        variants.write_text(variant_requests(deployment["units"]))
        aliases = work / "sampling-identities.tsv"
        aliases.write_text(
            "".join(
                f"{index}\t{row['sourceId']}\t{row.get('id', row['sourceId'])}"
                f"\t{row['classId']}\t{row['faction']}\n"
                for index, row in enumerate(deployment["units"])
                if "deploymentSlot" not in row
            )
        )
        reuse = []
        if reuse_chapter:
            plan = work / "motion-reuse.tsv"
            write_motion_reuse_plan(reuse_chapter, plan)
            reuse.append(plan)
        try:
            run(
                javac,
                "-cp",
                emulator,
                "-d",
                work,
                *(ROOT / "tools" / name for name in JAVA_SOURCES),
                cwd=work,
            )
            run(
                java,
                "-Djava.awt.headless=true",
                "-Dfile.encoding=ISO_8859_1",
                "-cp",
                f"{work}:{emulator}",
                "ImportChapter1",
                source,
                native,
                variants,
                deployment["battleId"][1:],
                str(route),
                reuse[0] if reuse else "-",
                aliases,
                cwd=work,
            )
            units = json.loads((native / "units.json").read_text())
            spawns = sample_spawns(deployment["units"], units)
            (native / "spawns.json").write_text(
                json.dumps(spawns, ensure_ascii=False, indent=2) + "\n"
            )
            provenance = json.loads((native / "provenance.json").read_text())
            provenance["emulatorSha256"] = EMULATOR_SHA
            (native / "provenance.json").write_text(
                json.dumps(provenance, ensure_ascii=False, indent=2) + "\n"
            )
            shutil.copytree(native, output)
        except Exception as error:
            failures = ROOT / "temp/import-failures"
            failures.mkdir(parents=True, exist_ok=True)
            retained = Path(
                tempfile.mkdtemp(prefix=f"{deployment['battleId']}-route-{route}-", dir=failures)
            )
            if native.exists():
                shutil.copytree(native, retained / "native")
            shutil.copyfile(variants, retained / variants.name)
            shutil.copyfile(aliases, retained / aliases.name)
            if reuse:
                shutil.copyfile(reuse[0], retained / "motion-reuse.tsv")
            (retained / "failure.txt").write_text(traceback.format_exc())
            raise RuntimeError(f"Native export failed; retained diagnostics: {retained}") from error


def _context_requests(records: list[dict], context: dict, members: set[int]) -> set[str]:
    requests = set()
    party = context["party"]
    for row in records:
        if "deploymentSlot" in row:
            slot = row["deploymentSlot"]
            requests.add(
                f"member:{party[slot]}"
                if slot < len(party)
                else f"slot_{slot}_job_{row['classId']}_faction_{row['faction']}"
            )
        elif row["faction"] == 0 and row["sourceId"] in members:
            requests.add(f"member:{row['sourceId']}")
        else:
            requests.add(f"source_{row['sourceId']}_job_{row['classId']}_faction_{row['faction']}")
    return requests


def _profile_request(identity: str, profile: dict) -> str:
    unit = profile["unit"]
    if unit["formal"]:
        return f"member:{unit['sourceId']}"
    origin = "slot" if identity.startswith("slot_") else "source"
    return f"{origin}_{unit['sourceId']}_job_{unit['classId']}_faction_{unit['faction']}"


def _available_groups(
    bank: dict, stage: str, records: list[dict], requests: set[str]
) -> tuple[set, set]:
    attacks, defenses = set(), set()
    for identity, profile in bank["profiles"].items():
        if _profile_request(identity, profile) not in requests:
            continue
        unit = profile["unit"]
        allowed = set(range(52))
        if unit["faction"] == 2:
            allowed = {0}
            for row in records:
                if row["sourceId"] == unit["sourceId"] and row["classId"] == unit["classId"]:
                    allowed.update(
                        item
                        for item in [*row["itemChoices"], row["dropTemplateId"]]
                        if 0 <= item <= 52
                    )
        for weapon, motion in profile["motion"].get(stage, {}).items():
            if int(weapon) not in allowed:
                continue
            defenses.add(motion["defenseGroup"])
            if motion["canAttack"]:
                attacks.add(motion["actionGroup"])
    return attacks, defenses


def update_chapter(
    chapter: Path,
    battle_id: str,
    emulator: Path,
    route: int | None,
    jdk: Path | None,
    native_inputs: list[Path],
    *,
    refresh_motion: bool = False,
) -> dict:
    """Prepare the smallest useful native context cover, then publish one closed chapter."""
    chapter = chapter.resolve()
    source = ROOT / "reference/original-jars/chapter-1.jar"
    before = {
        path.relative_to(chapter): path.read_bytes()
        for path in chapter.rglob("*")
        if path.is_file()
    }
    provided = {}
    for path in native_inputs:
        path = path.resolve()
        provenance = json.loads((path / "provenance.json").read_text())
        if (
            provenance["sourceSha256"] != SOURCE_SHA
            or provenance["emulatorSha256"] != EMULATOR_SHA
            or provenance["preparationSeed"] != 0
        ):
            raise ValueError(f"Prepared native input has an unexpected source contract: {path}")
        key = (provenance["map"].rsplit(":", 1)[-1], provenance["route"])
        if key in provided:
            raise ValueError(f"Duplicate prepared native context: {key}")
        provided[key] = path
    reports, sampled, raw = [], set(), {}
    with tempfile.TemporaryDirectory(prefix="emblem-update-") as temporary:
        work = Path(temporary)
        staged = work / "game/content" / chapter.name
        shutil.copytree(chapter, staged)
        try:
            entry = json.loads((staged / "chapter.json").read_text())
            members = set(entry["initialParty"]) | set(entry["recruitByNode"].values())
            candidates = []
            for battle in dict.fromkeys([battle_id, *entry["battles"]]):
                raw[battle] = normalize_deployment(staged, read_deployment(source, int(battle[1:])))
                for context in recruit_contexts(staged, battle):
                    candidates.append(
                        {
                            "battle": battle,
                            "context": context,
                            "requests": _context_requests(raw[battle]["units"], context, members),
                        }
                    )

            def sample(candidate):
                battle, context = candidate["battle"], candidate["context"]
                key = (battle, context["route"])
                native = provided.get(key)
                dependency_count = 0
                if native is not None:
                    motion = json.loads((native / "battle/clips/manifest.json").read_text())
                    catalog = json.loads((staged / "generated/library/catalog.json").read_text())
                    matches = [
                        stage
                        for stage in catalog["stages"].values()
                        if {field: stage[field] for field in STAGE_FIELDS}
                        == {field: motion[field] for field in STAGE_FIELDS}
                    ]
                    known = set(matches[0]["clips"]) if len(matches) == 1 else set()
                    dependency_count = len(set(motion.get("reusedClips", [])) - known)
                    if dependency_count:
                        native = None
                prepared = native is not None
                if native is None:
                    native = work / "native" / f"{battle}-route-{context['route']}"
                    export_native(
                        source,
                        native,
                        emulator,
                        raw[battle],
                        context["route"],
                        jdk,
                        None if refresh_motion else staged,
                    )
                units = json.loads((native / "units.json").read_text())
                expected_formal = set(context["party"]) | {
                    row["sourceId"]
                    for row in raw[battle]["units"]
                    if row["faction"] == 0
                    and "deploymentSlot" not in row
                    and row["sourceId"] in members
                }
                if {unit["id"] for unit in units if unit["formal"]} != expected_formal:
                    raise ValueError(
                        f"Prepared native roster disagrees with route prefix: "
                        f"{battle} route {context['route']}"
                    )
                if json.loads((native / "spawns.json").read_text()) != sample_spawns(
                    raw[battle]["units"], units
                ):
                    raise ValueError(f"Prepared native deployment binding is stale: {native}")
                result = prepare_map(staged, native, raw[battle])
                reports.append(
                    {
                        "battleId": battle,
                        **context,
                        "preparedInput": prepared,
                        "preparedClipDependenciesMissing": dependency_count,
                        **result,
                    }
                )
                sampled.add(key)

            first = next(
                (
                    candidate
                    for candidate in candidates
                    if candidate["battle"] == battle_id
                    and (route is None or route in candidate["context"]["equivalentRoutes"])
                ),
                None,
            )
            if first is None:
                raise ValueError(
                    f"Route does not reach configured battle: {battle_id} route {route}"
                )
            selected_cover = [first]
            if route is None:
                catalog = json.loads((staged / "generated/library/catalog.json").read_text())
                known = {
                    _profile_request(identity, profile)
                    for identity, profile in catalog["profiles"].items()
                }
                targets = [
                    candidate for candidate in candidates if candidate["battle"] == battle_id
                ]
                required = set().union(*(candidate["requests"] for candidate in targets)) - known
                for count in range(1, len(targets) + 1):
                    cover = next(
                        (
                            subset
                            for subset in combinations(targets, count)
                            if required
                            <= set().union(*(candidate["requests"] for candidate in subset))
                        ),
                        None,
                    )
                    if cover is not None:
                        selected_cover = list(cover)
                        break
            for candidate in selected_cover:
                sample(candidate)
            while True:
                bindings = recruit_binding_plan(staged)
                pending = [
                    candidate
                    for candidate in candidates
                    if (candidate["battle"], candidate["context"]["route"]) not in sampled
                ]
                if bindings["missingProfiles"]:
                    needed = {
                        f"member:{row['member']}" if "member" in row else row["recipe"]
                        for row in bindings["missingProfiles"]
                    }
                    scored = [
                        (len(candidate["requests"] & needed), candidate) for candidate in pending
                    ]
                else:
                    apply_recruit_bindings(staged)
                    coverage = motion_requirements(staged)
                    if not coverage["missing"]:
                        break
                    catalog = json.loads((staged / "generated/library/catalog.json").read_text())
                    scored = []
                    for candidate in pending:
                        map_entry = json.loads(
                            (
                                staged / "generated/battles" / candidate["battle"] / "battle.json"
                            ).read_text()
                        )
                        stage = map_entry["stage"]
                        attacks, defenses = _available_groups(
                            catalog, stage, raw[candidate["battle"]]["units"], candidate["requests"]
                        )
                        score = sum(
                            key.split("/")[0] in attacks and key.split("/")[1] in defenses
                            for key in coverage["missing"].get(stage, {})
                        )
                        scored.append((score, candidate))
                if not scored or max(score for score, _ in scored) == 0:
                    raise ValueError(
                        "No native context can complete the declared chapter; "
                        "inspect missing profiles/motion: "
                        + json.dumps(
                            {"bindings": bindings, "motion": motion_requirements(staged)},
                            ensure_ascii=False,
                        )
                    )
                sample(max(scored, key=lambda item: item[0])[1])
            formatted = format_changed_json(staged, before)
            publication = publish_chapter(chapter, staged, before)
            publication["formattedFiles"] = formatted
        except Exception as error:
            failures = ROOT / "temp/import-failures"
            failures.mkdir(parents=True, exist_ok=True)
            retained = Path(tempfile.mkdtemp(prefix=f"chapter-{battle_id}-", dir=failures))
            shutil.copytree(staged, retained / "game/content" / chapter.name)
            (retained / "failure.txt").write_text(traceback.format_exc())
            (retained / "contexts.json").write_text(
                json.dumps(reports, ensure_ascii=False, indent=2) + "\n"
            )
            raise RuntimeError(f"Chapter import failed; retained staging: {retained}") from error
    return {
        "chapter": str(chapter),
        "contexts": reports,
        "requestedContextCover": [candidate["context"]["route"] for candidate in selected_cover],
        **publication,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emulator", type=Path)
    parser.add_argument("--battle", choices=tuple(f"m{index}" for index in range(8)))
    parser.add_argument(
        "--route",
        type=int,
        choices=range(8),
        help="Preferred first native context; missing coverage is supplemented automatically",
    )
    parser.add_argument(
        "--chapter",
        type=Path,
        default=ROOT / "game/content/chapter_1",
        help="Explicit chapter tree for an isolated import rehearsal",
    )
    parser.add_argument(
        "--native-input",
        type=Path,
        action="append",
        default=[],
        help="Use an explicitly prepared native context instead of sampling it again",
    )
    parser.add_argument("--report", type=Path, help="Write detailed context/publication evidence")
    parser.add_argument(
        "--jdk", type=Path, help="JDK bin directory; defaults to java/javac on PATH"
    )
    parser.add_argument(
        "--native-output", type=Path, help="Keep a native export without publishing content"
    )
    parser.add_argument(
        "--plan",
        action="store_true",
        help="Report missing combinations for every registered map; no original runtime needed",
    )
    parser.add_argument(
        "--refresh-motion",
        action="store_true",
        help="Explicitly resample motion instead of reusing an identical stage contract",
    )
    args = parser.parse_args()
    chapter = args.chapter.resolve()
    if args.plan:
        plan = motion_requirements(chapter)
        plan["missingProfiles"] = recruit_binding_plan(chapter)["missingProfiles"]
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return
    if not args.battle or not args.emulator:
        parser.error("--battle and --emulator are required when not using --plan")
    reuse_chapter = None if args.refresh_motion else chapter
    source = ROOT / "reference/original-jars/chapter-1.jar"
    deployment = normalize_deployment(chapter, read_deployment(source, int(args.battle[1:])))
    if args.native_output:
        if args.native_input:
            parser.error("--native-output and --native-input are separate workflows")
        route = (
            args.route
            if args.route is not None
            else recruit_contexts(chapter, args.battle)[0]["route"]
        )
        export_native(
            source,
            args.native_output.resolve(),
            args.emulator.resolve(),
            deployment,
            route,
            args.jdk,
            reuse_chapter,
        )
        print(f"Native sampling export: {args.native_output}")
        return
    authored = chapter / "authored/battles" / f"{args.battle}.json"
    if not authored.is_file():
        raise ValueError(f"Create and verify the authored configuration first: {authored}")
    if args.native_input and args.refresh_motion:
        parser.error("--refresh-motion requires fresh native sampling, not prepared inputs")
    result = update_chapter(
        chapter,
        args.battle,
        args.emulator.resolve(),
        args.route,
        args.jdk,
        args.native_input,
        refresh_motion=args.refresh_motion,
    )
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
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
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
