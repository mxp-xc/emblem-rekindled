"""Verified m16 locations, including chests with an empty outcome."""

import json
import unittest
from pathlib import Path

import test_chapter_configuration as configuration_fixture
from emblem_dev.content.configuration import publish_map
from emblem_dev.content.definitions import map_locations, read_deployment


class M16ImportTest(unittest.TestCase):
    def test_authored_events_match_observed_boss_and_clone_rules(self):
        root = Path(__file__).resolve().parents[2]
        story = json.loads((root / "game/content/chapter_1/authored/battles/m16.json").read_text())
        self.assertEqual(
            [
                step["text"]["sourceTextIndex"]
                for step in story["sequences"]["opening"]
                if step["kind"] == "dialogue"
            ],
            [636, 637, 638],
        )
        boss = next(event for event in story["combatEvents"] if event["id"] == "boss_death")
        self.assertEqual((boss["unitId"], boss["revealUnitIds"]), (80, [92, 93, 94]))
        self.assertEqual(story["outcomeRules"]["checks"][1]["unitIds"], [80, 92])
        schedule = story["periodicClones"]["conditionalEvery"]
        self.assertEqual(schedule["period"], 2)
        self.assertEqual(
            [(group["whenUnitVisible"], group["templateUnitIds"]) for group in schedule["groups"]],
            [(34, [109]), (40, [108]), (89, [107]), (92, [110, 111])],
        )
        self.assertEqual(schedule["reservedUnitIds"], [112])

    def test_source_locations(self):
        root = Path(__file__).resolve().parents[2]
        result = read_deployment(root / "reference/original-jars/chapter-1.jar", 16)
        self.assertEqual((result["width"], result["height"], len(result["units"])), (30, 30, 54))
        locations = result["locations"]
        self.assertEqual(len(locations), 15)
        by_position = {tuple(location["position"]): location for location in locations}
        for position, items in (((4, 5), (9, 18, 60)), ((24, 5), (27, 37, 60))):
            chest = by_position[position]
            self.assertEqual(chest["kind"], "chest")
            self.assertEqual(
                chest["weightedChoices"], [{"templateId": item, "weight": 30} for item in items]
            )
            self.assertEqual(chest["emptyWeight"], 10)
        self.assertEqual(by_position[(1, 1)]["reward"]["templateId"], 74)
        self.assertEqual(by_position[(29, 4)]["reward"]["templateId"], 68)
        self.assertEqual(by_position[(29, 4)]["kind"], "waitPickup")

    def test_rejects_overweight_chest(self):
        data = bytes([1, 1, 79, 1, 3, 0, 0, 2, 9, 60, 18, 50])
        with self.assertRaises(ValueError):
            map_locations(data, 16)

    def test_publish_terrain_four_pickup(self):
        fixture = configuration_fixture.ChapterConfigurationTest()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        location = {
            "id": "wait_0",
            "sourceIndex": 0,
            "kind": "waitPickup",
            "position": [1, 1],
            "tileId": 49,
            "reward": {"kind": "item", "templateId": 68},
        }
        fixture.write(
            fixture.source / "map.json",
            {"width": 2, "height": 2, "tiles": [[0, 0], [0, 49]], "terrain": [[0, 0], [0, 4]]},
        )
        fixture.deployment["locations"] = [location]
        publish_map(fixture.chapter, fixture.source, fixture.deployment, fixture.presentation)
        result = json.loads((fixture.chapter / "generated/battles/m2/map.json").read_text())
        self.assertEqual(result["locations"], [location])


if __name__ == "__main__":
    unittest.main()
