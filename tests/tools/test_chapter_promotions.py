"""Finite promotion preparation keeps deployment identities and class-specific requests."""

import json
import tempfile
import unittest
from pathlib import Path

from emblem_dev.content.chapter1 import (
    _context_requests,
    _profile_request,
    candidate_key,
    validate_promotions,
)
from emblem_dev.content.configuration import import_promotion_rules, recruit_binding_plan


class ChapterPromotionsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.chapter = self.root / "game/content/chapter_1"
        self.native = self.root / "native"
        self.pair = {"fromClassId": 0, "toClassId": 1, "minimumLevel": 10, "gains": {"maxHp": 4}}

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def test_prepared_promotions_preserve_original_spawns_and_reject_stale_class_or_identity(self):
        original = {"id": 0, "sourceId": 0, "faction": 0, "formal": True, "classId": 0}
        records = [{"sourceId": 0, "faction": 0, "classId": 0}]
        self.write(self.native / "promotion_sources.json", [original])
        self.write(self.native / "promotions.json", [self.pair])
        self.write(
            self.native / "promotion_units.json", [{"id": 0, "fromClassId": 0, "toClassId": 1}]
        )
        promoted = {**original, "classId": 1}
        self.write(self.native / "units.json", [promoted])
        self.assertEqual(validate_promotions(self.native, records)[0]["classId"], 0)
        with_empty_slot = records + [
            {"sourceId": 2, "faction": 0, "classId": 8, "deploymentSlot": 2}
        ]
        self.assertEqual(
            validate_promotions(self.native, with_empty_slot, allow_empty_slots=True),
            validate_promotions(self.native, records),
        )
        with self.assertRaises(ValueError):
            validate_promotions(self.native, with_empty_slot)
        for key, invalid in (("classId", 2), ("sourceId", 9), ("formal", False)):
            with self.subTest(key=key):
                self.write(self.native / "units.json", [{**promoted, key: invalid}])
                with self.assertRaisesRegex(ValueError, "source identity or class"):
                    validate_promotions(self.native, records)

    def test_contexts_and_member_requests_distinguish_current_class(self):
        rows = [{"deploymentSlot": 0}, {"deploymentSlot": 2, "classId": 8}]
        context = {"party": [0]}
        base = _context_requests(rows, context, {0}, {0: 0})
        promoted = _context_requests(rows, context, {0}, {0: 0}, True)
        encounter = _context_requests(rows, context, {0}, {0: 0}, allow_empty_slots=True)
        self.assertEqual(base, {"source_0_job_0_faction_0", "slot_2_job_8_faction_0"})
        self.assertEqual(promoted, {"source_0_job_1_faction_0", "slot_2_job_9_faction_0"})
        self.assertEqual(encounter, {"source_0_job_0_faction_0"})
        self.assertNotEqual(
            candidate_key({"battle": "m1", "context": {"route": 0}}),
            candidate_key({"battle": "m1", "context": {"route": 0}, "promotion": True}),
        )
        profile = {"unit": {"formal": True, "sourceId": 0, "classId": 1, "faction": 0}}
        self.assertEqual(
            _profile_request("source_0_job_1_faction_0", profile), "source_0_job_1_faction_0"
        )
        self.assertNotIn(_profile_request("source_0_job_1_faction_0", profile), base)

    def test_original_rule_table_merges_once_and_rejects_conflicting_values(self):
        self.write(self.chapter / "chapter.json", {"rules": "res://content/chapter_1/rules.json"})
        self.write(self.chapter / "rules.json", {"statCaps": {"maxHp": 60}})
        self.write(self.native / "promotions.json", [self.pair])
        import_promotion_rules(self.chapter, self.native)
        before = (self.chapter / "rules.json").read_bytes()
        import_promotion_rules(self.chapter, self.native)
        self.assertEqual((self.chapter / "rules.json").read_bytes(), before)
        self.write(self.native / "promotions.json", [{**self.pair, "minimumLevel": 11}])
        with self.assertRaisesRegex(ValueError, "Conflicting original promotion"):
            import_promotion_rules(self.chapter, self.native)
        self.assertEqual((self.chapter / "rules.json").read_bytes(), before)

    def test_existing_base_profile_does_not_hide_missing_formal_or_temporary_target(self):
        self.write(
            self.chapter / "chapter.json",
            {
                "library": "res://content/chapter_1/library.json",
                "rules": "res://content/chapter_1/rules.json",
                "initialParty": [0],
                "recruitByNode": {"1": 6},
                "battles": {"m1": "res://content/chapter_1/m1.json"},
            },
        )
        self.write(
            self.chapter / "rules.json",
            {
                "promotions": [
                    self.pair,
                    {**self.pair, "fromClassId": 8, "toClassId": 9},
                    {**self.pair, "fromClassId": 20, "toClassId": 21},
                ]
            },
        )
        self.write(
            self.chapter / "library.json",
            {
                "storyCommon": {"world": {"routes": [[0, 1]]}},
                "profiles": {
                    "base": {"unit": {"formal": True, "faction": 0, "sourceId": 0, "classId": 0}},
                    "recruit": {
                        "unit": {"formal": True, "faction": 0, "sourceId": 6, "classId": 20}
                    },
                },
            },
        )
        self.write(
            self.chapter / "m1.json",
            {
                "profiles": {"slot_2_job_8_faction_0": "temporary"},
                "deployments": "res://content/chapter_1/rows.json",
            },
        )
        self.write(
            self.chapter / "rows.json",
            [
                {"deploymentSlot": 2, "classId": 8, "faction": 0},
                {"sourceId": 6, "classId": 20, "faction": 0},
            ],
        )
        missing = recruit_binding_plan(self.chapter)["missingProfiles"]
        self.assertEqual(
            {row["recipe"] for row in missing},
            {"source_0_job_1_faction_0", "source_6_job_21_faction_0", "slot_2_job_9_faction_0"},
        )

    def test_encounter_empty_slots_do_not_require_temporary_profiles(self):
        root = "res://content/chapter_1/"
        self.write(
            self.chapter / "chapter.json",
            {
                "library": root + "library.json",
                "initialParty": [0],
                "recruitByNode": {},
                "battles": {"m1": root + "m1.json", "m18": root + "m18.json"},
            },
        )
        self.write(
            self.chapter / "library.json",
            {
                "storyCommon": {"world": {"routes": [[0, 1, 2, 3, 4, 5, 6]]}},
                "profiles": {
                    "base": {"unit": {"formal": True, "faction": 0, "sourceId": 0, "classId": 0}}
                },
            },
        )
        for battle in ("m1", "m18"):
            self.write(
                self.chapter / f"{battle}.json", {"profiles": {}, "deployments": root + "rows.json"}
            )
        self.write(self.chapter / "rows.json", [{"deploymentSlot": 2, "classId": 8, "faction": 0}])
        missing = recruit_binding_plan(self.chapter)["missingProfiles"]
        self.assertEqual(missing, [{"battleId": "m1", "recipe": "slot_2_job_8_faction_0"}])


if __name__ == "__main__":
    unittest.main()
