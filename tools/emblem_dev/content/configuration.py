"""Publish one map/deployment definition; narrative remains authored chapter content."""

import copy
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from emblem_dev.content.actions import compile_actions
from emblem_dev.content.assets import owned_output_paths, publish_generated, share_textures
from emblem_dev.content.library import STAGE_FIELDS, import_presentation
from emblem_dev.paths import ROOT


def resource_path(chapter: Path, path: Path) -> str:
    return "res://" + path.resolve().relative_to(chapter.resolve().parents[1]).as_posix()


def write_motion_reuse_plan(chapter: Path, target: Path) -> None:
    """Describe existing motion by complete stage contract and verified file presence."""
    chapter = chapter.resolve()
    game = chapter.parents[1]
    entry = json.loads((chapter / "chapter.json").read_text())
    bank = json.loads((game / entry["library"][6:]).read_text())
    rows = []
    for stage_id, stage in bank["stages"].items():
        signature = json.dumps(
            {key: stage[key] for key in STAGE_FIELDS},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        rows.append(f"stage\t{stage_id}\t{signature}")
        rows.extend(
            f"clip\t{stage_id}\t{key}"
            for key, path in stage["clips"].items()
            if (game / path[6:]).is_file()
        )
        rows.extend(f"death\t{stage_id}\t{key}" for key in stage["deaths"])
    target.write_text("\n".join(rows) + "\n")


def motion_requirements(chapter: Path) -> dict:
    """Plan the sampled motion closure for every registered map, including old maps."""
    chapter = chapter.resolve()
    game = chapter.parents[1]

    def read_resource(path):
        return json.loads((game / path[6:]).read_text())

    entry = json.loads((chapter / "chapter.json").read_text())
    bank = read_resource(entry["library"])
    missing, maps = {}, {}
    for battle, path in entry["battles"].items():
        definition = read_resource(path)
        stage_id = definition["stage"]
        stage = bank["stages"][stage_id]
        appearances = []
        for profile_id in set(definition["profiles"].values()):
            profile = bank["profiles"][profile_id]
            for weapon, art in profile["appearances"].items():
                motion = profile["motion"][stage_id][weapon]
                appearances.append((profile_id, weapon, art["nativeSide"], motion))
        required = set()
        for profile, weapon, side, action in appearances:
            if not action["canAttack"]:
                continue
            for other_profile, other_weapon, other_side, defense in appearances:
                if side == other_side:
                    continue
                for slot in range(2):
                    for outcome in ("hit", "miss", "critical"):
                        key = f"{action['actionGroup']}/{defense['defenseGroup']}/{slot}/{outcome}"
                        required.add(key)
                        clip = stage["clips"].get(key)
                        if clip and (game / clip[6:]).is_file():
                            continue
                        request = missing.setdefault(stage_id, {}).setdefault(
                            key,
                            {
                                "maps": [],
                                "attacker": {"profile": profile, "weapon": int(weapon)},
                                "defender": {"profile": other_profile, "weapon": int(other_weapon)},
                            },
                        )
                        if battle not in request["maps"]:
                            request["maps"].append(battle)
        maps[battle] = {"stage": stage_id, "requiredClips": len(required)}
    return {"maps": maps, "missing": missing}


def recruit_contexts(chapter: Path, battle_id: str) -> list[dict]:
    """Native sampling contexts with distinct inherited rosters, not route snapshots."""
    chapter = chapter.resolve()
    entry = json.loads((chapter / "chapter.json").read_text())
    bank = json.loads((chapter.parents[1] / entry["library"][6:]).read_text())
    contexts = {}
    node = int(battle_id[1:])
    for route, path in enumerate(bank["storyCommon"]["world"]["routes"]):
        if node not in path:
            continue
        step = path.index(node)
        party = list(entry["initialParty"])
        for previous in path[:step]:
            member = entry["recruitByNode"].get(str(previous))
            if member is not None and member not in party:
                party.append(member)
        key = tuple(party)
        if key not in contexts:
            contexts[key] = {
                "route": route,
                "worldStep": step,
                "party": party,
                "equivalentRoutes": [],
            }
        contexts[key]["equivalentRoutes"].append(route)
    return list(contexts.values())


def recruit_binding_plan(chapter: Path) -> dict:
    """Explicitly bind all supported inherited source/class recipes in registered maps."""
    chapter = chapter.resolve()
    entry = json.loads((chapter / "chapter.json").read_text())
    game = chapter.parents[1]
    bank = json.loads((game / entry["library"][6:]).read_text())
    plans, missing = {}, []
    for battle_id, path in entry["battles"].items():
        definition = json.loads((game / path[6:]).read_text())
        bindings = dict(definition["profiles"])
        contexts = recruit_contexts(chapter, battle_id)
        members = {member for context in contexts for member in context["party"]}
        for member in sorted(members):
            by_recipe = {}
            for identity, profile in bank["profiles"].items():
                unit = profile["unit"]
                if unit["formal"] and unit["faction"] == 0 and unit["sourceId"] == member:
                    recipe = f"source_{member}_job_{unit['classId']}_faction_0"
                    by_recipe.setdefault(recipe, []).append(identity)
            if not by_recipe:
                missing.append({"battleId": battle_id, "member": member})
            for recipe, candidates in by_recipe.items():
                if recipe in bindings:
                    continue
                if len(candidates) != 1:
                    raise ValueError(
                        "Inherited profile is ambiguous; sample this map context explicitly: "
                        f"{battle_id}:{recipe}"
                    )
                bindings[recipe] = candidates[0]
        records = json.loads((game / definition["deployments"][6:]).read_text())
        for row in records:
            if "deploymentSlot" not in row or not any(
                row["deploymentSlot"] >= len(context["party"]) for context in contexts
            ):
                continue
            recipe = f"slot_{row['deploymentSlot']}_job_{row['classId']}_faction_{row['faction']}"
            if recipe in bindings:
                continue
            candidates = [
                name for name in bank["profiles"] if name == recipe or name.startswith(recipe + "_")
            ]
            if not candidates:
                missing.append({"battleId": battle_id, "recipe": recipe})
            elif len(candidates) != 1:
                raise ValueError(
                    "Temporary profile is ambiguous; sample this map context explicitly: "
                    f"{battle_id}:{recipe}"
                )
            else:
                bindings[recipe] = candidates[0]
        plans[battle_id] = bindings
    return {"bindings": plans, "missingProfiles": missing}


def apply_recruit_bindings(chapter: Path) -> dict:
    plan = recruit_binding_plan(chapter)
    if plan["missingProfiles"]:
        raise ValueError(
            "Missing inherited presentation profiles: "
            + json.dumps(plan["missingProfiles"], ensure_ascii=False)
        )
    entry = json.loads((chapter / "chapter.json").read_text())
    for battle_id, bindings in plan["bindings"].items():
        path = chapter.resolve().parents[1] / entry["battles"][battle_id][6:]
        definition = json.loads(path.read_text())
        if definition["profiles"] != bindings:
            definition["profiles"] = bindings
            path.write_text(json.dumps(definition, ensure_ascii=False, indent=2) + "\n")
    return plan


def import_map(chapter: Path, source: Path, deployment: dict) -> dict:
    """Validate a complete library/map update in isolation before changing the chapter."""
    chapter = chapter.resolve()
    before = {p.relative_to(chapter): p.read_bytes() for p in chapter.rglob("*") if p.is_file()}
    with tempfile.TemporaryDirectory(prefix="emblem-chapter-") as directory:
        staged = Path(directory) / "game/content" / chapter.name
        shutil.copytree(chapter, staged)
        result = prepare_map(staged, source, deployment)
        publication = publish_chapter(chapter, staged, before)
    return {**result, **publication}


def publish_chapter(chapter: Path, staged: Path, before: dict) -> dict:
    """Publish a stable, fully closed generated snapshot; never replace authored files."""
    chapter = chapter.resolve()
    coverage = motion_requirements(staged)
    if coverage["missing"]:
        raise ValueError(
            "Missing chapter motion combinations: " + json.dumps(coverage, ensure_ascii=False)
        )
    check = share_textures(staged, dry_run=True)
    if check["filesWritten"] or check["filesRemoved"]:
        raise ValueError("Staged chapter still requires texture normalization")
    after = {p.relative_to(staged): p.read_bytes() for p in staged.rglob("*") if p.is_file()}
    for relative in after.keys() & before.keys():
        if relative.suffix == ".json" and json.loads(after[relative]) == json.loads(
            before[relative]
        ):
            after[relative] = before[relative]
    owned = set()
    for path in chapter.rglob("provenance.json"):
        metadata = json.loads(path.read_text())
        for output in owned_output_paths(path.parent, metadata["outputs"]):
            relative = output.relative_to(chapter)
            owned.update((relative, Path(str(relative) + ".import")))
    removed = before.keys() - after.keys()
    if any(path not in owned for path in removed):
        raise ValueError("Chapter update would remove an unowned file")
    if any(
        after.get(path) != value for path, value in before.items() if path.parts[0] == "authored"
    ):
        raise ValueError("Chapter update would modify authored content")
    current = {p.relative_to(chapter): p.read_bytes() for p in chapter.rglob("*") if p.is_file()}
    if current != before:
        raise ValueError("Chapter changed during offline import; retry with a stable content tree")
    written = 0
    for relative, data in after.items():
        if before.get(relative) != data:
            path = chapter / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            written += 1
    for relative in removed:
        (chapter / relative).unlink()
    return {"coverage": coverage, "filesWritten": written, "filesRemoved": len(removed)}


def format_changed_json(chapter: Path, before: dict) -> int:
    """Use the project's Prettier for new/changed generated data, once before publication."""
    paths = []
    for path in chapter.rglob("*.json"):
        relative = path.relative_to(chapter)
        if relative.parts[0] == "authored":
            continue
        if relative not in before or json.loads(path.read_text()) != json.loads(before[relative]):
            paths.append(path)
    for start in range(0, len(paths), 128):
        result = subprocess.run(
            [
                "bun",
                "x",
                "prettier",
                "--config",
                str(ROOT / ".prettierrc.json"),
                "--write",
                *map(str, paths[start : start + 128]),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            log = chapter.parent / "format-error.log"
            log.write_text(result.stdout + result.stderr)
            raise RuntimeError(
                f"Project JSON formatting failed: {log}\n{result.stdout}{result.stderr}"
            )
    return len(paths)


def prepare_map(chapter: Path, source: Path, deployment: dict) -> dict:
    """Merge one native context into an isolated chapter; callers publish after closure."""
    presentation = import_presentation(chapter, source)
    result = publish_map(chapter, source, deployment, presentation)
    actions = compile_actions(chapter)
    entry_path = chapter / "chapter.json"
    entry = json.loads(entry_path.read_text())
    battle = deployment["battleId"]
    entry["battles"][battle] = resource_path(
        chapter, chapter / "generated/battles" / battle / "battle.json"
    )
    entry_path.write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n")
    return {"presentation": presentation, "map": result, "actions": actions}


def normalize_deployment(chapter: Path, deployment: dict) -> dict:
    """Apply explicit authored identity/position choices before sampling or publication."""
    result = copy.deepcopy(deployment)
    records = result["units"]
    path = chapter / "authored/battles" / f"{deployment['battleId']}.json"
    authored = json.loads(path.read_text()) if path.is_file() else {}
    for change in authored.get("deploymentAdjustments", []):
        if not isinstance(change, dict) or set(change) - {
            "sourceId",
            "deploymentIndex",
            "id",
            "position",
        }:
            raise ValueError("Invalid deployment adjustment fields")
        if ("sourceId" in change) == ("deploymentIndex" in change):
            raise ValueError("Deployment adjustment requires one identity selector")
        if not ({"id", "position"} & change.keys()):
            raise ValueError("Deployment adjustment must declare an identity or position")
        if "deploymentIndex" in change:
            index = change["deploymentIndex"]
            if type(index) is not int or not 0 <= index < len(records):
                raise ValueError("Deployment adjustment index is outside the declaration")
            row = records[index]
        else:
            if type(change["sourceId"]) is not int or not 0 <= change["sourceId"] <= 127:
                raise ValueError("Invalid deployment adjustment source identity")
            candidates = [row for row in records if row["sourceId"] == change["sourceId"]]
            if len(candidates) != 1:
                raise ValueError("Deployment adjustment identity is ambiguous")
            row = candidates[0]
        if "id" in change:
            identity = change["id"]
            if (
                type(identity) is not int
                or not 0 <= identity <= 2147483647
                or "deploymentSlot" in row
            ):
                raise ValueError("Invalid explicit deployment identity")
            row["id"] = identity
        if "position" in change:
            position = change["position"]
            if (
                not isinstance(position, list)
                or len(position) != 2
                or any(type(value) is not int for value in position)
                or not 0 <= position[0] < result["width"]
                or not 0 <= position[1] < result["height"]
            ):
                raise ValueError("Invalid deployment adjustment position")
            row.pop("deploymentRegions", None)
            row["position"] = position
    for faction in authored.get("deploymentRevealFactions", []):
        for row in records:
            if row["faction"] == faction:
                row["flags"] &= ~1
    identities = [row.get("id", row["sourceId"]) for row in records if "deploymentSlot" not in row]
    if len(set(identities)) != len(identities):
        raise ValueError("Duplicate fixed deployment identities; declare an explicit adjustment")
    return result


def publish_map(chapter: Path, source: Path, deployment: dict, presentation: dict) -> dict:
    """Publish map-owned outputs without duplicating profiles or replacing authored story.

    Multiple native preparation contexts may extend a map's recipe bindings. A conflicting
    binding is rejected before publication because the runtime cannot guess a variant.
    Source records are kept in original order and include unresolved deployment slots.
    """
    chapter, source = chapter.resolve(), source.resolve()
    battle_id = deployment["battleId"]
    target = chapter / "generated/battles" / battle_id
    story = chapter / "authored/battles" / f"{battle_id}.json"
    if not story.is_file():
        raise ValueError(f"Missing authored battle configuration: {battle_id}")
    native_map = json.loads((source / "map.json").read_text())
    if (native_map["width"], native_map["height"]) != (
        deployment["width"],
        deployment["height"],
    ):
        raise ValueError(f"Native map dimensions disagree with deployment: {battle_id}")
    records = normalize_deployment(chapter, deployment)["units"]
    bindings = {}
    previous_path = target / "battle.json"
    if previous_path.is_file():
        previous = json.loads(previous_path.read_text())
        if (
            previous.get("stage") != presentation["stage"]
            or previous.get("scene") != presentation["scene"]
        ):
            raise ValueError(
                f"Presentation context changed for {battle_id}; refresh the map explicitly"
            )
        bindings = previous["profiles"]
    for recipe, profile in presentation["recipes"].items():
        if recipe in bindings and bindings[recipe] != profile:
            raise ValueError(f"Conflicting map profile binding: {battle_id}:{recipe}")
        bindings[recipe] = profile
    entry = {
        "battleId": battle_id,
        "map": resource_path(chapter, target / "map.json"),
        "mapTexture": resource_path(chapter, target / "map.png"),
        "deployments": resource_path(chapter, target / "deployments.json"),
        "profiles": bindings,
        "stage": presentation["stage"],
        "scene": presentation["scene"],
        "story": resource_path(chapter, story),
    }
    with tempfile.TemporaryDirectory(prefix="emblem-map-") as directory:
        output = Path(directory)
        for name, data in (
            ("map.json", native_map),
            ("deployments.json", records),
            ("battle.json", entry),
        ):
            (output / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        (output / "map.png").write_bytes((source / "map.png").read_bytes())
        sidecar = Path(str(source / "map.png") + ".import")
        if sidecar.is_file():
            (output / "map.png.import").write_bytes(sidecar.read_bytes())
        sampled = json.loads((source / "provenance.json").read_text())
        provenance = {
            key: sampled[key]
            for key in ("sourceSha256", "emulatorSha256", "map", "deployment")
            if key in sampled
        }
        provenance["recordCount"] = len(records)
        provenance["outputs"] = ["map.json", "map.png", "deployments.json", "battle.json"]
        provenance["description"] = (
            "Original map and ordered deployment; presentation owned by chapter library"
        )
        (output / "provenance.json").write_text(
            json.dumps(provenance, ensure_ascii=False, indent=2) + "\n"
        )
        result = publish_generated(output, target, chapter)
    return {"battleId": battle_id, "profiles": len(bindings), "textures": result}
