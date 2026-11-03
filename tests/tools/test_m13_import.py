"""m13 offline source and map publication contracts."""

import json
import unittest
from pathlib import Path

import test_chapter_configuration as configuration_fixture
from emblem_dev.content.configuration import publish_map
from emblem_dev.content.definitions import map_locations, read_deployment


class M13ImportTest(unittest.TestCase):
    def test_original_m13_keeps_ordered_deployment_and_visit_rewards(self):
        root = Path(__file__).resolve().parents[2]
        result = read_deployment(root / "reference/original-jars/chapter-1.jar", 13)
        self.assertEqual((result["width"], result["height"]), (25, 20))
        self.assertEqual(len(result["units"]), 53)
        self.assertEqual(
            [row["deploymentSlot"] for row in result["units"] if "deploymentSlot" in row],
            [7, 1, 6, 5, 4, 3, 0, 2],
        )
        self.assertEqual(
            [row["sourceId"] for row in result["units"] if row["flags"] & 1],
            [81, 83, 57, 86, 45, 44, 46, 47, 53, 52, 91, 59, 48],
        )
        self.assertEqual(
            next(row for row in result["units"] if row["sourceId"] == 48)["deploymentRegions"],
            [[21, 1, 22, 3]],
        )
        self.assertEqual(
            result["locations"],
            [
                {
                    "id": "visit_0",
                    "sourceIndex": 0,
                    "kind": "visit",
                    "position": [7, 2],
                    "tileId": 58,
                    "reward": {
                        "kind": "weightedItem",
                        "weightedChoices": [
                            {"templateId": 57, "weight": 20},
                            {"templateId": 33, "weight": 70},
                        ],
                    },
                },
                {
                    "id": "visit_1",
                    "sourceIndex": 1,
                    "kind": "visit",
                    "position": [8, 15],
                    "tileId": 59,
                    "reward": {
                        "kind": "weightedItem",
                        "weightedChoices": [
                            {"templateId": 68, "weight": 10},
                            {"templateId": 69, "weight": 10},
                            {"templateId": 70, "weight": 10},
                            {"templateId": 71, "weight": 10},
                        ],
                    },
                },
                {
                    "id": "visit_2",
                    "sourceIndex": 2,
                    "kind": "visit",
                    "position": [9, 9],
                    "tileId": 58,
                    "reward": {"kind": "goldRange", "minimum": 1, "maximum": 500},
                },
                {
                    "id": "visit_3",
                    "sourceIndex": 3,
                    "kind": "visit",
                    "position": [10, 9],
                    "tileId": 58,
                    "reward": {"kind": "item", "templateId": 61},
                },
                {
                    "id": "visit_4",
                    "sourceIndex": 4,
                    "kind": "visit",
                    "position": [12, 0],
                    "tileId": 58,
                    "reward": {"kind": "item", "templateId": 53},
                },
                {
                    "id": "visit_5",
                    "sourceIndex": 5,
                    "kind": "visit",
                    "position": [13, 6],
                    "tileId": 58,
                    "reward": {"kind": "goldRange", "minimum": 1, "maximum": 500},
                },
                {
                    "id": "visit_6",
                    "sourceIndex": 6,
                    "kind": "visit",
                    "position": [14, 5],
                    "tileId": 58,
                    "reward": {"kind": "item", "templateId": 80},
                },
                {
                    "id": "visit_7",
                    "sourceIndex": 7,
                    "kind": "visit",
                    "position": [17, 6],
                    "tileId": 59,
                    "reward": {"kind": "goldRange", "minimum": 1, "maximum": 500},
                },
                {
                    "id": "visit_8",
                    "sourceIndex": 8,
                    "kind": "visit",
                    "position": [24, 6],
                    "tileId": 59,
                    "reward": {"kind": "goldRange", "minimum": 1, "maximum": 500},
                },
            ],
        )

    def test_visit_publishes_original_tile_without_opened_variant_and_reimports(self):
        fixture = configuration_fixture.ChapterConfigurationTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        location = {
            "id": "visit_0",
            "sourceIndex": 0,
            "kind": "visit",
            "position": [1, 1],
            "tileId": 58,
            "reward": {"kind": "goldRange", "minimum": 1, "maximum": 500},
        }
        fixture.write(
            fixture.source / "map.json",
            {"width": 2, "height": 2, "tiles": [[0, 0], [0, 58]], "terrain": [[0, 0], [0, 6]]},
        )
        fixture.deployment["locations"] = [location]
        publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)
        result = json.loads((fixture.chapter / "generated/battles/m2/map.json").read_text())
        self.assertEqual(result["locations"], [location])
        self.assertEqual(result["tiles"][1][1], 58)
        self.assertNotIn("tileVariants", result)
        before = fixture.snapshot()
        publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)
        self.assertEqual(fixture.snapshot(), before)

    def test_visit_tail_rejects_invalid_or_truncated_rewards_and_duplicate_cells(self):
        valid = bytes([1, 1, 58, 1, 1, 0, 0, 61])
        self.assertEqual(map_locations(valid, 13)[0]["reward"], {"kind": "item", "templateId": 61})
        for data in (
            valid[:-1],
            valid + b"\0",
            bytes([1, 1, 58, 1, 2, 0, 0]),
            bytes([1, 1, 58, 1, 1, 0, 0, 0]),
            bytes([1, 1, 58, 1, 3, 0, 0, 1, 57, 0]),
            bytes([1, 1, 58, 1, 3, 0, 0, 2, 57, 60, 33, 60]),
            bytes([1, 1, 58, 2, 1, 0, 0, 61, 1, 0, 0, 53]),
            bytes([1, 1, 79, 1, 1, 0, 0, 61]),
            bytes([1, 1, 58, 1, 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 1]),
        ):
            with self.subTest(data=list(data)), self.assertRaises(ValueError):
                map_locations(data, 13)

    def test_chest_keeps_total_weight_contract_while_visits_use_one_hundred(self):
        source = bytes([1, 1, 79, 1, 3, 0, 0, 2, 39, 60, 33, 60])
        self.assertEqual(
            map_locations(source, 12)[0]["weightedChoices"],
            [{"templateId": 39, "weight": 60}, {"templateId": 33, "weight": 60}],
        )
