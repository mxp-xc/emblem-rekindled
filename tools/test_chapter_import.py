"""Reimport keeps static deployment contracts and inherited texture locations."""

import unittest

from chapter_1_definitions import deployment_records
from import_chapter_1 import sample_spawns, variant_requests


class ChapterImportTest(unittest.TestCase):
    def test_native_sampling_uses_actual_party_identity_and_keeps_slot_recipe(self):
        records = [
            {"sourceId": 1, "classId": 0, "faction": 0, "policy": 32, "deploymentSlot": 1},
            {"sourceId": 82, "classId": 12, "faction": 2, "policy": 2},
        ]
        units = [
            {"id": 9, "sourceId": 9, "classId": 4, "faction": 0, "formal": True, "nativePolicy": 1},
            {"id": 82, "sourceId": 82, "classId": 12, "faction": 2, "formal": False},
        ]
        sample = sample_spawns(records, units)
        self.assertEqual(sample[0]["id"], 9)
        self.assertEqual(sample[0]["sourceId"], 9)
        self.assertEqual(sample[0]["deploymentSlot"], 1)
        with self.assertRaisesRegex(ValueError, "count or identities"):
            sample_spawns(records, units[:1])
        self.assertEqual(sample_spawns(records, list(reversed(units))), sample)
        invalid = [dict(unit) for unit in units]
        invalid[0]["nativePolicy"] = 2
        with self.assertRaisesRegex(ValueError, "identity/class/slot"):
            sample_spawns(records, invalid)

    def test_variant_request_covers_transferable_allied_weapons_and_enemy_choices(self):
        request = variant_requests(
            [
                {"sourceId": 0, "faction": 0, "itemChoices": [1, 0, 0], "dropTemplateId": 0},
                {"sourceId": 82, "faction": 2, "itemChoices": [1, 2, 0], "dropTemplateId": 53},
            ]
        )
        self.assertEqual(request.splitlines()[0], "allies\t" + ",".join(map(str, range(52))))
        self.assertEqual(request.splitlines()[1], "82\t0,1,2")

    def test_distinct_actual_ids_preserve_duplicate_source_recipes_and_sampling_index(self):
        records = [
            {
                "sourceId": 46,
                "classId": 8,
                "faction": 2,
                "policy": 0,
                "itemChoices": [25],
                "dropTemplateId": 25,
            },
            {
                "sourceId": 46,
                "id": 70,
                "classId": 24,
                "faction": 2,
                "policy": 2,
                "itemChoices": [1, 42],
                "dropTemplateId": 0,
            },
        ]
        units = [
            {
                "id": 70,
                "sourceId": 46,
                "classId": 24,
                "faction": 2,
                "formal": False,
                "deploymentIndex": 1,
            },
            {"id": 46, "sourceId": 46, "classId": 8, "faction": 2, "formal": False},
        ]
        samples = sample_spawns(records, units)
        self.assertEqual([(u["id"], u["sourceId"]) for u in samples], [(46, 46), (70, 46)])
        self.assertEqual(variant_requests(records).splitlines()[1:], ["46\t0,25", "70\t0,1,42"])
        for key, invalid in (("sourceId", 70), ("deploymentIndex", 0)):
            stale = [dict(u) for u in units]
            stale[0][key] = invalid
            with self.assertRaisesRegex(ValueError, "identity/class/slot"):
                sample_spawns(records, stale)

    def test_raw_deployments_keep_slots_without_assigning_runtime_identities(self):
        def deployment(battle):
            records = []
            for source_id in range(27) if battle == 0 else range(10, 36):
                records += [1, 0, source_id, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1]
            for slot in range(1, 6) if battle == 0 else range(6):
                records += [1, 0, slot, 1, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 1, 1]
            return bytes([32, *records])

        first = deployment_records(deployment(0), 20, 25)
        second = deployment_records(deployment(1), 22, 22)
        self.assertEqual(
            [spawn["deploymentSlot"] for spawn in first if "deploymentSlot" in spawn],
            [1, 2, 3, 4, 5],
        )
        self.assertEqual(
            [spawn["deploymentSlot"] for spawn in second if "deploymentSlot" in spawn],
            list(range(6)),
        )
        self.assertTrue(
            all("id" not in spawn and "formal" not in spawn for spawn in first + second)
        )

    def third_deployment(self, regions=None):
        records = []
        for slot in range(7):
            records += [1, 0, slot, 1, 0, 0, 1, 32, 0, 0, 0, 0, 0, 0, slot + 1, 1]
        records += [1, 12, 7, 1, 0, 0, 0, 0, 0, 40, 42, 0, 0, 0, 17, 9]
        for source_id in range(10, 40):
            records += [1, 0, source_id, 1, 2, 0, 0, 0, 0, 1, 0, 0, 0]
            if source_id == 39:
                rectangles = regions if regions is not None else [[2, 2, 4, 5], [4, 5, 5, 6]]
                records += [len(rectangles)]
                records += [value for rectangle in rectangles for value in rectangle]
            else:
                records += [0, source_id % 20, 10]
        return bytes([38, *records])

    def test_m2_keeps_ordered_slots_and_all_random_regions_unresolved(self):
        first = deployment_records(self.third_deployment(), 22, 26)
        self.assertEqual([spawn["deploymentSlot"] for spawn in first[:7]], list(range(7)))
        self.assertEqual(first[-1]["deploymentRegions"], [[2, 2, 4, 5], [4, 5, 5, 6]])
        self.assertNotIn("position", first[-1])
        self.assertNotIn("id", first[-1])

    def test_source_protocol_accepts_real_later_enemy_ids_and_monster_classes(self):
        data = bytes([1, 1, 28, 115, 1, 2, 0, 1, 4, 0, 1, 0, 0, 0, 0, 3, 4])
        rows = deployment_records(data, 4, 5)
        self.assertEqual(rows[0]["sourceId"], 115)
        self.assertEqual(rows[0]["classId"], 28)
        self.assertEqual(rows[0]["position"], [3, 4])

    def test_raw_parser_rejects_invalid_regions_truncation_and_trailing_data(self):
        with self.assertRaisesRegex(ValueError, "region is outside"):
            deployment_records(self.third_deployment([[0, 0, 22, 25]]), 22, 26)
        with self.assertRaisesRegex(ValueError, "region is outside"):
            deployment_records(self.third_deployment([[5, 2, 4, 5]]), 22, 26)
        with self.assertRaisesRegex(ValueError, "Truncated"):
            deployment_records(self.third_deployment()[:-1], 22, 26)
        with self.assertRaisesRegex(ValueError, "Unexpected trailing"):
            deployment_records(self.third_deployment() + b"\x00", 22, 26)


if __name__ == "__main__":
    unittest.main()
