"""Original Sofia Mountains location records."""

import unittest
from pathlib import Path

from emblem_dev.content.definitions import read_deployment


class M1LocationsTest(unittest.TestCase):
    def test_original_visits_and_chests(self):
        root = Path(__file__).resolve().parents[2]
        locations = read_deployment(root / "reference/original-jars/chapter-1.jar", 1)["locations"]
        self.assertEqual(
            [(row["kind"], row["position"]) for row in locations],
            [
                ("visit", [11, 7]),
                ("visit", [13, 5]),
                ("visit", [13, 6]),
                ("chest", [16, 5]),
                ("chest", [21, 16]),
            ],
        )
        self.assertEqual(
            [
                [(item["templateId"], item["weight"]) for item in row["weightedChoices"]]
                for row in locations[3:]
            ],
            [[(63, 20), (61, 20), (34, 20), (60, 40)], [(76, 5), (60, 80), (2, 15)]],
        )
