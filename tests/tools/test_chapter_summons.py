"""Native summon families are explicit resources included in every map's motion closure."""

import json
import unittest

import test_chapter_library as fixtures
from emblem_dev.content.configuration import motion_requirements
from emblem_dev.content.library import import_presentation


class ChapterSummonsTest(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.ChapterLibraryTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.chapter = self.fixture.chapter

    def native_summon(self, name, identity=20, faction=1, class_id=28):
        source = self.fixture.native(name, identity=identity, weapon=29)
        path = source / "units.json"
        unit = json.loads(path.read_text())[0]
        unit.update(
            sourceId=identity,
            faction=faction,
            classId=class_id,
            classGroup=class_id // 4,
            formal=False,
        )
        self.fixture.write(path, [unit])
        self.fixture.write(
            source / "spawns.json",
            [
                {
                    "id": identity,
                    "sourceId": identity,
                    "formal": False,
                    "faction": faction,
                    "policy": 0,
                    "summoned": True,
                }
            ],
        )
        return source

    def test_native_family_registers_each_real_identity_and_constructor_templates(self):
        first = import_presentation(self.chapter, self.native_summon("one"))
        second = import_presentation(self.chapter, self.native_summon("two", identity=29))
        catalog = json.loads((self.chapter / "generated/library/catalog.json").read_text())
        directory = catalog["summons"]["1"]["28"]
        self.assertEqual(directory, {"20": first["bindings"]["20"], "29": second["bindings"]["29"]})
        self.assertEqual(directory["20"], directory["29"])
        prototype = catalog["profiles"][directory["20"]]["unit"]
        self.assertEqual(
            (
                prototype["baseTemplateId"],
                prototype["initialGrowthTemplateId"],
                prototype["growthTemplateId"],
            ),
            (38, 17, 17),
        )
        before = self.fixture.snapshot()
        import_presentation(self.chapter, self.fixture.root / "one")
        self.assertEqual(self.fixture.snapshot(), before)

    def test_invalid_native_summon_cannot_publish_resources(self):
        source = self.native_summon("bad", identity=19)
        before = self.fixture.snapshot()
        with self.assertRaisesRegex(ValueError, "summon family"):
            import_presentation(self.chapter, source)
        self.assertEqual(self.fixture.snapshot(), before)

    def test_old_map_requires_opposite_side_summon_motion(self):
        first = import_presentation(self.chapter, self.native_summon("one"))
        enemy = self.fixture.native("enemy", identity=87, weapon=48)
        art_path = enemy / "battle/manifest.json"
        art = json.loads(art_path.read_text())
        art["appearances"]["87:48"]["nativeSide"] = "right"
        self.fixture.write(art_path, art)
        second = import_presentation(self.chapter, enemy)
        self.fixture.write(
            self.chapter / "chapter.json",
            {
                "library": "res://content/chapter_1/generated/library/catalog.json",
                "battles": {"m0": "res://content/chapter_1/map.json"},
            },
        )
        self.fixture.write(
            self.chapter / "map.json",
            {"stage": first["stage"], "profiles": {"boss": second["bindings"]["87"]}},
        )
        coverage = motion_requirements(self.chapter)
        self.assertEqual(coverage["maps"]["m0"]["requiredClips"], 6)
        self.assertIn("sword/human/1/miss", coverage["missing"][first["stage"]])


if __name__ == "__main__":
    unittest.main()
