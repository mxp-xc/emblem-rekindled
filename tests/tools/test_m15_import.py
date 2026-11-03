"""m15 mixed source locations and deployment contracts."""

import json
import unittest
from pathlib import Path

from emblem_dev.content.definitions import map_locations, read_deployment


class M15ImportTest(unittest.TestCase):
    def test_authored_opening_and_rounds_match_observed_events(self):
        root = Path(__file__).resolve().parents[2]
        story = json.loads((root / "game/content/chapter_1/authored/battles/m15.json").read_text())
        opening = story["sequences"]["opening"]
        self.assertEqual(
            [s["text"]["sourceTextIndex"] for s in opening if s["kind"] == "dialogue"],
            [619, 621, 622, 623, 624, 620],
        )
        entrance = next(s for s in opening if s["kind"] == "unitEntrance")
        self.assertEqual(
            (entrance["unitId"], entrance["from"], entrance["to"]), (59, [10, 18], [10, 17])
        )
        self.assertEqual(story["deploymentRevealUnitIds"], list(range(45, 53)))
        self.assertEqual(story["speakers"]["91"]["name"], "吉克")
        events = {e["afterEnemyPhaseOfRound"]: e for e in story["turnEvents"]}
        self.assertEqual(events[3]["withdrawUnitId"], 91)
        self.assertEqual(events[4]["unitIds"], [20, 22, 23, 24, 15, 16])
        self.assertEqual(events[5]["unitIds"], [56, 57, 58, 86, 10, 11, 12, 13, 14])
        self.assertEqual(events[10]["unitIds"], [89])
        self.assertEqual(story["outcomeRules"]["checks"][1]["unitIds"], [83, 89])

    def test_source_mixed_locations(self):
        root = Path(__file__).resolve().parents[2]
        result = read_deployment(root / "reference/original-jars/chapter-1.jar", 15)
        self.assertEqual((result["width"], result["height"], len(result["units"])), (25, 25, 63))
        locations = result["locations"]
        self.assertEqual([v["sourceIndex"] for v in locations], list(range(11)))
        self.assertEqual(
            [v["kind"] for v in locations],
            [
                "chest",
                "visit",
                "visit",
                "visit",
                "visit",
                "visit",
                "visit",
                "visit",
                "visit",
                "chest",
                "waitPickup",
            ],
        )
        self.assertEqual(locations[0]["reward"], {"kind": "item", "templateId": 9})
        self.assertEqual(locations[9]["reward"], {"kind": "item", "templateId": 18})
        self.assertNotIn("weightedChoices", locations[0])
        self.assertNotIn("weightedChoices", locations[9])
        self.assertEqual(locations[3]["reward"], {"kind": "gold", "amount": 1000})
        self.assertEqual(locations[8]["reward"], {"kind": "gold", "amount": 500})
        self.assertEqual(
            locations[4]["reward"], {"kind": "goldRange", "minimum": 1, "maximum": 500}
        )
        self.assertEqual(
            locations[10]["reward"],
            {
                "kind": "weightedItem",
                "weightedChoices": [
                    {"templateId": 72, "weight": 20},
                    {"templateId": 73, "weight": 20},
                ],
            },
        )

    def test_rejects_mixed_location_wrong_terrain_or_payload(self):
        # 1x1 map: tile, one tail record and its payload.
        for data in (
            bytes([1, 1, 79, 1, 3, 0, 0, 1, 72, 20]),
            bytes([1, 1, 39, 1, 2, 0, 0, 0, 0, 0, 1]),
            bytes([1, 1, 59, 1, 2, 0, 0, 0, 0, 0]),
            bytes([1, 1, 39, 1, 3, 0, 0, 2, 72, 60, 73, 50]),
        ):
            with self.subTest(data=list(data)), self.assertRaises(ValueError):
                map_locations(data, 15)


if __name__ == "__main__":
    unittest.main()
