"""Build the chapter presentation bank from native exports without deployment-ID identity."""

import copy
import json
import shutil
import tempfile
from pathlib import Path

from emblem_dev.content import profile_pool
from emblem_dev.content.assets import (
    group_texture_sources,
    publish_generated,
    texture_import_parameters,
    texture_import_settings,
    texture_pixels,
    texture_sources,
)

UNIT_FIELDS = (
    "name",
    "className",
    "classId",
    "classGroup",
    "faction",
    "sourceId",
    "formal",
    "equipMask",
    "sprite",
    "spriteOffsetX",
    "spriteOffsetY",
)
STAGE_FIELDS = (
    "tickMillis",
    "logicTickUnits",
    "spriteTickUnits",
    "viewport",
    "stage",
    "coordinates",
    "composition",
    "effectTails",
    "hpContract",
)
STORY_COMMON_FIELDS = (
    "schemaVersion",
    "chapterId",
    "sourceSha256",
    "labels",
    "images",
    "world",
    "tutorials",
    "tutorialGroups",
    "textFormat",
    "timing",
)


def _read(path: Path):
    return json.loads(path.read_text())


def _write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def sampling_context(art: dict) -> dict:
    """Global native pixels and terrain placement geometry affecting sampled clips."""
    geometries = []
    for background in art.get("backgrounds", {}).values():
        geometry = {
            "virtualWidth": background.get("virtualWidth"),
            "virtualHeight": background.get("virtualHeight"),
            "frames": [
                {
                    key: frame.get(key)
                    for key in (
                        "bodyWidth",
                        "bodyHeight",
                        "bodyOffsetX",
                        "bodyOffsetY",
                        "originalFlag",
                    )
                }
                for frame in background["frames"]
            ],
        }
        if geometry not in geometries:
            geometries.append(geometry)
    return {
        "effects": art.get("effects", {}),
        "terrainGeometries": sorted(
            geometries, key=lambda value: json.dumps(value, sort_keys=True)
        ),
    }


def import_presentation(chapter: Path, source: Path, *, dry_run: bool = False) -> dict:
    """Merge source profiles and motion pairs; publish only the bank owner's outputs.

    Source is an isolated native export (units/spawns/map animations/UI/art/clips).
    Existing profiles are immutable except for adding new weapons or stage bindings.
    Returned deployment bindings are the small map-specific output, never a route copy.
    All planning/validation happens before publication. Dry runs leave both trees intact.
    """
    chapter, source = chapter.resolve(), source.resolve()
    library = chapter / "generated/library"
    game = chapter.parents[1]
    existing = library / "catalog.json"
    previous_sources = (
        texture_sources(_read(library / "provenance.json"))
        if (library / "provenance.json").exists()
        else {}
    )
    previous_metadata = (
        (library / "provenance.json").read_bytes()
        if (library / "provenance.json").exists()
        else None
    )
    bank = (
        _read(existing)
        if existing.exists()
        else {
            "profiles": {},
            "stages": {},
            "scenes": {},
            "appearancePool": {},
            "mapAnimationPool": {},
        }
    )
    bank = copy.deepcopy(bank)
    previous_appearances = profile_pool.expand(bank)
    previous_animations = profile_pool.expand_animations(bank)
    defaults = _read(chapter / "generated/shared/provenance.json")["textureImportParameters"]
    art = _read(source / "battle/manifest.json")
    motion = _read(source / "battle/clips/manifest.json")
    animations = _read(source / "map_animations.json")["units"]
    interface = _read(source / "ui/manifest.json")
    spawns = {spawn["id"]: spawn for spawn in _read(source / "spawns.json")}
    units = _read(source / "units.json")
    signature = {key: motion[key] for key in STAGE_FIELDS}
    previous_stages = set(bank["stages"])
    stage_id = next(
        (
            key
            for key, stage in bank["stages"].items()
            if {field: stage[field] for field in STAGE_FIELDS} == signature
        ),
        None,
    )
    if stage_id is None:
        stage_id = f"stage_{len(bank['stages'])}"
        stage = copy.deepcopy(motion)
        for field in (
            "appearances",
            "textures",
            "clips",
            "actionGroups",
            "defenseGroups",
            "deaths",
        ):
            stage[field] = {}
        stage.pop("reusedClips", None)
        stage.pop("reusedDeaths", None)
        bank["stages"][stage_id] = stage
    stage = bank["stages"][stage_id]
    reused_clips = motion.get("reusedClips", [])
    reused_deaths = motion.get("reusedDeaths", [])
    for names, field in ((reused_clips, "clips"), (reused_deaths, "deaths")):
        if (
            not isinstance(names, list)
            or any(not isinstance(name, str) for name in names)
            or len(names) != len(set(names))
        ):
            raise ValueError(f"Invalid reused {field} declaration")
        if any(name not in stage[field] or name in motion[field] for name in names):
            raise ValueError(f"Unknown or duplicate reused {field} in {stage_id}")
    for name in reused_clips:
        path = stage["clips"][name]
        if not (game / path[6:] if path.startswith("res://") else library / path).is_file():
            raise ValueError(f"Reused sampled motion file is missing: {name}")
    images: dict[Path, Path] = {}
    image_settings: dict[Path, tuple] = {}
    image_contents: dict[Path, tuple] = {}
    published_settings: dict[Path, tuple] = {}
    clip_writes: dict[Path, dict] = {}
    report = {
        "stage": stage_id,
        "profilesAdded": 0,
        "profilesReused": 0,
        "clipsAdded": 0,
        "clipsReused": len(reused_clips),
        "deathsReused": len(reused_deaths),
        "bindings": {},
        "recipes": {},
    }

    def resolve(value: str, directory: Path) -> Path:
        return (game / value[6:] if value.startswith("res://") else directory / value).resolve()

    def source_label(key, value, directory):
        return (
            key == "source"
            and isinstance(value, str)
            and resolve(value, directory) not in images
            and not resolve(value, directory).is_file()
        )

    def comparable(value, directory):
        if isinstance(value, dict):
            return {
                key: item if source_label(key, item, directory) else comparable(item, directory)
                for key, item in value.items()
            }
        if isinstance(value, list):
            return [comparable(item, directory) for item in value]
        if isinstance(value, str) and value.endswith(".png"):
            path = resolve(value, directory)
            settings = image_settings.get(path)
            if path in images:
                path = images[path]
            if path.is_file():
                if path not in image_contents:
                    image_contents[path] = texture_pixels(path)
                if settings is None:
                    if path not in published_settings:
                        published_settings[path] = texture_import_parameters(path, defaults)
                    settings = published_settings[path]
                return image_contents[path], settings
        return value

    def sampling_comparable(value, directory):
        if isinstance(value, dict):
            return {
                key: item
                if source_label(key, item, directory)
                else sampling_comparable(item, directory)
                for key, item in value.items()
            }
        if isinstance(value, list):
            return [sampling_comparable(item, directory) for item in value]
        if isinstance(value, str) and value.endswith(".png"):
            path = resolve(value, directory)
            if not path.is_file():
                raise ValueError(f"Missing native sampling resource: {path}")
            if path not in image_contents:
                image_contents[path] = texture_pixels(path)
            return image_contents[path]
        return value

    if stage_id in previous_stages:
        scene_ids = set()
        chapter_entry = chapter / "chapter.json"
        if chapter_entry.is_file():
            for path in _read(chapter_entry).get("battles", {}).values():
                definition = _read(game / path[6:])
                if definition.get("stage") == stage_id:
                    scene_ids.add(definition["scene"])
        prior_scenes = (
            [bank["scenes"][identity] for identity in scene_ids]
            if scene_ids
            else list(bank["scenes"].values())
        )
        incoming_context = sampling_comparable(sampling_context(art), source / "battle")
        if any(
            sampling_comparable(sampling_context(scene), library) != incoming_context
            for scene in prior_scenes
        ):
            raise ValueError(
                "Native sampling pixels or terrain placement changed; "
                "define a new stage context and resample before reuse"
            )

    def resource(path):
        return "res://" + path.relative_to(game).as_posix()

    def inherit_fields(incoming, prior, directory, namespace):
        if isinstance(incoming, dict) and isinstance(prior, dict):
            for key in incoming.keys() & prior.keys():
                if not source_label(key, incoming[key], directory):
                    inherit_fields(incoming[key], prior[key], directory, namespace)
        elif isinstance(incoming, list) and isinstance(prior, list):
            for item, before in zip(incoming, prior, strict=False):
                inherit_fields(item, before, directory, namespace)
        elif (
            isinstance(incoming, str)
            and incoming.endswith(".png")
            and isinstance(prior, str)
            and prior.endswith(".png")
        ):
            path = resolve(incoming, directory)
            previous = resolve(prior, library)
            if (
                path.is_file()
                and not path.is_relative_to(chapter)
                and not Path(str(path) + ".import").exists()
                and previous.is_file()
            ):
                destination = library / "images" / namespace / path.relative_to(source)
                settings = texture_import_parameters(previous, defaults)
                if destination in image_settings and image_settings[destination] != settings:
                    raise ValueError(f"Conflicting inherited texture parameters: {destination}")
                image_settings[destination] = settings

    def relocate(value, directory, namespace, fallback_namespace=None):
        if isinstance(value, dict):
            return {
                key: (
                    item
                    if source_label(key, item, directory)
                    else relocate(item, directory, namespace, fallback_namespace)
                )
                for key, item in value.items()
            }
        if isinstance(value, list):
            return [relocate(item, directory, namespace, fallback_namespace) for item in value]
        if isinstance(value, str) and value.endswith(".png"):
            path = resolve(value, directory)
            if not path.is_file():
                raise ValueError(f"Missing presentation texture: {path}")
            if path.is_file():
                # Keep already-published chapter images; stage only new native images.
                if path.is_relative_to(chapter):
                    return resource(path)
                relative = path.relative_to(source)
                destination = library / "images" / namespace / relative
                if destination in images and texture_pixels(images[destination]) != texture_pixels(
                    path
                ):
                    raise ValueError(f"Conflicting image in presentation request: {destination}")
                images[destination] = path
                settings = image_settings.get(
                    destination, texture_import_parameters(path, defaults)
                )
                if destination not in image_settings and not Path(str(path) + ".import").exists():
                    for previous_namespace in (namespace, fallback_namespace):
                        if previous_namespace is None:
                            continue
                        old_name = (Path("images") / previous_namespace / relative).as_posix()
                        if old_name not in previous_sources:
                            continue
                        prior = (chapter / previous_sources[old_name]).resolve()
                        if (
                            not prior.is_relative_to(chapter / "generated/shared")
                            or not prior.is_file()
                        ):
                            raise ValueError(
                                f"Invalid shared source texture: {previous_sources[old_name]}"
                            )
                        settings = texture_import_parameters(prior, defaults)
                        break
                image_settings[destination] = settings
                return resource(destination)
        return value

    def merge_groups(field):
        for key, definition in motion[field].items():
            if key in stage[field] and stage[field][key] != definition:
                raise ValueError(f"Conflicting {field} definition: {key}")
            stage[field][key] = definition

    def merge_common(prior, incoming, location):
        if isinstance(prior, dict) and isinstance(incoming, dict):
            merged = copy.deepcopy(prior)
            for key, value in incoming.items():
                merged[key] = (
                    merge_common(merged[key], value, location + "." + key)
                    if key in merged
                    else value
                )
            return merged
        if comparable(prior, library) != comparable(incoming, library):
            raise ValueError(f"Conflicting chapter common definition: {location}")
        return prior

    common_interface = copy.deepcopy(interface)
    portraits = common_interface.pop("portraitByUnitId")
    portrait_textures = {
        entry["texture"] for entry in portraits.values() if entry["texture"] is not None
    }

    def texture_references(value):
        if isinstance(value, dict):
            return set().union(*(texture_references(item) for item in value.values()))
        if isinstance(value, list):
            return set().union(*(texture_references(item) for item in value))
        return {value} if isinstance(value, str) else set()

    other_references = texture_references(
        {key: value for key, value in common_interface.items() if key != "textures"}
    )
    common_interface["textures"] = {
        key: value
        for key, value in common_interface["textures"].items()
        if key not in portrait_textures or key in other_references
    }
    # The native HUD can be offscreen during source sampling. Its current top is
    # transient state; the remaining geometry describes the shared presentation.
    common_interface.get("mapHud", {}).get("nativeReferenceLayout", {}).pop("top", None)
    common_interface = relocate(common_interface, source / "ui", "interface")
    bank["interface"] = merge_common(bank.get("interface", {}), common_interface, "interface")
    story_path = source / "story/manifest.json"
    if story_path.exists():
        story = _read(story_path)
        common_story = {key: story[key] for key in STORY_COMMON_FIELDS if key in story}
        common_story["sequences"] = {
            key: value
            for key, value in story.get("sequences", {}).items()
            if key in ("boot", "newGame", "defeat")
        }
        common_story = relocate(common_story, story_path.parent, "story")
        bank["storyCommon"] = merge_common(bank.get("storyCommon", {}), common_story, "storyCommon")
        if "texts" in story:
            bank["texts"] = merge_common(bank.get("texts", {}), story["texts"], "texts")

    for field in ("actionGroups", "defenseGroups"):
        merge_groups(field)

    texture_ids = {}
    next_texture_id = len(stage["textures"])
    for key, value in motion["textures"].items():
        definition = relocate(value, source / "battle/clips", stage_id)
        match = next(
            (
                name
                for name, prior in stage["textures"].items()
                if comparable(prior, library) == comparable(definition, library)
            ),
            None,
        )
        if match is None:
            while f"texture_{next_texture_id}" in stage["textures"]:
                next_texture_id += 1
            match = f"texture_{next_texture_id}"
            stage["textures"][match] = definition
            next_texture_id += 1
        texture_ids[key] = match

    def bind_textures(value):
        if isinstance(value, dict):
            return {key: bind_textures(item) for key, item in value.items()}
        if isinstance(value, list):
            return [bind_textures(item) for item in value]
        if isinstance(value, str):
            return texture_ids.get(value, value)
        return value

    for key, value in motion["deaths"].items():
        death = bind_textures(value)
        if key in stage["deaths"] and stage["deaths"][key] != death:
            raise ValueError(f"Conflicting death motion: {key}")
        stage["deaths"][key] = death
    for key, relative in motion["clips"].items():
        clip = bind_textures(_read(source / "battle/clips" / relative))
        clip.pop("attackerAppearance", None)
        clip.pop("defenderAppearance", None)
        if key in stage["clips"]:
            path = resolve(stage["clips"][key], library)
            prior = clip_writes.get(path) if path in clip_writes else _read(path)
            if prior != clip:
                raise ValueError(f"Conflicting sampled motion in {stage_id}: {key}")
            report["clipsReused"] += 1
        else:
            path = library / "clips" / stage_id / relative
            clip_writes[path] = clip
            stage["clips"][key] = resource(path)
            report["clipsAdded"] += 1

    for unit in units:
        identity = unit["id"]
        spawn = spawns[identity]
        slot = spawn.get("deploymentSlot", spawn["sourceId"])
        kind = (
            "slot"
            if not spawn["formal"] and spawn["faction"] == 0 and spawn["policy"] & 32
            else "source"
        )
        origin = slot if kind == "slot" else spawn["sourceId"]
        recipe = f"{kind}_{origin}_job_{unit['classId']}_faction_{unit['faction']}"
        prototype = {key: unit[key] for key in UNIT_FIELDS}
        if spawn.get("summoned", False):
            first = 20 if unit["faction"] == 1 else 70
            if (
                unit["faction"] not in (1, 2)
                or unit["classId"] not in (28, 29, 32, 33, 36, 37)
                or unit["classGroup"] != unit["classId"] // 4
                or not first <= unit["sourceId"] < first + 10
                or unit["formal"]
            ):
                raise ValueError("Invalid native summon family")
            # Instance identity is stored by the runtime binding. Sharing still
            # requires every sampled name, portrait, map and battle field to match.
            recipe = f"summon_job_{unit['classId']}_faction_{unit['faction']}"
            prototype["sourceId"] = first
            prototype.update(
                baseTemplateId=10 + unit["classId"],
                initialGrowthTemplateId=10 + unit["classGroup"],
                growthTemplateId=10 + unit["classGroup"],
            )
        map_animation = copy.deepcopy(animations[str(identity)])
        map_animation.pop("deploymentId", None)
        portrait = copy.deepcopy(interface["portraitByUnitId"][str(identity)])
        if portrait["texture"] is not None:
            portrait["texture"] = interface["textures"][portrait["texture"]]
        entries = {}
        for key, value in art["appearances"].items():
            actor, weapon = key.split(":")
            if int(actor) != identity:
                continue
            appearance = copy.deepcopy(value)
            appearance.pop("deploymentId", None)
            entries[weapon] = appearance
        candidate = {
            "unit": prototype,
            "mapAnimation": map_animation,
            "portrait": portrait,
            "appearances": entries,
            "motion": {stage_id: {}},
        }

        def prepared(
            namespace,
            prototype=prototype,
            map_animation=map_animation,
            portrait=portrait,
            entries=entries,
            recipe=recipe,
        ):
            prior = bank["profiles"].get(namespace, bank["profiles"].get(recipe))
            if prior is not None:
                for field, incoming, directory in (
                    ("unit", prototype, source),
                    ("mapAnimation", map_animation, source),
                    ("portrait", portrait, source / "ui"),
                    ("appearances", entries, source / "battle"),
                ):
                    inherit_fields(incoming, prior[field], directory, namespace)
            return {
                "unit": relocate(prototype, source, namespace, recipe),
                "mapAnimation": relocate(map_animation, source, namespace, recipe),
                "portrait": relocate(portrait, source / "ui", namespace, recipe),
                "appearances": {
                    key: relocate(value, source / "battle", namespace, recipe)
                    for key, value in entries.items()
                },
            }

        chosen = None
        for name, prior in bank["profiles"].items():
            if name != recipe and not name.startswith(recipe + "_"):
                continue
            comparison = comparable(prepared(name), library)
            previous = comparable(prior, library)
            common = comparison["appearances"].keys() & previous["appearances"].keys()
            if all(
                comparison[field] == previous[field]
                for field in ("unit", "mapAnimation", "portrait")
            ) and all(
                comparison["appearances"][weapon] == previous["appearances"][weapon]
                for weapon in common
            ):
                chosen = name
                break
        if chosen is None:
            chosen = recipe
            suffix = 2
            while chosen in bank["profiles"]:
                chosen = f"{recipe}_{suffix}"
                suffix += 1
            candidate.update(prepared(chosen))
            candidate["appearances"] = {}
            bank["profiles"][chosen] = candidate
            report["profilesAdded"] += 1
        else:
            report["profilesReused"] += 1
        profile = bank["profiles"][chosen]
        for weapon, appearance in entries.items():
            if weapon not in profile["appearances"]:
                profile["appearances"][weapon] = relocate(
                    appearance, source / "battle", chosen, recipe
                )
            binding = motion["appearances"][f"{identity}:{weapon}"]
            bindings = profile["motion"].setdefault(stage_id, {})
            if weapon in bindings and bindings[weapon] != binding:
                raise ValueError(f"Conflicting profile motion binding: {chosen}:{weapon}")
            bindings[weapon] = binding
        report["bindings"][str(identity)] = chosen
        if recipe in report["recipes"] and report["recipes"][recipe] != chosen:
            raise ValueError(f"Ambiguous presentation recipe within one map: {recipe}")
        report["recipes"][recipe] = chosen
        if spawn.get("summoned", False):
            identities = (
                bank.setdefault("summons", {})
                .setdefault(str(unit["faction"]), {})
                .setdefault(str(unit["classId"]), {})
            )
            source_id = str(unit["sourceId"])
            if source_id in identities and identities[source_id] != chosen:
                raise ValueError("Conflicting native summon family")
            identities[source_id] = chosen

    # Terrain/background coverage belongs to a scene, not the last map to be imported.
    scene = {key: value for key, value in art.items() if key != "appearances"}
    scene_id = None
    for name, prior in bank["scenes"].items():
        inherit_fields(scene, prior, source / "battle", name)
        if comparable(prior, library) == comparable(
            relocate(scene, source / "battle", name), library
        ):
            scene_id = name
            break
    if scene_id is None:
        scene_id = f"scene_{len(bank['scenes'])}"
        fallback_scene = next(iter(bank["scenes"]), None)
        bank["scenes"][scene_id] = relocate(scene, source / "battle", scene_id, fallback_scene)
    report["scene"] = scene_id
    profile_pool.compact(bank, previous_appearances)
    profile_pool.compact_animations(bank, previous_animations)
    referenced_images: set[Path] = set()

    def collect_images(value):
        if isinstance(value, dict):
            for item in value.values():
                collect_images(item)
        elif isinstance(value, list):
            for item in value:
                collect_images(item)
        elif isinstance(value, str) and value.endswith(".png"):
            path = resolve(value, library)
            if path in images:
                referenced_images.add(path)

    collect_images(bank)
    images = {path: original for path, original in images.items() if path in referenced_images}
    if not dry_run:
        with tempfile.TemporaryDirectory(prefix="emblem-library-") as temporary:
            output = Path(temporary) / "library"
            if library.exists():
                shutil.copytree(library, output)
            else:
                output.mkdir()
            for path, data in clip_writes.items():
                _write(output / path.relative_to(library), data)
            for path, original in images.items():
                destination = output / path.relative_to(library)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(original, destination)
                sidecar = Path(str(original) + ".import")
                if sidecar.exists():
                    shutil.copyfile(sidecar, Path(str(destination) + ".import"))
                else:
                    Path(str(destination) + ".import").write_bytes(
                        texture_import_settings(image_settings[path])
                    )
            if not existing.exists() or _read(existing) != bank:
                _write(output / "catalog.json", bank)
            owned = sorted(
                p.relative_to(output).as_posix()
                for p in output.rglob("*")
                if p.is_file() and p.name != "provenance.json" and p.suffix != ".import"
            )
            _write(
                output / "provenance.json",
                {
                    "description": "Chapter presentation profiles and sampled motion",
                    "outputs": owned,
                },
            )
            publish_generated(output, library, chapter)
            # Texture sharing can make newly published paths identical to an
            # existing appearance. Coalesce only after paths have settled.
            published = _read(existing)
            published_pool = profile_pool.expand(published)
            published_animations = profile_pool.expand_animations(published)
            profile_pool.compact(published, previous_appearances | published_pool)
            profile_pool.compact_animations(published, previous_animations | published_animations)
            if _read(existing) != published:
                _write(existing, published)
            # The bank keeps old profiles even when a new native export does not emit
            # their source PNGs. Preserve their semantic source paths for later refreshes.
            provenance_path = library / "provenance.json"
            metadata = _read(provenance_path)
            sources = previous_sources | texture_sources(metadata)
            metadata["textureSourceGroups"] = group_texture_sources(
                {name: path for name, path in sorted(sources.items()) if (chapter / path).is_file()}
            )
            if _read(provenance_path) != metadata:
                _write(provenance_path, metadata)
            if previous_metadata is not None and json.loads(previous_metadata) == metadata:
                if provenance_path.read_bytes() != previous_metadata:
                    provenance_path.write_bytes(previous_metadata)
    return report
