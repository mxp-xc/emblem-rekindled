"""Authored map abilities compile without changing source stats or hiding bad rules."""

import copy
import json
import tempfile
import unittest
from pathlib import Path

from emblem_dev.content.actions import compile_actions


class ChapterActionsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.chapter = Path(self.temporary.name) / "game/content/chapter_1"
        self.rules_path = self.chapter / "generated/rules.json"
        self.catalog_path = self.chapter / "generated/library/catalog.json"
        self.actions_path = self.chapter / "authored/item_actions.json"
        self.write(
            self.chapter / "chapter.json",
            {
                "rules": "res://content/chapter_1/generated/rules.json",
                "library": "res://content/chapter_1/generated/library/catalog.json",
            },
        )
        self.rules = {
            "initialGold": 5000,
            "itemTemplates": [
                {"id": 1, "damageKind": "physical", "power": 7},
                {"id": 52, "damageKind": "magic", "power": 12},
                {"id": 200, "damageKind": "magic", "power": 3},
                {"id": 54, "damageKind": "healing", "power": 10},
            ],
        }
        self.write(self.rules_path, self.rules)
        self.write(self.catalog_path, {"profiles": {}, "scenes": {}})
        self.actions = {
            "items": {
                "200": {
                    "actionMode": "map_attack",
                    "targetRule": {"selection": "none", "range": "map", "shape": "all_hostile"},
                    "roundRule": {"period": 3, "remainder": 0},
                    "mapEffect": "quake",
                }
            },
            "effects": {
                "quake": {
                    "kind": "shake",
                    "logicalTickUnits": 50,
                    "durationUnits": 500,
                    "shakeModuli": [10, 3],
                    "flashUpdates": 5,
                    "flashColor": 0,
                    "flashOnEven": True,
                }
            },
        }
        self.write(self.actions_path, self.actions)

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def snapshot(self):
        return self.rules_path.read_bytes(), self.catalog_path.read_bytes()

    def test_compilation_is_data_driven_and_keeps_source_item_values(self):
        result = compile_actions(self.chapter)
        rules = json.loads(self.rules_path.read_text())
        self.assertEqual(result, {"items": 1, "effects": 1})
        self.assertEqual(rules["initialGold"], 5000)
        self.assertEqual([item["id"] for item in rules["itemTemplates"]], [1, 52, 200, 54])
        for item, original in zip(rules["itemTemplates"], self.rules["itemTemplates"], strict=True):
            self.assertTrue(original.items() <= item.items())
        self.assertEqual(rules["itemTemplates"][0]["actionMode"], "battle_clip")
        self.assertEqual(rules["itemTemplates"][1]["actionMode"], "battle_clip")
        self.assertEqual(rules["itemTemplates"][2]["actionMode"], "map_attack")
        self.assertNotIn("actionMode", rules["itemTemplates"][3])
        before = self.snapshot()
        compile_actions(self.chapter)
        self.assertEqual(self.snapshot(), before)

    def test_missing_effect_or_invalid_round_rule_never_modifies_outputs(self):
        before = self.snapshot()
        invalid = copy.deepcopy(self.actions)
        invalid["items"]["200"]["mapEffect"] = "missing"
        self.write(self.actions_path, invalid)
        with self.assertRaisesRegex(ValueError, "missing effect"):
            compile_actions(self.chapter)
        self.assertEqual(self.snapshot(), before)
        invalid = copy.deepcopy(self.actions)
        invalid["items"]["200"]["roundRule"]["period"] = 0
        self.write(self.actions_path, invalid)
        with self.assertRaisesRegex(ValueError, "round rule"):
            compile_actions(self.chapter)
        self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
