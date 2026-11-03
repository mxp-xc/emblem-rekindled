"""Reimport keeps static deployment contracts and inherited texture locations."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from emblem_dev.commands.content import import_chapter
from emblem_dev.content.chapter1 import _available_groups, sample_spawns, variant_requests
from emblem_dev.content.configuration import normalize_deployment
from emblem_dev.content.definitions import deployment_records, read_deployment


class ChapterImportTest(unittest.TestCase):
    def test_plan_returns_data_without_original_runtime_or_changing_content(self):
        with tempfile.TemporaryDirectory() as temporary:
            chapter = Path(temporary) / "game/content/chapter_1"
            chapter.mkdir(parents=True)
            entry = chapter / "chapter.json"
            entry.write_text(
                json.dumps({"library": "res://content/chapter_1/library.json", "battles": {}})
            )
            library = chapter / "library.json"
            library.write_text(json.dumps({"stages": {}, "profiles": {}}))
            before = {path.name: path.read_bytes() for path in chapter.iterdir()}
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                import_chapter(chapter=chapter, plan=True)
            self.assertEqual(
                json.loads(output.getvalue()), {"maps": {}, "missing": {}, "missingProfiles": []}
            )
            self.assertEqual(before, {path.name: path.read_bytes() for path in chapter.iterdir()})

    def test_import_rejects_invalid_workflows_before_loading_original_runtime(self):
        cases = [
            ({}, "required"),
            ({"battle": "m20"}, "battle"),
            ({"route": 8}, "route"),
            (
                {"native_input": [Path("prepared")], "native_output": Path("output")},
                "separate workflows",
            ),
            ({"native_input": [Path("prepared")], "refresh_motion": True}, "fresh native sampling"),
        ]
        for arguments, message in cases:
            with self.subTest(arguments=arguments), self.assertRaisesRegex(ValueError, message):
                if not arguments:
                    import_chapter()
                else:
                    import_chapter(
                        **{"battle": "m0", "emulator": Path("emulator.jar"), **arguments}
                    )

    def test_m16_native_sampling_accepts_verified_deployment(self):
        with (
            tempfile.TemporaryDirectory() as temporary,
            patch("emblem_dev.commands.content.chapter1.export_native") as export,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            import_chapter(
                battle="m16",
                emulator=Path("emulator.jar"),
                route=2,
                native_output=Path(temporary) / "native",
            )
        self.assertEqual(export.call_args.args[3]["battleId"], "m16")
        self.assertEqual(len(export.call_args.args[3]["units"]), 54)

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

    def test_verified_m10_keeps_duplicate_source_and_unresolved_random_regions(self):
        source = Path(__file__).resolve().parents[2] / "reference/original-jars/chapter-1.jar"
        deployment = read_deployment(source, 10)
        self.assertEqual((deployment["width"], deployment["height"]), (25, 22))
        records = deployment["units"]
        self.assertEqual(len(records), 27)
        self.assertEqual(
            [(index, row["classId"]) for index, row in enumerate(records) if row["sourceId"] == 36],
            [(19, 5), (25, 12)],
        )
        self.assertEqual(records[25]["deploymentRegions"], [[15, 16, 23, 21]])
        self.assertNotIn("position", records[25])
        self.assertNotIn("id", records[25])
        self.assertEqual(sum(row["randomEquipment"] for row in records), 4)
        with self.assertRaisesRegex(ValueError, "Unverified chapter-1 battle: m20"):
            read_deployment(Path("missing-source.jar"), 20)

    def test_verified_m11_preserves_raw_deployment_order_and_random_regions(self):
        source = Path(__file__).resolve().parents[2] / "reference/original-jars/chapter-1.jar"
        deployment = read_deployment(source, 11)
        self.assertEqual((deployment["width"], deployment["height"]), (23, 25))
        records = deployment["units"]
        self.assertEqual(len(records), 55)
        self.assertEqual(len({row["sourceId"] for row in records}), 55)
        self.assertEqual(sum(row["randomEquipment"] for row in records), 14)
        self.assertEqual(sum("deploymentRegions" in row for row in records), 8)
        self.assertEqual(
            next(row for row in records if row["sourceId"] == 50)["position"], [11, 13]
        )

    def test_m11_normalization_only_moves_source50_to_its_opening_destination(self):
        root = Path(__file__).resolve().parents[2]
        deployment = read_deployment(root / "reference/original-jars/chapter-1.jar", 11)
        normalized = normalize_deployment(root / "game/content/chapter_1", deployment)
        expected = json.loads(json.dumps(deployment))
        next(row for row in expected["units"] if row["sourceId"] == 50)["position"] = [11, 12]
        self.assertEqual(normalized, expected)
        self.assertEqual(
            next(row for row in deployment["units"] if row["sourceId"] == 50)["position"], [11, 13]
        )

    def test_variant_request_covers_transferable_allied_weapons_and_enemy_choices(self):
        request = variant_requests(
            [
                {"sourceId": 0, "faction": 0, "itemChoices": [1, 0, 0], "dropTemplateId": 0},
                {"sourceId": 82, "faction": 2, "itemChoices": [1, 2, 0], "dropTemplateId": 53},
            ]
        )
        self.assertEqual(request.splitlines()[0], "allies\t" + ",".join(map(str, range(52))))
        self.assertEqual(request.splitlines()[1], "82\t0,1,2")

    def test_enemy_resampling_includes_only_matching_registered_profile_weapons(self):
        records = [
            {"sourceId": 33, "classId": 5, "faction": 2, "itemChoices": [1], "dropTemplateId": 0}
        ]
        profiles = {
            "matching": {
                "unit": {"sourceId": 33, "classId": 5, "faction": 2},
                "appearances": {"45": {}},
            },
            "other_class": {
                "unit": {"sourceId": 33, "classId": 8, "faction": 2},
                "appearances": {"25": {}},
            },
            "other_source": {
                "unit": {"sourceId": 34, "classId": 5, "faction": 2},
                "appearances": {"42": {}},
            },
            "other_faction": {
                "unit": {"sourceId": 33, "classId": 5, "faction": 1},
                "appearances": {"43": {}},
            },
        }
        self.assertEqual(variant_requests(records, profiles).splitlines()[1], "33\t0,1,45")
        self.assertEqual(records[0]["itemChoices"], [1])
        matching = profiles["matching"]
        matching["unit"].update(formal=False, classGroup=1)
        matching["motion"] = {
            "stage_0": {
                "45": {"canAttack": True, "actionGroup": "weapon45", "defenseGroup": "shape"}
            }
        }
        attacks, _ = _available_groups(
            {"profiles": {"matching": matching}},
            "stage_0",
            records,
            {"source_33_job_5_faction_2"},
        )
        self.assertEqual(attacks, {"weapon45"})

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
