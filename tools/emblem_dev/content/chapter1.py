"""Update configured chapter-1 maps and the shared presentation bank offline.

Normal Godot runs use the committed chapter snapshot. The pinned original JAR and
FreeJ2ME are only needed here; authored narrative is never generated or replaced.
"""

import filecmp
import hashlib
import json
import shutil
import subprocess
import tempfile
import time
import traceback
from itertools import combinations
from pathlib import Path

from emblem_dev.content.configuration import (
    ENCOUNTER_BATTLES,
    apply_recruit_bindings,
    format_changed_json,
    import_promotion_rules,
    motion_requirements,
    normalize_deployment,
    prepare_map,
    publish_chapter,
    recruit_binding_plan,
    recruit_contexts,
    write_motion_reuse_plan,
)
from emblem_dev.content.definitions import SOURCE_SHA, read_deployment
from emblem_dev.content.library import STAGE_FIELDS, import_presentation
from emblem_dev.paths import JAVA, ROOT

EMULATOR_SHA = "9c59b74ae8e4fad205e5ff186940c24c53480918a3b180bb551559db9be3e7ff"
JAVA_SOURCES = (
    "ImportChapter1.java",
    "Chapter1Rules.java",
    "Chapter1MapAssets.java",
    "Chapter1BattleAssets.java",
    "Chapter1BattleClips.java",
    "Chapter1Story.java",
    "Chapter1Interface.java",
    "Chapter1Summons.java",
    "Chapter1Promotions.java",
)
SUMMON_CLASSES = (28, 29, 32, 33, 36, 37)


def summon_requests(class_id: int) -> set[str]:
    """Native families after all ten identities pass full presentation comparison."""
    return {f"summon_job_{class_id}_faction_{faction}" for faction in (1, 2)}


def candidate_key(candidate: dict) -> tuple:
    return (
        candidate["battle"],
        candidate["context"]["route"],
        candidate.get("summonClass"),
        candidate.get("promotion", False),
        candidate.get("adaptive", False),
        candidate["context"].get("worldStep") if candidate["battle"] in ENCOUNTER_BATTLES else None,
    )


def canonicalize_prepared_contexts(provided: dict, candidates: list[dict]) -> dict:
    """Match encounter samples to the planned representative of the same roster."""
    aliases = {}
    for candidate in candidates:
        if candidate["battle"] not in ENCOUNTER_BATTLES:
            continue
        canonical = candidate_key(candidate)
        for context in candidate["context"]["equivalentContexts"]:
            alias = candidate_key({**candidate, "context": context})
            if alias in aliases and aliases[alias] != canonical:
                raise ValueError(f"Ambiguous encounter context: {alias}")
            aliases[alias] = canonical
    result = {}
    for key, path in provided.items():
        if key[0] in ENCOUNTER_BATTLES:
            if key not in aliases:
                raise ValueError(f"Unsupported prepared encounter context: {key}")
            key = aliases[key]
        if key in result:
            raise ValueError(f"Duplicate equivalent prepared native context: {key}")
        result[key] = path
    return result


def run(*args: str | Path, cwd: Path) -> None:
    subprocess.run(list(map(str, args)), cwd=cwd, check=True)


def preserve_native_sample(source: Path, destination: Path) -> None:
    """Copy completed native evidence to a new directory and verify every file."""
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(destination)
    source, destination = source.resolve(), destination.resolve()
    if destination.is_relative_to(source) or source.is_relative_to(destination):
        raise ValueError("Native evidence overlaps its source")
    entries = list(source.rglob("*"))
    if any(path.is_symlink() for path in entries):
        raise ValueError("Native evidence source contains a symbolic link")
    source_files = {path.relative_to(source) for path in entries if path.is_file()}
    required = {
        Path(name)
        for name in ("provenance.json", "units.json", "spawns.json", "battle/clips/manifest.json")
    }
    if not required.issubset(source_files):
        raise ValueError("Native evidence source is incomplete")
    shutil.copytree(source, destination)
    copied_files = {
        path.relative_to(destination) for path in destination.rglob("*") if path.is_file()
    }
    if source_files != copied_files or any(
        not filecmp.cmp(source / path, destination / path, shallow=False) for path in source_files
    ):
        raise ValueError(f"Native evidence did not match source: {destination}")


def _enemy_weapon_choices(record: dict, profiles: dict) -> set[int]:
    choices = {0, *record.get("itemChoices", []), record.get("dropTemplateId", 0)}
    for profile in profiles.values():
        if all(
            profile["unit"][field] == record.get(field)
            for field in ("sourceId", "classId", "faction")
        ):
            choices.update(int(weapon) for weapon in profile["appearances"])
    return {item for item in choices if 0 <= item <= 52}


def variant_requests(
    records: list[dict], profiles: dict | None = None, *, adaptive: bool = False
) -> str:
    """Allied legal weapons and enemy equipment registered for the same native recipe."""
    # Native weapon 52 is not obtainable from the verified chapter shops/deployments.
    # Keep its template and any explicit enemy request, without synthesizing allied use.
    requests = ["allies\t" + ",".join(map(str, range(52)))]
    for record in records:
        if record["faction"] != 2:
            continue
        selected = {**record, "classId": _adaptive_class(record)} if adaptive else record
        weapons = sorted(_enemy_weapon_choices(selected, profiles or {}))
        requests.append(f"{record.get('id', record['sourceId'])}\t{','.join(map(str, weapons))}")
    return "\n".join(requests) + "\n"


def _adaptive_class(record: dict) -> int:
    current = record["classId"]
    if record.get("kind") == 1 and record["faction"] != 0 and current % 4 == 0:
        return current + 1
    return current


def _same_json_value(left, right) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(
            _same_json_value(left[k], right[k]) for k in left
        )
    if isinstance(left, list):
        return len(left) == len(right) and all(
            _same_json_value(a, b) for a, b in zip(left, right, strict=True)
        )
    return left == right


def bind_adaptive_profiles(
    records: list[dict], bindings: dict, recipes: dict, profiles: dict
) -> dict:
    """Bind only automatically selected native classes to their verified profiles."""
    result = dict(bindings)
    for row in records:
        target = _adaptive_class(row)
        if target == row["classId"]:
            continue
        recipe = f"source_{row['sourceId']}_job_{target}_faction_{row['faction']}"
        identity = recipes.get(recipe)
        profile = profiles.get(identity, {})
        unit = profile.get("unit", {})
        if any(
            type(unit.get(key)) is not int or unit[key] != value
            for key, value in (
                ("sourceId", row["sourceId"]),
                ("classId", target),
                ("faction", row["faction"]),
            )
        ):
            raise ValueError(f"Missing or invalid adaptive profile: {recipe}")
        if recipe in result and result[recipe] != identity:
            raise ValueError(f"Conflicting adaptive profile binding: {recipe}")
        result[recipe] = identity
    return result


def _adaptive_bindings_ready(chapter: Path, battle: str) -> bool:
    entry_path = chapter / "chapter.json"
    if not entry_path.is_file():
        return False
    entry = json.loads(entry_path.read_text())
    if not isinstance(entry, dict) or not isinstance(entry.get("battles"), dict):
        return False
    definition_ref = entry["battles"].get(battle)
    library_ref = entry.get("library")
    if not all(
        isinstance(ref, str) and ref.startswith("res://") for ref in (definition_ref, library_ref)
    ):
        return False
    game = chapter.parents[1]
    definition_path, library_path = (
        (game / ref[6:]).resolve() for ref in (definition_ref, library_ref)
    )
    if not all(
        path.is_relative_to(chapter) and path.is_file() for path in (definition_path, library_path)
    ):
        return False
    definition = json.loads(definition_path.read_text())
    catalog = json.loads(library_path.read_text())
    if not isinstance(definition, dict) or not isinstance(catalog, dict):
        return False
    records_ref = definition.get("deployments")
    if not isinstance(records_ref, str) or not records_ref.startswith("res://"):
        return False
    records_path = (game / records_ref[6:]).resolve()
    if not records_path.is_relative_to(chapter) or not records_path.is_file():
        return False
    records = json.loads(records_path.read_text())
    bindings, profiles = definition.get("profiles"), catalog.get("profiles")
    if (
        not isinstance(records, list)
        or not isinstance(bindings, dict)
        or not isinstance(profiles, dict)
    ):
        return False
    if not battle.startswith("m") or not battle[1:].isdigit() or int(battle[1:]) > 16:
        return False
    authoritative = normalize_deployment(
        chapter, read_deployment(ROOT / "reference/original-jars/chapter-1.jar", int(battle[1:]))
    )["units"]
    if not _same_json_value(records, authoritative):
        return False
    for row in records:
        if not isinstance(row, dict) or any(
            key not in row for key in ("kind", "classId", "faction", "sourceId")
        ):
            return False
        target = _adaptive_class(row)
        if target == row["classId"]:
            continue
        recipe = f"source_{row['sourceId']}_job_{target}_faction_{row['faction']}"
        profile = profiles.get(bindings.get(recipe), {})
        unit = profile.get("unit", {}) if isinstance(profile, dict) else {}
        if any(
            type(unit.get(key)) is not int or unit[key] != value
            for key, value in (
                ("sourceId", row["sourceId"]),
                ("classId", target),
                ("faction", row["faction"]),
            )
        ):
            return False
    return True


def sample_spawns(
    records: list[dict],
    units: list[dict],
    *,
    adaptive: bool = False,
    deployment_indices: list[int] | None = None,
    allow_empty_slots: bool = False,
) -> list[dict]:
    """Bind native samples by identity/slot, independently of the retained party vector."""
    if len({unit["id"] for unit in units}) != len(units):
        raise ValueError("Native sample changed deployment count or identities")
    if not allow_empty_slots and len(records) != len(units):
        raise ValueError("Native sample changed deployment count or identities")
    if deployment_indices is not None and len(deployment_indices) != len(records):
        raise ValueError("Native sample deployment indices disagree with records")
    result, used = [], set()
    direct_allies = {
        row["sourceId"] for row in records if row["faction"] == 0 and "deploymentSlot" not in row
    }
    inherited_count = sum(
        unit["faction"] == 0 and unit["id"] not in direct_allies for unit in units
    )
    for offset, record in enumerate(records):
        index = deployment_indices[offset] if deployment_indices is not None else offset
        expected_class = _adaptive_class(record) if adaptive else record["classId"]
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
                and unit["classId"] == expected_class
                and unit.get("deploymentIndex", index) == index
                and ("id" not in record or unit.get("deploymentIndex") == index)
            ]
        if (
            allow_empty_slots
            and "deploymentSlot" in record
            and record["deploymentSlot"] >= inherited_count
            and not candidates
        ):
            continue
        if len(candidates) != 1 or candidates[0]["id"] in used:
            raise ValueError("Native deployment identity/class/slot disagrees with source")
        unit = candidates[0]
        if adaptive and record.get("kind") == 1 and record["faction"] != 0:
            if unit.get("level") != 10:
                raise ValueError("Native adaptive level disagrees with controlled cache")
        used.add(unit["id"])
        spawn = {**record, "id": unit["id"], "sourceId": unit["sourceId"], "formal": unit["formal"]}
        if (
            "deploymentSlot" in record
            and not unit["formal"]
            and record["deploymentSlot"] != unit["sourceId"]
        ):
            raise ValueError("Native temporary source disagrees with deployment slot")
        result.append(spawn)
    if len(used) != len(units):
        raise ValueError("Native sample contains unmatched units")
    return result


def export_native(
    source: Path,
    output: Path,
    emulator: Path,
    deployment: dict,
    route: int,
    jdk: Path | None = None,
    reuse_chapter: Path | None = None,
    summon_class: int | None = None,
    promotion: bool = False,
    adaptive: bool = False,
    encounter_step: int | None = None,
) -> None:
    """Keep native threads, RNG and RMS in an isolated temporary working directory."""
    if output.exists():
        raise ValueError(f"Native output must be a new directory: {output}")
    if promotion and summon_class is not None:
        raise ValueError("Promotion and summon sampling cannot be combined")
    if hashlib.sha256(emulator.read_bytes()).hexdigest() != EMULATOR_SHA:
        raise ValueError("FreeJ2ME-Plus SHA-256 mismatch; use the documented pinned artifact")
    java = jdk / "java" if jdk else "java"
    javac = jdk / "javac" if jdk else "javac"
    with tempfile.TemporaryDirectory(prefix="emblem-native-") as temporary:
        work = Path(temporary)
        native = work / "generated"
        variants = work / "battle_variants.tsv"
        profiles = {}
        if reuse_chapter:
            profiles = json.loads((reuse_chapter / "generated/library/catalog.json").read_text())[
                "profiles"
            ]
        variants.write_text(variant_requests(deployment["units"], profiles, adaptive=adaptive))
        aliases = work / "sampling-identities.tsv"
        aliases.write_text(
            "".join(
                f"{index}\t{row['sourceId']}\t{row.get('id', row['sourceId'])}"
                f"\t{row['classId']}\t{row['faction']}"
                + (f"\t{_adaptive_class(row)}" if adaptive else "")
                + "\n"
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
                *(JAVA / name for name in JAVA_SOURCES),
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
                str(summon_class if summon_class is not None else -1),
                str(promotion).lower(),
                str(adaptive).lower(),
                str(encounter_step if encounter_step is not None else -1),
                cwd=work,
            )
            units = json.loads((native / "units.json").read_text())
            summon_file = native / "summons.json"
            summons = json.loads(summon_file.read_text()) if summon_file.exists() else []
            summoned_ids = {row["sourceId"] for row in summons}
            retained = [
                (index, row)
                for index, row in enumerate(deployment["units"])
                if "deploymentSlot" in row or row.get("id", row["sourceId"]) not in summoned_ids
            ]
            records = [row for _, row in retained]
            binding_units = (
                json.loads((native / "promotion_sources.json").read_text()) if promotion else units
            )
            if adaptive and summon_class is not None:
                spawns = validate_adaptive_summons(
                    native, deployment["units"], summon_class, battle_id=deployment["battleId"]
                )
            else:
                spawns = sample_spawns(
                    records,
                    [u for u in binding_units if u["id"] not in summoned_ids],
                    adaptive=adaptive,
                    deployment_indices=[index for index, _ in retained],
                    allow_empty_slots=deployment["battleId"] in ENCOUNTER_BATTLES,
                )
            if promotion:
                validate_promotions(
                    native,
                    records,
                    adaptive=adaptive,
                    allow_empty_slots=deployment["battleId"] in ENCOUNTER_BATTLES,
                )
            spawns.extend(
                {**row, "id": row["sourceId"], "formal": False, "policy": 0, "summoned": True}
                for row in summons
            )
            (native / "spawns.json").write_text(
                json.dumps(spawns, ensure_ascii=False, indent=2) + "\n"
            )
            provenance = json.loads((native / "provenance.json").read_text())
            provenance["emulatorSha256"] = EMULATOR_SHA
            if promotion:
                provenance["promotionPreparation"] = (
                    "original 76 action on current blue stage0 units, "
                    "fixed minimum level; not natural play"
                )
            if adaptive:
                provenance["adaptivePreparation"] = {
                    "maxInternalLevel": 9,
                    "averageInternalLevel": 9,
                    "description": "original loader with controlled cache; not natural play",
                }
            if summon_class is not None:
                provenance["summonClassId"] = summon_class
                provenance["summonPreparation"] = (
                    "controlled original b.b(caster,true), selected family; "
                    "both complete native identity pools, not natural play"
                )
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


def validate_adaptive_summons(
    native: Path, records: list[dict], summon_class: int, *, battle_id: str = ""
) -> list[dict]:
    """Validate original deployment before and after controlled summon preparation."""
    sources = json.loads((native / "adaptive_sources.json").read_text())
    units = json.loads((native / "units.json").read_text())
    declarations = json.loads((native / "summons.json").read_text())
    casters = json.loads((native / "summon_casters.json").read_text())
    summoned = {
        (faction, identity, summon_class)
        for faction, first in ((1, 20), (2, 70))
        for identity in range(first, first + 10)
    }
    if (
        len(declarations) != 20
        or {(row["faction"], row["sourceId"], row["classId"]) for row in declarations} != summoned
    ):
        raise ValueError("Native summon declarations disagree with controlled family")
    if len(casters) != 2 or {row["faction"] for row in casters} != {0, 2}:
        raise ValueError("Native summon casters disagree with controlled preparation")
    caster_by_id = {row["id"]: row for row in casters}
    if len(caster_by_id) != 2:
        raise ValueError("Native summon caster identities are not unique")
    expected_sources = [
        row for row in sources if not (20 <= row["id"] <= 29 or 70 <= row["id"] <= 79)
    ]
    if not set(caster_by_id).issubset({row["id"] for row in expected_sources}):
        raise ValueError("Native summon caster is not an original deployment")
    original_spawns = sample_spawns(records, sources, adaptive=True)
    spawns = [
        row for row in original_spawns if not (20 <= row["id"] <= 29 or 70 <= row["id"] <= 79)
    ]
    by_id = {unit["id"]: unit for unit in units}
    if len(by_id) != len(units):
        raise ValueError("Native summon units have duplicate identities")
    born = {
        (unit["faction"], unit["sourceId"], unit["classId"])
        for unit in units
        if (unit["faction"], unit["sourceId"], unit["classId"]) in summoned
    }
    if born != summoned or len(units) != len(expected_sources) + 20:
        raise ValueError("Native summon units disagree with controlled family")
    for before in expected_sources:
        after = by_id.get(before["id"], {})
        caster = caster_by_id.get(before["id"])
        if caster and (
            caster["faction"] != before["faction"]
            or caster["beforeLevel"] != before["level"]
            or caster["afterLevel"] != 1
        ):
            raise ValueError("Native summon caster state disagrees with preparation")
        expected = dict(before)
        if caster:
            expected["level"] = 1
        if battle_id == "m0":
            visible = before["id"] not in (13, 14, 15)
            expected["visible"] = visible
            expected["flags"] = (before["flags"] & ~1) if visible else (before["flags"] | 1)
        for key in expected:
            if key not in ("x", "y") and expected[key] != after.get(key):
                raise ValueError("Native summon preparation changed deployment unexpectedly")
    return spawns


def validate_promotions(
    native: Path, records: list[dict], *, adaptive: bool = False, allow_empty_slots: bool = False
) -> list[dict]:
    """Prepared profiles retain the original deployment and exact original transition."""
    sources = json.loads((native / "promotion_sources.json").read_text())
    spawns = sample_spawns(records, sources, adaptive=adaptive, allow_empty_slots=allow_empty_slots)
    units = json.loads((native / "units.json").read_text())
    changes = json.loads((native / "promotion_units.json").read_text())
    rules = json.loads((native / "promotions.json").read_text())
    pairs = {row["fromClassId"]: row["toClassId"] for row in rules}
    expected = [
        {"id": u["id"], "fromClassId": u["classId"], "toClassId": pairs[u["classId"]]}
        for u in sources
        if u["faction"] == 0 and u["classId"] in pairs
    ]
    if changes != expected or len(units) != len(sources):
        raise ValueError("Prepared promotion declarations disagree with original units")
    by_id = {u["id"]: u for u in units}
    for before in sources:
        after = by_id.get(before["id"], {})
        target = (
            pairs.get(before["classId"], before["classId"])
            if before["faction"] == 0
            else before["classId"]
        )
        if after.get("classId") != target or any(
            after.get(key) != before.get(key)
            for key in ("id", "sourceId", "formal", "faction", "nativePolicy", "deploymentIndex")
        ):
            raise ValueError("Prepared promotion changed source identity or class unexpectedly")
    return spawns


def _context_requests(
    records: list[dict],
    context: dict,
    members: set[int],
    classes: dict[int, int],
    promotion: bool = False,
    adaptive: bool = False,
    allow_empty_slots: bool = False,
) -> set[str]:
    requests = set()
    party = context["party"]
    for row in records:
        if "deploymentSlot" in row:
            slot = row["deploymentSlot"]
            formal = slot < len(party)
            if not formal and allow_empty_slots:
                continue
            source_id = party[slot] if formal else slot
            class_id = classes[source_id] if formal else row["classId"]
            if promotion and class_id in range(0, 21, 4):
                class_id += 1
            requests.add(f"{'source' if formal else 'slot'}_{source_id}_job_{class_id}_faction_0")
        elif row["faction"] == 0 and row["sourceId"] in members:
            class_id = classes[row["sourceId"]]
            if promotion and class_id in range(0, 21, 4):
                class_id += 1
            requests.add(f"source_{row['sourceId']}_job_{class_id}_faction_0")
        else:
            target = _adaptive_class(row) if adaptive else row["classId"]
            requests.add(f"source_{row['sourceId']}_job_{target}_faction_{row['faction']}")
    return requests


def _profile_request(identity: str, profile: dict) -> str:
    unit = profile["unit"]
    if unit["formal"]:
        return f"source_{unit['sourceId']}_job_{unit['classId']}_faction_{unit['faction']}"
    if identity.startswith("summon_job_"):
        return f"summon_job_{unit['classId']}_faction_{unit['faction']}"
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
            # Shared recipes may acquire a declared weapon on another map. Native
            # resampling requests that same registered union when closing old stages.
            allowed = _enemy_weapon_choices(unit, {identity: profile})
            if unit.get("baseTemplateId") == 10 + unit["classId"]:
                allowed.update(
                    [29]
                    if unit["classGroup"] == 7
                    else [30]
                    if unit["classGroup"] == 8
                    else range(40, 46)
                )
            for row in records:
                if all(row[field] == unit[field] for field in ("sourceId", "classId", "faction")):
                    allowed.update(_enemy_weapon_choices(row, {identity: profile}))
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
    evidence_output: Path | None = None,
) -> dict:
    """Prepare the smallest useful native context cover, then publish one closed chapter."""
    chapter = chapter.resolve()
    if evidence_output is not None:
        if evidence_output.exists() or evidence_output.is_symlink():
            raise FileExistsError(evidence_output)
        evidence_output = evidence_output.resolve()
        if evidence_output.is_relative_to(chapter) or chapter.is_relative_to(evidence_output):
            raise ValueError("Native evidence directory overlaps the chapter")
        evidence_output.mkdir(parents=True)
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
        adaptive_preparation = provenance.get("adaptivePreparation")
        if adaptive_preparation is not None and (
            not isinstance(adaptive_preparation, dict)
            or adaptive_preparation.get("maxInternalLevel") != 9
            or adaptive_preparation.get("averageInternalLevel") != 9
        ):
            raise ValueError(f"Prepared native input has an invalid adaptive context: {path}")
        battle = provenance["map"].rsplit(":", 1)[-1]
        step = provenance.get("worldStep")
        if battle in ENCOUNTER_BATTLES and (type(step) is not int or step < 6):
            raise ValueError(f"Prepared encounter input lacks a valid world step: {path}")
        key = candidate_key(
            {
                "battle": battle,
                "context": {"route": provenance["route"], "worldStep": step},
                "summonClass": provenance.get("summonClassId"),
                "promotion": bool(provenance.get("promotionPreparation")),
                "adaptive": bool(provenance.get("adaptivePreparation")),
            }
        )
        if key in provided:
            raise ValueError(f"Duplicate prepared native context: {key}")
        provided[key] = path
    combined_battles = {key[0] for key in provided if key[4] and (key[2] is not None or key[3])}
    base_battles = {key[0] for key in provided if key[4] and key[2] is None and not key[3]}
    for battle in combined_battles - base_battles:
        if not _adaptive_bindings_ready(chapter, battle):
            raise ValueError(f"Prepared combined sample requires an adaptive base: {battle}")
    reports, sampled, raw = [], set(), {}
    with tempfile.TemporaryDirectory(prefix="emblem-update-") as temporary:
        work = Path(temporary)
        staged = work / "game/content" / chapter.name
        shutil.copytree(chapter, staged)
        try:
            entry = json.loads((staged / "chapter.json").read_text())
            members = set(entry["initialParty"]) | set(entry["recruitByNode"].values())
            bank = json.loads((staged / "generated/library/catalog.json").read_text())
            classes = {}
            for profile in bank["profiles"].values():
                unit = profile["unit"]
                if unit["formal"] and unit["faction"] == 0 and unit["classId"] in range(0, 21, 4):
                    source_id = unit["sourceId"]
                    if source_id in classes and classes[source_id] != unit["classId"]:
                        raise ValueError("Conflicting original formal class")
                    classes[source_id] = unit["classId"]
            candidates = []
            for battle in dict.fromkeys([battle_id, *entry["battles"]]):
                raw[battle] = normalize_deployment(staged, read_deployment(source, int(battle[1:])))
                for context in recruit_contexts(staged, battle):
                    candidates.append(
                        {
                            "battle": battle,
                            "context": context,
                            "requests": _context_requests(
                                raw[battle]["units"],
                                context,
                                members,
                                classes,
                                allow_empty_slots=battle in ENCOUNTER_BATTLES,
                            ),
                        }
                    )
                    if battle != "m0":
                        candidates.append(
                            {
                                "battle": battle,
                                "context": context,
                                "promotion": True,
                                "requests": _context_requests(
                                    raw[battle]["units"],
                                    context,
                                    members,
                                    classes,
                                    True,
                                    allow_empty_slots=battle in ENCOUNTER_BATTLES,
                                ),
                            }
                        )
                    for promoted in [False, True] if battle != "m0" else [False]:
                        candidates.append(
                            {
                                "battle": battle,
                                "context": context,
                                "adaptive": True,
                                "promotion": promoted,
                                "requests": _context_requests(
                                    raw[battle]["units"],
                                    context,
                                    members,
                                    classes,
                                    promotion=promoted,
                                    adaptive=True,
                                    allow_empty_slots=battle in ENCOUNTER_BATTLES,
                                ),
                            }
                        )
                first_context = recruit_contexts(staged, battle)[0]
                for class_id in SUMMON_CLASSES:
                    candidates.append(
                        {
                            "battle": battle,
                            "context": first_context,
                            "summonClass": class_id,
                            "requests": _context_requests(
                                raw[battle]["units"],
                                first_context,
                                members,
                                classes,
                                allow_empty_slots=battle in ENCOUNTER_BATTLES,
                            )
                            | summon_requests(class_id),
                        }
                    )
                    for context in recruit_contexts(staged, battle):
                        candidates.append(
                            {
                                "battle": battle,
                                "context": context,
                                "summonClass": class_id,
                                "adaptive": True,
                                "requests": _context_requests(
                                    raw[battle]["units"],
                                    context,
                                    members,
                                    classes,
                                    adaptive=True,
                                    allow_empty_slots=battle in ENCOUNTER_BATTLES,
                                )
                                | summon_requests(class_id),
                            }
                        )

            provided = canonicalize_prepared_contexts(provided, candidates)
            candidate_keys = {candidate_key(candidate) for candidate in candidates}
            unsupported = [key for key in provided if key[4] and key not in candidate_keys]
            if unsupported:
                raise ValueError(f"Unsupported prepared adaptive contexts: {unsupported}")

            def sample(candidate):
                started = time.monotonic()
                battle, context = candidate["battle"], candidate["context"]
                key = candidate_key(candidate)
                summon_class = candidate.get("summonClass")
                promotion = candidate.get("promotion", False)
                adaptive = candidate.get("adaptive", False)
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
                    suffix = (
                        f"-summon-{summon_class}"
                        if summon_class is not None
                        else "-promotion"
                        if promotion
                        else ""
                    )
                    if adaptive:
                        suffix += "-adaptive"
                    if battle in ENCOUNTER_BATTLES:
                        suffix += f"-step-{context['worldStep']}"
                    native = work / "native" / f"{battle}-route-{context['route']}{suffix}"
                    export_native(
                        source,
                        native,
                        emulator,
                        raw[battle],
                        context["route"],
                        jdk,
                        None if refresh_motion else staged,
                        summon_class,
                        promotion,
                        adaptive,
                        context["worldStep"] if battle in ENCOUNTER_BATTLES else None,
                    )
                evidence_path = None
                if evidence_output is not None and not prepared:
                    evidence_path = evidence_output / native.name
                    preserve_native_sample(native, evidence_path)
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
                import_promotion_rules(staged, native)
                if promotion:
                    if json.loads((native / "spawns.json").read_text()) != validate_promotions(
                        native,
                        raw[battle]["units"],
                        adaptive=adaptive,
                        allow_empty_slots=battle in ENCOUNTER_BATTLES,
                    ):
                        raise ValueError(
                            f"Prepared promotion deployment binding is stale: {native}"
                        )
                    result = {"presentation": import_presentation(staged, native)}
                elif summon_class is None:
                    if json.loads((native / "spawns.json").read_text()) != sample_spawns(
                        raw[battle]["units"],
                        units,
                        adaptive=adaptive,
                        allow_empty_slots=battle in ENCOUNTER_BATTLES,
                    ):
                        raise ValueError(f"Prepared native deployment binding is stale: {native}")
                    if adaptive:
                        result = {"presentation": import_presentation(staged, native)}
                        definition_path = staged / "generated/battles" / battle / "battle.json"
                        definition = json.loads(definition_path.read_text())
                        if (
                            definition["stage"] != result["presentation"]["stage"]
                            or definition["scene"] != result["presentation"]["scene"]
                        ):
                            raise ValueError("Adaptive sample stage or scene disagrees with map")
                        profiles = json.loads(
                            (staged / "generated/library/catalog.json").read_text()
                        )["profiles"]
                        definition["profiles"] = bind_adaptive_profiles(
                            raw[battle]["units"],
                            definition["profiles"],
                            result["presentation"]["recipes"],
                            profiles,
                        )
                        definition_path.write_text(
                            json.dumps(definition, ensure_ascii=False, indent=2) + "\n"
                        )
                    else:
                        result = prepare_map(staged, native, raw[battle])
                else:
                    expected = {
                        (faction, identity, summon_class)
                        for faction, first in ((1, 20), (2, 70))
                        for identity in range(first, first + 10)
                    }
                    declared = json.loads((native / "summons.json").read_text())
                    actual = {(row["faction"], row["sourceId"], row["classId"]) for row in declared}
                    summoned_ids = {row["sourceId"] for row in declared}
                    sampled_actors = {
                        (unit["faction"], unit["sourceId"], unit["classId"])
                        for unit in units
                        if unit["id"] in summoned_ids and unit["id"] == unit["sourceId"]
                    }
                    if actual != expected or len(declared) != 20 or sampled_actors != expected:
                        raise ValueError(f"Prepared summon declaration is stale: {native}")
                    if adaptive:
                        originals = validate_adaptive_summons(
                            native, raw[battle]["units"], summon_class, battle_id=battle
                        )
                        expected_spawns = originals + [
                            {
                                **row,
                                "id": row["sourceId"],
                                "formal": False,
                                "policy": 0,
                                "summoned": True,
                            }
                            for row in declared
                        ]
                        if json.loads((native / "spawns.json").read_text()) != expected_spawns:
                            raise ValueError(
                                f"Prepared adaptive summon bindings are stale: {native}"
                            )
                    result = {"presentation": import_presentation(staged, native)}
                reports.append(
                    {
                        "battleId": battle,
                        **context,
                        "preparedInput": prepared,
                        "summonClassId": summon_class,
                        "promotionPreparation": promotion,
                        "adaptivePreparation": adaptive,
                        **({"nativeEvidence": str(evidence_path)} if evidence_path else {}),
                        "preparedClipDependenciesMissing": dependency_count,
                        "preparationSeconds": round(time.monotonic() - started, 3),
                        **result,
                    }
                )
                sampled.add(key)

            first = next(
                (
                    candidate
                    for candidate in candidates
                    if candidate["battle"] == battle_id
                    and "summonClass" not in candidate
                    and not candidate.get("promotion")
                    and not candidate.get("adaptive")
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
                    candidate
                    for candidate in candidates
                    if candidate["battle"] == battle_id
                    and "summonClass" not in candidate
                    and not candidate.get("promotion")
                    and not candidate.get("adaptive")
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
            for candidate in candidates:
                if candidate.get("adaptive") and candidate_key(candidate) in provided:
                    sample(candidate)
            adaptive_battles = {key[0] for key in provided if key[4]}
            # Explicit promotion samples must still prove equivalence when a
            # target recipe already exists from an initially advanced blue slot.
            for candidate in candidates:
                if (
                    candidate.get("promotion")
                    and not candidate.get("adaptive")
                    and candidate_key(candidate) in provided
                ):
                    sample(candidate)
            catalog = json.loads((staged / "generated/library/catalog.json").read_text())
            for class_id in SUMMON_CLASSES:
                complete = True
                for faction, first_identity in ((1, 20), (2, 70)):
                    family = catalog.get("summons", {}).get(str(faction), {}).get(str(class_id), {})
                    complete = (
                        complete
                        and set(family)
                        == {
                            str(identity) for identity in range(first_identity, first_identity + 10)
                        }
                        and all(profile in catalog["profiles"] for profile in family.values())
                    )
                if not complete:
                    sample(
                        next(
                            candidate
                            for candidate in candidates
                            if candidate["battle"] == battle_id
                            and candidate.get("summonClass") == class_id
                        )
                    )
            while True:
                catalog = json.loads((staged / "generated/library/catalog.json").read_text())
                known = {
                    _profile_request(identity, profile)
                    for identity, profile in catalog["profiles"].items()
                }
                promoted = [
                    candidate
                    for candidate in candidates
                    if candidate.get("promotion") and not candidate.get("adaptive")
                ]
                needed_promotions = (
                    set().union(*(candidate["requests"] for candidate in promoted)) - known
                )
                if needed_promotions:
                    scored_promotions = [
                        (len(candidate["requests"] & needed_promotions), candidate)
                        for candidate in promoted
                        if candidate_key(candidate) not in sampled
                    ]
                    if not scored_promotions or max(score for score, _ in scored_promotions) == 0:
                        raise ValueError("No native context can provide finite promotion profiles")
                    sample(max(scored_promotions, key=lambda item: item[0])[1])
                    continue
                bindings = recruit_binding_plan(staged)
                pending = [
                    candidate
                    for candidate in candidates
                    if candidate_key(candidate) not in sampled
                    and (not candidate.get("adaptive") or candidate["battle"] in adaptive_battles)
                ]
                if bindings["missingProfiles"]:
                    needed = {
                        f"source_{row['member']}_job_{classes[row['member']]}_faction_0"
                        if "member" in row
                        else row["recipe"]
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
