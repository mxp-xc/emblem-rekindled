"""m12 offline source and map publication contracts."""

import json
import unittest
from pathlib import Path

import test_chapter_configuration as configuration_fixture
from emblem_dev.content.assets import texture_sources
from emblem_dev.content.configuration import publish_map
from emblem_dev.content.definitions import read_deployment
from texture_fixture import png


class M12ImportTest(unittest.TestCase):
    def test_map_publishes_opened_texture_under_shared_ownership_and_reimports(self):
        fixture = configuration_fixture.ChapterConfigurationTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        native_map = {
            "width": 2,
            "height": 2,
            "tileVariants": {
                "opened_chest": {
                    "tileId": 88,
                    "terrain": 1,
                    "texture": "map_tiles/opened_chest.png",
                    "movementCosts": {str(group): 1 for group in range(11)},
                }
            },
            "locationTileVariants": {"chest_0": "opened_chest"},
        }
        fixture.write(fixture.source / "map.json", native_map)
        tile = fixture.source / "map_tiles/opened_chest.png"
        tile.parent.mkdir()
        tile.write_bytes(png(b"native-tile-88"))
        fixture.deployment["locations"] = [{"id": "chest_0", "position": [1, 1]}]
        publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)
        target = fixture.chapter / "generated/battles/m2"
        result = json.loads((target / "map.json").read_text())
        self.assertEqual(
            result["locations"],
            [{"id": "chest_0", "position": [1, 1], "openedVariant": "opened_chest"}],
        )
        self.assertNotIn("locationTileVariants", result)
        texture = result["tileVariants"]["opened_chest"]["texture"]
        self.assertTrue(texture.startswith("res://content/chapter_1/generated/shared/"))
        self.assertEqual((fixture.root / "game" / texture[6:]).read_bytes(), png(b"native-tile-88"))
        provenance = json.loads((target / "provenance.json").read_text())
        self.assertIn("map_tiles/opened_chest.png", texture_sources(provenance))
        before = fixture.snapshot()
        publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)
        self.assertEqual(fixture.snapshot(), before)

    def test_original_m12_keeps_ordered_deployment_and_weighted_locations(self):
        root = Path(__file__).resolve().parents[2]
        deployment = read_deployment(root / "reference/original-jars/chapter-1.jar", 12)
        self.assertEqual(len(deployment["units"]), 41)
        self.assertEqual(
            [row["sourceId"] for row in deployment["units"]],
            [
                4,
                0,
                6,
                5,
                1,
                2,
                3,
                7,
                89,
                11,
                13,
                10,
                12,
                15,
                16,
                41,
                40,
                43,
                42,
                37,
                36,
                34,
                35,
                39,
                38,
                68,
                67,
                66,
                65,
                64,
                63,
                62,
                61,
                60,
                59,
                58,
                57,
                30,
                33,
                31,
                32,
            ],
        )
        self.assertEqual(
            [index for index, row in enumerate(deployment["units"]) if row["randomEquipment"]],
            [0, 3, 5, 6, 26, 27, 28, 29, 30, 31, 32, 35, 36, 37, 38, 40],
        )
        self.assertEqual(
            [row["deploymentSlot"] for row in deployment["units"] if "deploymentSlot" in row],
            [4, 0, 6, 5, 1, 2, 3, 7],
        )
        self.assertEqual(sum(bool(row["flags"] & 1) for row in deployment["units"]), 16)
        self.assertEqual((deployment["width"], deployment["height"]), (24, 27))
        self.assertEqual(
            deployment["locations"],
            [
                {
                    "id": "chest_0",
                    "sourceIndex": 0,
                    "kind": "chest",
                    "position": [1, 1],
                    "tileId": 79,
                    "weightedChoices": [
                        {"templateId": 39, "weight": 30},
                        {"templateId": 33, "weight": 70},
                    ],
                },
                {
                    "id": "chest_1",
                    "sourceIndex": 1,
                    "kind": "chest",
                    "position": [8, 20],
                    "tileId": 79,
                    "weightedChoices": [
                        {"templateId": 2, "weight": 70},
                        {"templateId": 10, "weight": 30},
                    ],
                },
                {
                    "id": "chest_2",
                    "sourceIndex": 2,
                    "kind": "chest",
                    "position": [15, 20],
                    "tileId": 79,
                    "weightedChoices": [
                        {"templateId": 15, "weight": 70},
                        {"templateId": 19, "weight": 30},
                    ],
                },
                {
                    "id": "chest_3",
                    "sourceIndex": 3,
                    "kind": "chest",
                    "position": [22, 1],
                    "tileId": 79,
                    "weightedChoices": [
                        {"templateId": 25, "weight": 70},
                        {"templateId": 27, "weight": 30},
                    ],
                },
            ],
        )
