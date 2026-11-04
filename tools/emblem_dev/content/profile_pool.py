"""Convert shared profile definitions to the importer's editable working data."""

import copy
import json


def expand(bank: dict) -> dict:
    pool = bank.pop("appearancePool")
    for profile in bank["profiles"].values():
        profile["appearances"] = {
            weapon: copy.deepcopy(pool[reference])
            for weapon, reference in profile["appearances"].items()
        }
    return pool


def _references(values, previous: dict, prefix: str):
    def value_key(value):
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

    identifiers = {}
    for name, value in previous.items():
        identifiers.setdefault(value_key(value), name)
    next_id = 0
    used = {}
    references = []
    for value in values:
        key = value_key(value)
        reference = identifiers.get(key)
        if reference is None:
            while f"{prefix}_{next_id:06d}" in previous:
                next_id += 1
            reference = f"{prefix}_{next_id:06d}"
            next_id += 1
            identifiers[key] = reference
        used[reference] = value
        references.append(reference)
    return references, used


def compact(bank: dict, previous: dict) -> None:
    entries = [
        (profile["appearances"], weapon)
        for profile in bank["profiles"].values()
        for weapon in profile["appearances"]
    ]
    refs, bank["appearancePool"] = _references(
        (appearances[weapon] for appearances, weapon in entries), previous, "appearance"
    )
    for (appearances, weapon), ref in zip(entries, refs, strict=True):
        appearances[weapon] = ref


def expand_animations(bank: dict) -> dict:
    pool = bank.pop("mapAnimationPool")
    for profile in bank["profiles"].values():
        profile["mapAnimation"] = copy.deepcopy(pool[profile["mapAnimation"]])
    return pool


def compact_animations(bank: dict, previous: dict) -> None:
    profiles = list(bank["profiles"].values())
    refs, bank["mapAnimationPool"] = _references(
        (profile["mapAnimation"] for profile in profiles), previous, "animation"
    )
    for profile, ref in zip(profiles, refs, strict=True):
        profile["mapAnimation"] = ref
