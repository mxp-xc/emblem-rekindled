"""Compile verified chapter item actions and map presentation into the runtime snapshot."""

import copy
import json
from pathlib import Path


def compile_actions(chapter: Path) -> dict:
    """Apply authored ability declarations without deriving map rules from item IDs."""
    chapter = chapter.resolve()
    actions_path = chapter / "authored/item_actions.json"
    if not actions_path.is_file():
        return {"items": 0, "effects": 0}
    actions = json.loads(actions_path.read_text())
    entry = json.loads((chapter / "chapter.json").read_text())
    game = chapter.parents[1]
    rules_path = game / entry["rules"][6:]
    library_path = game / entry["library"][6:]
    rules, library = json.loads(rules_path.read_text()), json.loads(library_path.read_text())
    items = {str(item["id"]): item for item in rules["itemTemplates"]}
    declarations = actions["items"]
    for identity, definition in declarations.items():
        if identity not in items or items[identity]["damageKind"] not in ("physical", "magic"):
            raise ValueError(f"Map action references an unknown attack item: {identity}")
        if definition["actionMode"] != "map_attack":
            raise ValueError(f"Expected a declared map action: {identity}")
        if definition["mapEffect"] not in actions["effects"]:
            raise ValueError(f"Map action references a missing effect: {identity}")
        target, rounds = definition["targetRule"], definition["roundRule"]
        shape = target.get("shape")
        if (
            shape not in ("all_hostile", "square", "cross")
            or target.get("selection") not in ("none", "hostile_unit")
            or target.get("range") not in ("map", "item")
        ):
            raise ValueError(f"Invalid map target rule: {identity}")
        if shape == "all_hostile":
            if target["selection"] != "none" or target["range"] != "map":
                raise ValueError(f"Invalid map-wide target rule: {identity}")
        elif (
            target["selection"] != "hostile_unit"
            or target["range"] != "item"
            or type(target.get("radius")) is not int
            or target["radius"] < 1
        ):
            raise ValueError(f"Invalid area target rule: {identity}")
        if (
            type(rounds.get("period")) is not int
            or rounds["period"] < 1
            or type(rounds.get("remainder")) is not int
            or not 0 <= rounds["remainder"] < rounds["period"]
        ):
            raise ValueError(f"Invalid map round rule: {identity}")
    for item in rules["itemTemplates"]:
        for key in ("actionMode", "targetRule", "roundRule", "mapEffect"):
            item.pop(key, None)
        if item["damageKind"] in ("physical", "magic"):
            item["actionMode"] = "battle_clip"
            item.update(copy.deepcopy(declarations.get(str(item["id"]), {})))
    effects = {}
    for key, definition in actions["effects"].items():
        effect = copy.deepcopy(definition)
        if type(effect.get("logicalTickUnits")) is not int or effect["logicalTickUnits"] < 1:
            raise ValueError(f"Invalid map effect clock: {key}")
        sprite_key = effect.pop("spriteKey", None)
        if effect["kind"] == "sprite":
            candidates = [
                scene["effects"][sprite_key]
                for scene in library["scenes"].values()
                if sprite_key in scene.get("effects", {})
            ]
            if not candidates or any(candidate != candidates[0] for candidate in candidates):
                raise ValueError(f"Map effect sprite is missing or ambiguous: {key}")
            effect["sprite"] = copy.deepcopy(candidates[0])
            sequence = effect["sequence"]
            if not sequence or any(
                type(index) is not int or not 0 <= index < len(effect["sprite"]["frames"])
                for index in sequence
            ):
                raise ValueError(f"Map effect sequence is invalid: {key}")
            if effect.get("anchor") != "bottomCenter" or any(
                type(effect.get(field)) is not int or effect[field] < 1
                for field in ("cycles", "stepUnits")
            ):
                raise ValueError(f"Invalid map sprite timing or anchor: {key}")
        elif effect["kind"] != "shake":
            raise ValueError(f"Unsupported map effect kind: {key}")
        effects[key] = effect
    library["mapEffects"] = effects
    # Both complete values are prepared and checked before either output is touched.
    for path, data in ((rules_path, rules), (library_path, library)):
        original = json.loads(path.read_text())
        if data != original:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    return {"items": len(declarations), "effects": len(effects)}
