"""m14 source deployment and fixed wait-pickup contracts."""

import json
import unittest
from pathlib import Path

import test_chapter_configuration as configuration_fixture
from emblem_dev.content.chapter1 import sample_spawns
from emblem_dev.content.configuration import publish_map
from emblem_dev.content.definitions import map_locations, read_deployment


class M14ImportTest(unittest.TestCase):
    def test_source_deployment_and_locations(self):
        root = Path(__file__).resolve().parents[2]
        result = read_deployment(root / "reference/original-jars/chapter-1.jar", 14)
        self.assertEqual((result["width"], result["height"], len(result["units"])), (24, 22, 43))
        self.assertEqual(
            [u["deploymentSlot"] for u in result["units"] if "deploymentSlot" in u],
            [6, 4, 7, 5, 3, 2, 0, 1],
        )
        self.assertEqual([u["sourceId"] for u in result["units"] if u["flags"] & 1], [112])
        self.assertEqual(
            [u["sourceId"] for u in result["units"] if "deploymentRegions" in u],
            [110, 108, 114, 113, 107, 109, 111, 112],
        )
        self.assertEqual(
            [(v["position"], v["reward"]["templateId"]) for v in result["locations"]],
            [
                ([3, 1], 26),
                ([5, 11], 18),
                ([8, 9], 62),
                ([17, 10], 9),
                ([22, 2], 37),
                ([22, 15], 59),
            ],
        )
        self.assertTrue(
            all(
                v["kind"] == "waitPickup" and v["id"] == f"wait_{i}"
                for i, v in enumerate(result["locations"])
            )
        )

    def test_invalid_wait_pickup_tail(self):
        valid = bytes([1, 1, 39, 1, 1, 0, 0, 26])
        self.assertEqual(map_locations(valid, 14)[0]["reward"], {"kind": "item", "templateId": 26})
        for data in (
            valid[:-1],
            valid + b"\0",
            bytes([1, 1, 58, 1, 1, 0, 0, 26]),
            bytes([1, 1, 39, 1, 3, 0, 0, 1, 26, 1]),
            bytes([1, 1, 39, 1, 1, 0, 0, 0]),
            bytes([1, 1, 39, 2, 1, 0, 0, 26, 1, 0, 0, 18]),
        ):
            with self.subTest(data=list(data)), self.assertRaises(ValueError):
                map_locations(data, 14)

    def test_publish_wait_pickup_keeps_tile_and_rejects_wrong_terrain(self):
        fixture = configuration_fixture.ChapterConfigurationTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        location = {
            "id": "wait_0",
            "sourceIndex": 0,
            "kind": "waitPickup",
            "position": [1, 1],
            "tileId": 39,
            "reward": {"kind": "item", "templateId": 26},
        }
        fixture.write(
            fixture.source / "map.json",
            {"width": 2, "height": 2, "tiles": [[0, 0], [0, 39]], "terrain": [[0, 0], [0, 3]]},
        )
        fixture.deployment["locations"] = [location]
        publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)
        result = json.loads((fixture.chapter / "generated/battles/m2/map.json").read_text())
        self.assertEqual(result["locations"], [location])
        self.assertEqual(result["tiles"][1][1], 39)
        self.assertNotIn("tileVariants", result)
        before = fixture.snapshot()
        publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)
        self.assertEqual(fixture.snapshot(), before)
        fixture.write(
            fixture.source / "map.json",
            {"width": 2, "height": 2, "tiles": [[0, 0], [0, 39]], "terrain": [[0, 0], [0, 6]]},
        )
        with self.assertRaises(ValueError):
            publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)

    def test_binding_preserves_original_indices_after_summon_replacement(self):
        records = [
            {"sourceId": 22, "classId": 33, "faction": 2},
            {"sourceId": 34, "classId": 29, "faction": 2},
        ]
        units = [
            {
                "id": 34,
                "sourceId": 34,
                "classId": 29,
                "faction": 2,
                "formal": False,
                "deploymentIndex": 1,
            }
        ]
        result = sample_spawns(records[1:], units, deployment_indices=[1])
        self.assertEqual(result[0]["id"], 34)
        with self.assertRaises(ValueError):
            sample_spawns(records[1:], units, deployment_indices=[0])

    def test_authored_first_combat_uses_element_portrait(self):
        root = Path(__file__).resolve().parents[2]
        story = json.loads((root / "game/content/chapter_1/authored/battles/m14.json").read_text())
        self.assertEqual(story["speakers"]["92"]["portraitId"], 23)
        self.assertEqual(
            story["sequences"]["element_first_combat"][0]["text"],
            {"sourceTextIndex": 640, "speakerId": 92},
        )
