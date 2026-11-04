"""Map publication preserves authored content and validates bindings before mutation."""

import copy
import json
import tempfile
import unittest
from pathlib import Path

import test_chapter_library as library_fixture
from emblem_dev.content.configuration import (
    generated_critical,
    generated_noncritical,
    import_map,
    motion_requirements,
    normalize_deployment,
    publish_map,
)
from texture_fixture import png


class ChapterConfigurationTest(unittest.TestCase):
    def test_generated_critical_requires_supported_thrown_weapon_and_projectile(self):
        thrown = {"R": 2, "effectKind": 0, "thrown": True}
        projectile = {"projectile": {"texture": "axe.png"}}
        self.assertTrue(generated_critical(thrown, projectile))
        self.assertFalse(generated_critical(thrown, {}))
        self.assertTrue(generated_critical({**thrown, "thrown": False}, projectile))
        self.assertTrue(generated_critical({**thrown, "R": 0, "thrown": False}, projectile))
        self.assertFalse(generated_critical({**thrown, "R": 5}, projectile))
        self.assertTrue(generated_critical({**thrown, "R": 5, "thrown": False}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 3}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 4}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 5}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 6}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 8}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 7}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 11}, projectile))
        self.assertTrue(generated_critical({**thrown, "effectKind": 12}, projectile))
        self.assertFalse(generated_critical({**thrown, "effectKind": 3}, {}))

    def test_generated_noncritical_requires_projectile_for_thrown_weapon(self):
        regular = {"R": 2, "effectKind": 0, "thrown": False}
        thrown = {**regular, "thrown": True}
        self.assertTrue(generated_noncritical(regular, {}))
        self.assertFalse(generated_noncritical(thrown, {}))
        self.assertTrue(generated_noncritical(thrown, {"projectile": {"texture": "axe.png"}}))
        self.assertTrue(generated_noncritical({"R": 3, "effectKind": 4}, {}))
        self.assertTrue(generated_noncritical({"R": 3, "effectKind": 7}, {}))
        self.assertTrue(generated_noncritical({"R": 3, "effectKind": 5}, {}))
        self.assertTrue(generated_noncritical({"R": 3, "effectKind": 6}, {}))
        self.assertTrue(generated_noncritical({"R": 3, "effectKind": 11}, {}))
        self.assertTrue(generated_noncritical({"R": 3, "effectKind": 12}, {}))
        self.assertTrue(generated_noncritical({"R": 7, "effectKind": 0}, {}))
        self.assertFalse(
            generated_noncritical(
                {"R": 7, "effectKind": 0, "thrown": True},
                {"projectile": {"texture": "axe.png"}},
            )
        )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.chapter = self.root / "game/content/chapter_1"
        self.write(self.chapter / "chapter.json", {"id": "chapter_1", "battles": {}})
        self.write(
            self.chapter / "generated/shared/provenance.json",
            {"outputs": [], "textureImportParameters": {}},
        )
        self.story = self.chapter / "authored/battles/m2.json"
        self.write(
            self.story,
            {
                "deploymentAdjustments": [{"sourceId": 5, "position": [1, 1]}],
                "deploymentRevealFactions": [2],
            },
        )
        self.source = self.root / "native"
        self.write(self.source / "map.json", {"width": 2, "height": 2})
        (self.source / "map.png").write_bytes(png(b"map"))
        self.write(self.source / "provenance.json", {"source": "native"})
        self.deployment = {
            "battleId": "m2",
            "width": 2,
            "height": 2,
            "units": [
                {
                    "kind": 1,
                    "sourceId": 5,
                    "classId": 0,
                    "faction": 2,
                    "flags": 1,
                    "position": [0, 0],
                }
            ],
        }
        self.presentation = {
            "stage": "stage_0",
            "scene": "scene_0",
            "recipes": {"source_5_job_0_faction_2": "source_5_job_0_faction_2"},
        }

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def snapshot(self):
        return {
            path.relative_to(self.chapter): path.read_bytes()
            for path in self.chapter.rglob("*")
            if path.is_file()
        }

    def test_map_keeps_unresolved_deployment_and_explicit_normalization(self):
        original_story = self.story.read_bytes()
        publish_map(self.chapter, self.source, self.deployment, self.presentation)
        target = self.chapter / "generated/battles/m2"
        records = json.loads((target / "deployments.json").read_text())
        self.assertEqual(records[0]["position"], [1, 1])
        self.assertEqual(records[0]["flags"], 0)
        self.assertNotIn("id", records[0])
        self.assertEqual(self.deployment["units"][0]["position"], [0, 0])
        self.assertEqual(self.story.read_bytes(), original_story)
        before = self.snapshot()
        publish_map(self.chapter, self.source, self.deployment, self.presentation)
        self.assertEqual(self.snapshot(), before)

    def test_invalid_map_or_conflicting_recipe_cannot_modify_chapter(self):
        publish_map(self.chapter, self.source, self.deployment, self.presentation)
        before = self.snapshot()
        conflict = copy.deepcopy(self.presentation)
        conflict["recipes"]["source_5_job_0_faction_2"] = "different"
        with self.assertRaisesRegex(ValueError, "Conflicting map profile"):
            publish_map(self.chapter, self.source, self.deployment, conflict)
        invalid = {**self.deployment, "width": 3}
        with self.assertRaisesRegex(ValueError, "dimensions disagree"):
            publish_map(self.chapter, self.source, invalid, self.presentation)
        self.assertEqual(self.snapshot(), before)

    def test_index_adjustment_preserves_sources_order_and_rejects_ambiguous_identities(self):
        raw = {
            **self.deployment,
            "units": [
                {"sourceId": 46, "classId": 8, "faction": 2, "position": [0, 0]},
                {"sourceId": 46, "classId": 24, "faction": 2, "level": 5, "position": [1, 1]},
            ],
        }
        untouched = copy.deepcopy(raw)
        self.write(self.story, {"deploymentAdjustments": [{"deploymentIndex": 1, "id": 70}]})
        normalized = normalize_deployment(self.chapter, raw)
        self.assertEqual(raw, untouched)
        self.assertEqual(normalized["units"], [raw["units"][0], {**raw["units"][1], "id": 70}])
        for change in (
            {"deploymentIndex": 2, "id": 70},
            {"deploymentIndex": True, "id": 70},
            {"sourceId": 46, "id": 70},
            {"deploymentIndex": 1, "id": 46},
            {"deploymentIndex": 1, "id": True},
            {"deploymentIndex": 1, "sourceId": 46, "id": 70},
            {"deploymentIndex": 1, "classId": 8},
        ):
            self.write(self.story, {"deploymentAdjustments": [change]})
            with self.assertRaises(ValueError):
                normalize_deployment(self.chapter, raw)

    def test_complete_import_validates_before_publishing_library_and_registers_map(self):
        fixture = library_fixture.ChapterLibraryTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        native = fixture.native("source")
        self.write(native / "map.json", {"width": 2, "height": 2})
        (native / "map.png").write_bytes(png(b"map"))
        self.write(native / "provenance.json", {"source": "native"})
        self.write(
            fixture.chapter / "chapter.json",
            {
                "id": "chapter_1",
                "battles": {},
                "library": "res://content/chapter_1/generated/library/catalog.json",
            },
        )
        before = {
            p.relative_to(fixture.chapter): p.read_bytes()
            for p in fixture.chapter.rglob("*")
            if p.is_file()
        }
        with self.assertRaisesRegex(ValueError, "Missing authored"):
            import_map(fixture.chapter, native, self.deployment)
        self.assertEqual(
            {
                p.relative_to(fixture.chapter): p.read_bytes()
                for p in fixture.chapter.rglob("*")
                if p.is_file()
            },
            before,
        )
        self.write(fixture.chapter / "authored/battles/m2.json", {})
        result = import_map(fixture.chapter, native, self.deployment)
        self.assertEqual(result["map"]["battleId"], "m2")
        entry = json.loads((fixture.chapter / "chapter.json").read_text())
        self.assertEqual(
            entry["battles"]["m2"], "res://content/chapter_1/generated/battles/m2/battle.json"
        )
        map_path = fixture.chapter / "generated/battles/m2/map.json"
        formatted = json.dumps(json.loads(map_path.read_text()), indent=4) + "\n"
        map_path.write_text(formatted)
        repeat = import_map(fixture.chapter, native, self.deployment)
        self.assertEqual(repeat["filesWritten"], 0)
        self.assertEqual(repeat["filesRemoved"], 0)
        self.assertEqual(map_path.read_text(), formatted)

    def test_new_map_weapon_extension_cannot_publish_missing_old_map_pairs(self):
        fixture = library_fixture.ChapterLibraryTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        chapter = fixture.chapter
        self.write(
            chapter / "chapter.json",
            {
                "id": "chapter_1",
                "battles": {},
                "library": "res://content/chapter_1/generated/library/catalog.json",
            },
        )
        self.write(chapter / "authored/battles/m2.json", {})
        first = fixture.native("first")
        for source in (first,):
            self.write(source / "map.json", {"width": 2, "height": 2})
            (source / "map.png").write_bytes(png(b"map"))
            self.write(source / "provenance.json", {"source": "native"})
        import_map(chapter, first, self.deployment)
        catalog = chapter / "generated/library/catalog.json"
        bank = json.loads(catalog.read_text())
        profile_id = next(iter(bank["profiles"]))
        enemy = copy.deepcopy(bank["profiles"][profile_id])
        enemy["unit"]["faction"] = 2
        appearance = copy.deepcopy(bank["appearancePool"][enemy["appearances"]["1"]])
        appearance["nativeSide"] = "right"
        bank["appearancePool"]["enemy_weapon_1"] = appearance
        enemy["appearances"]["1"] = "enemy_weapon_1"
        enemy["motion"]["stage_0"]["1"].update(canAttack=False, actionGroup=None)
        bank["profiles"]["enemy"] = enemy
        stage = bank["stages"]["stage_0"]
        library = catalog.parent
        provenance_path = library / "provenance.json"
        provenance = json.loads(provenance_path.read_text())
        for slot in range(2):
            for outcome in ("hit", "miss", "critical"):
                key = f"sword/human/{slot}/{outcome}"
                relative = f"baseline/{slot}-{outcome}.json"
                self.write(
                    library / relative, {"sourceSlot": slot, "outcome": outcome, "ticks": []}
                )
                stage["clips"][key] = "res://content/chapter_1/generated/library/" + relative
                provenance["outputs"].append(relative)
        self.write(provenance_path, provenance)
        self.write(catalog, bank)
        map_path = chapter / "generated/battles/m2/battle.json"
        definition = json.loads(map_path.read_text())
        definition["profiles"]["enemy"] = "enemy"
        self.write(map_path, definition)
        self.assertFalse(motion_requirements(chapter)["missing"])

        extension = fixture.native("extension", weapon=2)
        self.write(extension / "map.json", {"width": 2, "height": 2})
        (extension / "map.png").write_bytes(png(b"map"))
        self.write(extension / "provenance.json", {"source": "native"})
        motion_path = extension / "battle/clips/manifest.json"
        motion = json.loads(motion_path.read_text())
        motion["actionGroups"]["shot"] = motion["actionGroups"].pop("sword")
        motion["appearances"]["0:2"]["actionGroup"] = "shot"
        motion["clips"] = {"shot/human/0/hit": "hit.json"}
        self.write(motion_path, motion)
        self.write(chapter / "authored/battles/m3.json", {})
        before = {p.relative_to(chapter): p.read_bytes() for p in chapter.rglob("*") if p.is_file()}
        with self.assertRaisesRegex(ValueError, "Missing chapter motion combinations.*m2"):
            import_map(chapter, extension, {**self.deployment, "battleId": "m3"})
        self.assertEqual(
            {p.relative_to(chapter): p.read_bytes() for p in chapter.rglob("*") if p.is_file()},
            before,
        )


if __name__ == "__main__":
    unittest.main()
