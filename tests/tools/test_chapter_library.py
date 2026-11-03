"""Presentation bank identity, immutable motion reuse and owner-safe publication."""

import json
import tempfile
import unittest
from pathlib import Path

from emblem_dev.content.assets import texture_import_parameters
from emblem_dev.content.library import STAGE_FIELDS, import_presentation


class ChapterLibraryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.chapter = self.root / "game/content/chapter_1"
        self.write(
            self.chapter / "generated/shared/provenance.json",
            {"outputs": [], "textureImportParameters": {"compress/mode": "0"}},
        )

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def native(self, directory, identity=0, pixels=b"same", weapon=1):
        source = self.root / directory
        source.mkdir()
        (source / "sprite.png").write_bytes(pixels)
        unit = {
            "id": identity,
            "name": "King",
            "className": "King",
            "classId": 0,
            "classGroup": 0,
            "faction": 0,
            "sourceId": 0,
            "formal": True,
            "equipMask": 1,
            "sprite": "sprite.png",
            "spriteOffsetX": -24,
            "spriteOffsetY": -24,
        }
        self.write(source / "units.json", [unit])
        self.write(
            source / "spawns.json",
            [{"id": identity, "sourceId": 0, "formal": True, "faction": 0, "policy": 0}],
        )
        self.write(
            source / "map_animations.json",
            {
                "units": {
                    str(identity): {"deploymentId": identity, "frames": [{"texture": "sprite.png"}]}
                }
            },
        )
        self.write(
            source / "ui/manifest.json",
            {
                "portraitByUnitId": {
                    str(identity): {"usesCommanderPortrait": False, "texture": "face"}
                },
                "textures": {"face": {"texture": "../sprite.png"}},
            },
        )
        art = {
            "appearances": {
                f"{identity}:{weapon}": {
                    "deploymentId": identity,
                    "classId": 0,
                    "nativeSide": "left",
                    "frames": [{"texture": "../sprite.png", "offsetX": -1, "offsetY": 2}],
                }
            },
            "backgrounds": {"grass": {"frames": [{"texture": "../sprite.png"}]}},
            "terrainBackgrounds": {"0": "grass"},
        }
        self.write(source / "battle/manifest.json", art)
        motion = {key: {} for key in STAGE_FIELDS}
        motion.update(
            {
                "tickMillis": 65,
                "logicTickUnits": 50,
                "appearances": {
                    f"{identity}:{weapon}": {
                        "actionGroup": "sword",
                        "defenseGroup": "human",
                        "canAttack": True,
                    }
                },
                "actionGroups": {"sword": {"frames": [[1, 2, 3]]}},
                "defenseGroups": {"human": {"frames": [[1, 2, 3]]}},
                "clips": {"sword/human/0/hit": "hit.json"},
                "textures": {"effect": {"texture": "../../sprite.png"}},
                "deaths": {"human": {"ticks": [[{"texture": "effect"}]]}},
            }
        )
        self.write(source / "battle/clips/manifest.json", motion)
        self.write(
            source / "battle/clips/hit.json",
            {
                "attackerAppearance": f"{identity}:{weapon}",
                "defenderAppearance": "other",
                "ticks": [[{"texture": "effect", "actor": "attacker"}]],
            },
        )
        return source

    def snapshot(self):
        return {
            p.relative_to(self.chapter): p.read_bytes()
            for p in self.chapter.rglob("*")
            if p.is_file()
        }

    def test_import_does_not_overwrite_a_retained_texture_after_pruning(self):
        import_presentation(self.chapter, self.native("first"))
        catalog = self.chapter / "generated/library/catalog.json"
        bank = json.loads(catalog.read_text())
        stage = next(iter(bank["stages"].values()))
        existing = stage["textures"].pop("texture_0")
        stage["textures"]["texture_1"] = existing
        self.write(catalog, bank)

        source = self.native("second")
        manifest = source / "battle/clips/manifest.json"
        motion = json.loads(manifest.read_text())
        motion["textures"]["effect"]["width"] = 9
        motion["clips"] = {}
        motion["deaths"] = {}
        self.write(manifest, motion)
        import_presentation(self.chapter, source)

        updated = json.loads(catalog.read_text())
        textures = next(iter(updated["stages"].values()))["textures"]
        self.assertEqual(textures["texture_1"], existing)
        self.assertEqual(textures["texture_2"]["width"], 9)

    def test_identical_motion_and_profiles_reuse_without_deployment_identity(self):
        first = import_presentation(self.chapter, self.native("first"))
        second = import_presentation(self.chapter, self.native("second", identity=9))
        self.assertEqual(first["bindings"]["0"], second["bindings"]["9"])
        self.assertEqual(second["profilesAdded"], 0)
        self.assertEqual(second["clipsAdded"], 0)
        self.assertEqual(second["clipsReused"], 1)
        library = self.chapter / "generated/library"
        self.assertEqual(len(list(self.chapter.rglob("*.png"))), 1)
        self.assertFalse(list(library.rglob("*.png")))
        self.assertEqual(len(list((library / "clips").rglob("*.json"))), 1)
        before = self.snapshot()
        import_presentation(self.chapter, self.root / "first")
        self.assertEqual(self.snapshot(), before)

    def test_changed_visual_keeps_prior_profile_and_new_weapon_extends_existing(self):
        original = import_presentation(self.chapter, self.native("first"))["bindings"]["0"]
        extension = import_presentation(self.chapter, self.native("extension", weapon=2))
        self.assertEqual(extension["bindings"]["0"], original)
        # Same motion pair with a different texture would not be silently overwritten.
        changed = self.native("changed", pixels=b"different")
        catalog = json.loads((changed / "battle/clips/manifest.json").read_text())
        catalog["textures"] = {}
        catalog["deaths"] = {}
        catalog["clips"] = {}
        self.write(changed / "battle/clips/manifest.json", catalog)
        result = import_presentation(self.chapter, changed)
        self.assertNotEqual(result["bindings"]["0"], original)
        bank = json.loads((self.chapter / "generated/library/catalog.json").read_text())
        self.assertEqual(set(bank["profiles"][original]["appearances"]), {"1", "2"})
        self.assertEqual(len(list((self.chapter / "generated/shared").rglob("*.png"))), 2)

    def test_dry_run_and_conflicting_motion_never_modify_chapter(self):
        source = self.native("first")
        before = self.snapshot()
        plan = import_presentation(self.chapter, source, dry_run=True)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(import_presentation(self.chapter, source), plan)
        conflict = self.native("conflict")
        path = conflict / "battle/clips/hit.json"
        data = json.loads(path.read_text())
        data["ticks"].append([])
        self.write(path, data)
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "Conflicting sampled motion"):
            import_presentation(self.chapter, conflict)
        self.assertEqual(self.snapshot(), before)

    def test_old_map_reimport_keeps_new_scene_and_current_catalog_format(self):
        first = self.native("first")
        first_report = import_presentation(self.chapter, first)
        second = self.native("second")
        scene_path = second / "battle/manifest.json"
        data = json.loads(scene_path.read_text())
        data["terrainBackgrounds"]["9"] = "grass"
        self.write(scene_path, data)
        second_report = import_presentation(self.chapter, second)
        self.assertNotEqual(first_report["scene"], second_report["scene"])
        catalog = self.chapter / "generated/library/catalog.json"
        compact = json.dumps(json.loads(catalog.read_text()), separators=(",", ":"))
        catalog.write_text(compact)
        import_presentation(self.chapter, first)
        self.assertEqual(catalog.read_text(), compact)
        bank = json.loads(catalog.read_text())
        self.assertIn("9", bank["scenes"][second_report["scene"]]["terrainBackgrounds"])

    def test_explicit_reuse_requires_existing_motion_and_never_republishes_pairs(self):
        import_presentation(self.chapter, self.native("first"))
        source = self.native("reuse")
        path = source / "battle/clips/manifest.json"
        motion = json.loads(path.read_text())
        motion["clips"] = {}
        motion["deaths"] = {}
        motion["textures"] = {}
        motion["reusedClips"] = ["sword/human/0/hit"]
        motion["reusedDeaths"] = ["human"]
        self.write(path, motion)
        before = self.snapshot()
        report = import_presentation(self.chapter, source)
        self.assertEqual(report["clipsAdded"], 0)
        self.assertEqual(report["clipsReused"], 1)
        self.assertEqual(report["deathsReused"], 1)
        self.assertEqual(self.snapshot(), before)
        motion["reusedClips"] = ["unknown/human/0/hit"]
        self.write(path, motion)
        with self.assertRaisesRegex(ValueError, "Unknown or duplicate reused clips"):
            import_presentation(self.chapter, source)
        self.assertEqual(self.snapshot(), before)

    def test_same_stage_timing_cannot_reuse_changed_sky_or_terrain_geometry(self):
        first = self.native("first")
        art_path = first / "battle/manifest.json"
        art = json.loads(art_path.read_text())
        art["effects"] = {"cloud": {"texture": "cloud.png", "virtualWidth": 1, "virtualHeight": 1}}
        (first / "battle/cloud.png").write_bytes(b"sky-one")
        self.write(art_path, art)
        import_presentation(self.chapter, first)
        before = self.snapshot()
        changed = self.native("changed")
        self.write(changed / "battle/manifest.json", art)
        (changed / "battle/cloud.png").write_bytes(b"sky-two")
        with self.assertRaisesRegex(ValueError, "sampling pixels or terrain placement changed"):
            import_presentation(self.chapter, changed)
        self.assertEqual(self.snapshot(), before)
        (changed / "battle/cloud.png").write_bytes(b"sky-one")
        art["backgrounds"]["grass"]["virtualHeight"] = 32
        self.write(changed / "battle/manifest.json", art)
        with self.assertRaisesRegex(ValueError, "sampling pixels or terrain placement changed"):
            import_presentation(self.chapter, changed)
        self.assertEqual(self.snapshot(), before)

    def test_native_reimport_inherits_custom_texture_parameters_and_identity(self):
        source = self.native("first")
        (source / "sprite.png.import").write_text(
            '[remap]\nimporter="texture"\nuid="uid://original"\n[params]\ncompress/mode=1\n'
        )
        first = import_presentation(self.chapter, source)
        old = next((self.chapter / "generated/shared").rglob("*.png"))
        before = self.snapshot()
        repeated = import_presentation(self.chapter, self.native("second"))
        self.assertEqual(first["bindings"], repeated["bindings"])
        self.assertEqual(first["recipes"], repeated["recipes"])
        self.assertEqual(self.snapshot(), before)
        self.assertIn('uid="uid://original"', Path(str(old) + ".import").read_text())

        changed = self.native("changed", pixels=b"new")
        motion_path = changed / "battle/clips/manifest.json"
        motion = json.loads(motion_path.read_text())
        motion.update(textures={}, deaths={}, clips={})
        self.write(motion_path, motion)
        result = import_presentation(self.chapter, changed)
        self.assertNotEqual(result["bindings"], first["bindings"])
        images = list((self.chapter / "generated/shared").rglob("*.png"))
        self.assertEqual({p.read_bytes() for p in images}, {b"same", b"new"})
        for image in images:
            self.assertEqual(texture_import_parameters(image, {}), (("compress/mode", "1"),))
        self.assertNotIn(
            "uid=", Path(str(next(p for p in images if p != old)) + ".import").read_text()
        )

    def test_common_interface_and_story_preserve_shared_ui_and_reject_conflicts(self):
        source = self.native("first")
        ui_path = source / "ui/manifest.json"
        ui = json.loads(ui_path.read_text())
        ui["textures"]["hud"] = {"texture": "../sprite.png"}
        ui["textures"]["hud"]["source"] = "../sprite.png"
        ui["provenance"] = {"source": "original-resource.png"}
        ui["window"] = {"texture": "hud"}
        self.write(ui_path, ui)
        self.write(
            source / "story/manifest.json",
            {
                "images": {"intro": {"texture": "../sprite.png"}},
                "labels": {"newGame": {"text": "Start"}},
                "speakers": {"0": {"name": "Different per map"}},
                "texts": {"10": {"text": "A shared line", "sourceTextIndex": 10}},
                "sequences": {"boot": [{"kind": "prologue"}], "opening": [{"kind": "focus"}]},
            },
        )
        import_presentation(self.chapter, source)
        bank = json.loads((self.chapter / "generated/library/catalog.json").read_text())
        self.assertNotIn("portraitByUnitId", bank["interface"])
        self.assertEqual(set(bank["interface"]["textures"]), {"hud"})
        self.assertTrue(bank["interface"]["textures"]["hud"]["texture"].startswith("res://"))
        self.assertTrue(bank["interface"]["textures"]["hud"]["source"].startswith("res://"))
        self.assertEqual(bank["interface"]["provenance"]["source"], "original-resource.png")
        self.assertEqual(set(bank["storyCommon"]["sequences"]), {"boot"})
        self.assertNotIn("speakers", bank["storyCommon"])
        self.assertNotIn("texts", bank["storyCommon"])
        self.assertEqual(bank["texts"]["10"]["text"], "A shared line")
        self.assertTrue(bank["storyCommon"]["images"]["intro"]["texture"].startswith("res://"))
        self.assertTrue(
            next(iter(bank["stages"].values()))["clips"]["sword/human/0/hit"].startswith("res://")
        )
        self.assertEqual(bank["profiles"]["source_0_job_0_faction_0"]["unit"]["sourceId"], 0)
        before = self.snapshot()
        import_presentation(self.chapter, source)
        self.assertEqual(self.snapshot(), before)
        story_path = source / "story/manifest.json"
        story = json.loads(story_path.read_text())
        story["labels"]["newGame"]["text"] = "Changed"
        self.write(story_path, story)
        with self.assertRaisesRegex(ValueError, "Conflicting chapter common definition"):
            import_presentation(self.chapter, source)
        self.assertEqual(self.snapshot(), before)

    def test_explicit_native_import_parameters_do_not_inherit_prior_settings(self):
        source = self.native("first")
        (source / "sprite.png.import").write_text(
            '[remap]\nimporter="texture"\nuid="uid://original"\n[params]\ncompress/mode=1\n'
        )
        first = import_presentation(self.chapter, source)
        changed = self.native("changed")
        (changed / "sprite.png.import").write_text(
            '[remap]\nimporter="texture"\nuid="uid://explicit"\n[params]\ncompress/mode=2\n'
        )
        motion_path = changed / "battle/clips/manifest.json"
        motion = json.loads(motion_path.read_text())
        motion.update(textures={}, deaths={}, clips={})
        self.write(motion_path, motion)
        second = import_presentation(self.chapter, changed)
        self.assertNotEqual(first["bindings"], second["bindings"])
        images = list((self.chapter / "generated/shared").rglob("*.png"))
        self.assertEqual(len(images), 2)
        self.assertEqual(
            {texture_import_parameters(image, {}) for image in images},
            {(("compress/mode", "1"),), (("compress/mode", "2"),)},
        )

    def test_missing_native_texture_fails_before_publication(self):
        source = self.native("first")
        (source / "sprite.png").unlink()
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "Missing presentation texture"):
            import_presentation(self.chapter, source)
        self.assertEqual(self.snapshot(), before)

    def test_profile_custom_parameters_follow_semantic_fields_after_native_filename_changes(self):
        first = self.native("first")
        (first / "sprite.png.import").write_text(
            '[remap]\nimporter="texture"\n[params]\ncompress/mode=1\n'
        )
        report = import_presentation(self.chapter, first)
        second = self.native("second", identity=9)
        (second / "renamed.png").write_bytes(b"same")
        for name in (
            "units.json",
            "map_animations.json",
            "ui/manifest.json",
            "battle/manifest.json",
        ):
            path = second / name
            path.write_text(path.read_text().replace("sprite.png", "renamed.png"))
        before = self.snapshot()
        repeated = import_presentation(self.chapter, second)
        self.assertEqual(report["recipes"], repeated["recipes"])
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
