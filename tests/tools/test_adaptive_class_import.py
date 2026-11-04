"""Controlled native sampling retains deployment identity during automatic class selection."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from emblem_dev.commands.content import import_chapter
from emblem_dev.content.chapter1 import (
    EMULATOR_SHA,
    bind_adaptive_profiles,
    candidate_key,
    export_native,
    preserve_native_sample,
    sample_spawns,
    update_chapter,
    validate_adaptive_summons,
    validate_promotions,
    variant_requests,
)
from emblem_dev.content.definitions import SOURCE_SHA
from texture_fixture import png


class AdaptiveClassSamplingTest(unittest.TestCase):
    def test_trusted_profile_numeric_fields_reject_booleans(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            chapter = root / "game/content/chapter_1"
            chapter.mkdir(parents=True)
            (chapter / "chapter.json").write_text(
                json.dumps(
                    {
                        "battles": {"m1": "res://content/chapter_1/battle.json"},
                        "library": "res://content/chapter_1/catalog.json",
                    }
                )
            )
            record = {"kind": 1, "sourceId": 1, "classId": 8, "faction": 1}
            (chapter / "records.json").write_text(json.dumps([record]))
            (chapter / "battle.json").write_text(
                json.dumps(
                    {
                        "deployments": "res://content/chapter_1/records.json",
                        "profiles": {"source_1_job_9_faction_1": "p"},
                    }
                )
            )
            native = root / "native"
            native.mkdir()
            (native / "provenance.json").write_text(
                json.dumps(
                    {
                        "sourceSha256": SOURCE_SHA,
                        "emulatorSha256": EMULATOR_SHA,
                        "preparationSeed": 0,
                        "map": "1.pak:m1",
                        "route": 0,
                        "summonClassId": 28,
                        "adaptivePreparation": {"maxInternalLevel": 9, "averageInternalLevel": 9},
                    }
                )
            )
            for key in ("sourceId", "faction"):
                unit = {"sourceId": 1, "classId": 9, "faction": 1}
                unit[key] = True
                (chapter / "catalog.json").write_text(
                    json.dumps({"profiles": {"p": {"unit": unit}}})
                )
                with (
                    self.subTest(field=key),
                    patch(
                        "emblem_dev.content.chapter1.read_deployment",
                        return_value={"units": [record]},
                    ),
                    patch(
                        "emblem_dev.content.chapter1.normalize_deployment",
                        side_effect=lambda _c, d: d,
                    ),
                    patch(
                        "emblem_dev.content.chapter1.tempfile.TemporaryDirectory",
                        side_effect=RuntimeError("preflight passed"),
                    ),
                    self.assertRaisesRegex(ValueError, "adaptive base"),
                ):
                    update_chapter(chapter, "m1", root / "emu", 0, None, [native])

    def test_combined_input_requires_base_of_same_battle_but_not_same_route(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            chapter = root / "game/content/chapter_1"
            chapter.mkdir(parents=True)

            def prepared(name, battle, route, promotion):
                path = root / name
                path.mkdir()
                value = {
                    "sourceSha256": SOURCE_SHA,
                    "emulatorSha256": EMULATOR_SHA,
                    "preparationSeed": 0,
                    "map": f"1.pak:{battle}",
                    "route": route,
                    "adaptivePreparation": {"maxInternalLevel": 9, "averageInternalLevel": 9},
                }
                if promotion:
                    value["promotionPreparation"] = "native action"
                (path / "provenance.json").write_text(json.dumps(value))
                return path

            combined = prepared("combined", "m13", 4, True)
            other = prepared("other", "m12", 4, False)
            with self.assertRaisesRegex(ValueError, "adaptive base"):
                update_chapter(chapter, "m13", root / "emu", 4, None, [combined, other])
            same = prepared("same", "m13", 7, False)
            ordinary = root / "ordinary"
            ordinary.mkdir()
            (ordinary / "provenance.json").write_text(
                json.dumps(
                    {
                        "sourceSha256": SOURCE_SHA,
                        "emulatorSha256": EMULATOR_SHA,
                        "preparationSeed": 0,
                        "map": "1.pak:m13",
                        "route": 4,
                        "promotionPreparation": "native action",
                    }
                )
            )
            with patch(
                "emblem_dev.content.chapter1.tempfile.TemporaryDirectory",
                side_effect=RuntimeError("preflight passed"),
            ):
                with self.assertRaisesRegex(RuntimeError, "preflight passed"):
                    update_chapter(chapter, "m13", root / "emu", 4, None, [combined, same])
                with self.assertRaisesRegex(RuntimeError, "preflight passed"):
                    update_chapter(chapter, "m13", root / "emu", 4, None, [ordinary])

    def test_combined_input_accepts_only_complete_trusted_existing_bindings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game = root / "game"
            chapter = game / "content/chapter_1"
            chapter.mkdir(parents=True)
            (chapter / "chapter.json").write_text(
                json.dumps(
                    {
                        "battles": {"m13": "res://content/chapter_1/battle.json"},
                        "library": "res://content/chapter_1/catalog.json",
                    }
                )
            )
            records = [
                {"kind": 1, "sourceId": 91, "classId": 16, "faction": 2},
                {"kind": 1, "sourceId": 63, "classId": 28, "faction": 2},
            ]
            (chapter / "records.json").write_text(json.dumps(records))
            recipes = {"source_91_job_17_faction_2": "p91", "source_63_job_29_faction_2": "p63"}
            definition = {
                "deployments": "res://content/chapter_1/records.json",
                "profiles": recipes,
            }
            (chapter / "battle.json").write_text(json.dumps(definition))
            catalog = {
                "profiles": {
                    "p91": {"unit": {"sourceId": 91, "classId": 17, "faction": 2}},
                    "p63": {"unit": {"sourceId": 63, "classId": 29, "faction": 2}},
                }
            }
            (chapter / "catalog.json").write_text(json.dumps(catalog))
            native = root / "native"
            native.mkdir()
            (native / "provenance.json").write_text(
                json.dumps(
                    {
                        "sourceSha256": SOURCE_SHA,
                        "emulatorSha256": EMULATOR_SHA,
                        "preparationSeed": 0,
                        "map": "1.pak:m13",
                        "route": 4,
                        "summonClassId": 28,
                        "adaptivePreparation": {"maxInternalLevel": 9, "averageInternalLevel": 9},
                    }
                )
            )

            def run_update():
                with (
                    patch(
                        "emblem_dev.content.chapter1.read_deployment",
                        return_value={"battleId": "m13", "units": records},
                    ),
                    patch(
                        "emblem_dev.content.chapter1.normalize_deployment",
                        side_effect=lambda _chapter, deployment: deployment,
                    ),
                ):
                    return update_chapter(chapter, "m13", root / "emu", 4, None, [native])

            with patch(
                "emblem_dev.content.chapter1.tempfile.TemporaryDirectory",
                side_effect=RuntimeError("preflight passed"),
            ):
                with self.assertRaisesRegex(RuntimeError, "preflight passed"):
                    run_update()
            for altered in ([], records[:1], [{**records[0], "sourceId": 92}, records[1]]):
                (chapter / "records.json").write_text(json.dumps(altered))
                with (
                    self.subTest(records=altered),
                    patch(
                        "emblem_dev.content.chapter1.tempfile.TemporaryDirectory",
                        side_effect=RuntimeError("preflight passed"),
                    ),
                    self.assertRaisesRegex(ValueError, "adaptive base"),
                ):
                    run_update()
            (chapter / "records.json").write_text(
                json.dumps([{**records[0], "kind": True}, records[1]])
            )
            with (
                patch(
                    "emblem_dev.content.chapter1.tempfile.TemporaryDirectory",
                    side_effect=RuntimeError("preflight passed"),
                ),
                self.assertRaisesRegex(ValueError, "adaptive base"),
            ):
                run_update()
            (chapter / "records.json").write_text(json.dumps(records))
            spoofed = [{**records[0], "sourceId": 92}, records[1]]
            (chapter / "records.json").write_text(json.dumps(spoofed))
            definition["profiles"]["source_92_job_17_faction_2"] = definition["profiles"].pop(
                "source_91_job_17_faction_2"
            )
            catalog["profiles"]["p91"]["unit"]["sourceId"] = 92
            (chapter / "battle.json").write_text(json.dumps(definition))
            (chapter / "catalog.json").write_text(json.dumps(catalog))
            with (
                patch(
                    "emblem_dev.content.chapter1.tempfile.TemporaryDirectory",
                    side_effect=RuntimeError("preflight passed"),
                ),
                self.assertRaisesRegex(ValueError, "adaptive base"),
            ):
                run_update()
            (chapter / "records.json").write_text(json.dumps(records))
            definition["profiles"]["source_91_job_17_faction_2"] = definition["profiles"].pop(
                "source_92_job_17_faction_2"
            )
            catalog["profiles"]["p91"]["unit"]["sourceId"] = 91
            (chapter / "catalog.json").write_text(json.dumps(catalog))
            del definition["profiles"]["source_63_job_29_faction_2"]
            (chapter / "battle.json").write_text(json.dumps(definition))
            with self.assertRaisesRegex(ValueError, "adaptive base"):
                run_update()
            definition["profiles"]["source_63_job_29_faction_2"] = "p63"
            (chapter / "battle.json").write_text(json.dumps(definition))
            catalog["profiles"]["p63"]["unit"]["classId"] = 25
            (chapter / "catalog.json").write_text(json.dumps(catalog))
            with self.assertRaisesRegex(ValueError, "adaptive base"):
                run_update()

    def test_combined_input_without_base_or_bindings_is_rejected_before_update(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            chapter = root / "game/content/chapter_1"
            chapter.mkdir(parents=True)
            prepared = root / "prepared"
            prepared.mkdir()
            (prepared / "provenance.json").write_text(
                json.dumps(
                    {
                        "sourceSha256": SOURCE_SHA,
                        "emulatorSha256": EMULATOR_SHA,
                        "preparationSeed": 0,
                        "map": "1.pak:m13",
                        "route": 4,
                        "promotionPreparation": "native action",
                        "adaptivePreparation": {"maxInternalLevel": 9, "averageInternalLevel": 9},
                    }
                )
            )
            with patch(
                "emblem_dev.content.chapter1.tempfile.TemporaryDirectory",
                side_effect=RuntimeError("proceeded"),
            ):
                with self.assertRaisesRegex(ValueError, "adaptive base"):
                    update_chapter(chapter, "m13", root / "emulator", 4, None, [prepared])

    def test_adaptive_samples_registered_weapons_for_selected_enemy_class(self):
        records = [
            {
                "kind": 1,
                "sourceId": 37,
                "classId": 12,
                "faction": 2,
                "itemChoices": [51],
                "dropTemplateId": 65,
            }
        ]
        profiles = {
            "selected": {
                "unit": {"sourceId": 37, "classId": 13, "faction": 2},
                "appearances": {"45": {}},
            },
            "other_source": {
                "unit": {"sourceId": 38, "classId": 13, "faction": 2},
                "appearances": {"44": {}},
            },
            "other_class": {
                "unit": {"sourceId": 37, "classId": 14, "faction": 2},
                "appearances": {"43": {}},
            },
        }
        self.assertEqual(
            variant_requests(records, profiles, adaptive=True).splitlines()[1], "37\t0,45,51"
        )
        self.assertEqual(variant_requests(records, profiles).splitlines()[1], "37\t0,51")
        self.assertEqual(records[0]["itemChoices"], [51])

    def test_evidence_directory_must_be_new_and_outside_chapter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            chapter = root / "chapter"
            chapter.mkdir()
            with self.assertRaises(ValueError):
                update_chapter(
                    chapter, "m13", root / "emu", 4, None, [], evidence_output=chapter / "evidence"
                )
            existing = root / "existing"
            existing.mkdir()
            with self.assertRaises(FileExistsError):
                update_chapter(chapter, "m13", root / "emu", 4, None, [], evidence_output=existing)
            self.assertEqual(list(existing.iterdir()), [])

    def test_native_evidence_is_new_complete_and_verified(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "units.json").write_text("units")
            (source / "spawns.json").write_text("spawns")
            (source / "provenance.json").write_text("provenance")
            (source / "battle" / "clips").mkdir(parents=True)
            (source / "battle" / "clips" / "manifest.json").write_text("manifest")
            (source / "nested").mkdir()
            (source / "nested" / "sprite.png").write_bytes(png(b"pixels"))
            destination = root / "evidence"
            preserve_native_sample(source, destination)
            self.assertEqual((destination / "units.json").read_text(), "units")
            self.assertEqual((destination / "nested" / "sprite.png").read_bytes(), png(b"pixels"))
            with self.assertRaises(FileExistsError):
                preserve_native_sample(source, destination)
            with self.assertRaises(ValueError):
                preserve_native_sample(source, source / "nested-output")
            (source / "external").symlink_to(root / "outside")
            with self.assertRaises(ValueError):
                preserve_native_sample(source, root / "unsafe")
            (source / "external").unlink()
            (source / "spawns.json").unlink()
            with self.assertRaisesRegex(ValueError, "incomplete"):
                preserve_native_sample(source, root / "incomplete")

    def test_corrupt_evidence_copy_is_rejected_and_retained(self):
        import shutil

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "units.json").write_text("valid")
            (source / "spawns.json").write_text("spawns")
            (source / "provenance.json").write_text("provenance")
            (source / "battle" / "clips").mkdir(parents=True)
            (source / "battle" / "clips" / "manifest.json").write_text("manifest")
            destination = root / "evidence"
            original_copy = shutil.copytree

            def corrupt_copy(src, dst, *args, **kwargs):
                result = original_copy(src, dst, *args, **kwargs)
                if Path(src).resolve() == source.resolve():
                    (Path(dst) / "units.json").write_text("wrong")
                return result

            with patch("emblem_dev.content.chapter1.shutil.copytree", side_effect=corrupt_copy):
                with self.assertRaisesRegex(ValueError, "evidence"):
                    preserve_native_sample(source, destination)
            self.assertEqual((destination / "units.json").read_text(), "wrong")

    def test_candidate_key_distinguishes_combined_adaptive_contexts(self):
        base = {"battle": "m13", "context": {"route": 4}}
        keys = {
            candidate_key(base),
            candidate_key({**base, "adaptive": True}),
            candidate_key({**base, "adaptive": True, "promotion": True}),
            candidate_key({**base, "adaptive": True, "summonClass": 28}),
        }
        self.assertEqual(len(keys), 4)

    def test_adaptive_bindings_require_matching_native_profile_for_each_candidate(self):
        records = [{"kind": 1, "sourceId": 91, "classId": 16, "faction": 2}]
        recipe = "source_91_job_17_faction_2"
        profiles = {recipe: {"unit": {"sourceId": 91, "classId": 17, "faction": 2}}}
        bindings = bind_adaptive_profiles(records, {}, {recipe: recipe}, profiles)
        self.assertEqual(bindings, {recipe: recipe})
        with self.assertRaises(ValueError):
            bind_adaptive_profiles(records, {}, {}, profiles)
        with self.assertRaises(ValueError):
            bind_adaptive_profiles(records, {recipe: "different"}, {recipe: recipe}, profiles)
        profiles[recipe]["unit"]["classId"] = 16
        with self.assertRaises(ValueError):
            bind_adaptive_profiles(records, {}, {recipe: recipe}, profiles)
        ally = [{"kind": 1, "sourceId": 1, "classId": 8, "faction": 1}]
        key = "source_1_job_9_faction_1"
        bad = {key: {"unit": {"sourceId": 1, "classId": 9, "faction": True}}}
        with self.assertRaises(ValueError):
            bind_adaptive_profiles(ally, {}, {key: key}, bad)

    def test_promotion_and_summon_are_still_mutually_exclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, "cannot be combined"):
                export_native(
                    root / "source.jar",
                    root / "new-output",
                    root / "emulator.jar",
                    {},
                    0,
                    promotion=True,
                    summon_class=28,
                    adaptive=True,
                )

    def test_combined_summon_checks_deployment_before_caster_preparation(self):
        records = [{"kind": 1, "sourceId": 91, "classId": 16, "faction": 2, "policy": 0}]
        source = {
            "id": 91,
            "sourceId": 91,
            "classId": 17,
            "faction": 2,
            "formal": False,
            "level": 10,
        }
        ally = {"id": 0, "sourceId": 0, "classId": 0, "faction": 0, "formal": True, "level": 3}
        records.append({"kind": 1, "sourceId": 0, "classId": 0, "faction": 0, "policy": 0})
        born = [
            {"id": i, "sourceId": i, "classId": 28, "faction": faction, "formal": False}
            for faction, start in ((1, 20), (2, 70))
            for i in range(start, start + 10)
        ]
        declarations = [
            {"sourceId": u["id"], "classId": u["classId"], "faction": u["faction"]} for u in born
        ]
        with tempfile.TemporaryDirectory() as directory:
            native = Path(directory)
            for name, value in {
                "adaptive_sources.json": [source, ally],
                "units.json": [{**source, "level": 1}, {**ally, "level": 1}, *born],
                "summons.json": declarations,
                "summon_casters.json": [
                    {"id": 0, "faction": 0, "beforeLevel": 3, "afterLevel": 1},
                    {"id": 91, "faction": 2, "beforeLevel": 10, "afterLevel": 1},
                ],
            }.items():
                (native / name).write_text(json.dumps(value))
            self.assertEqual(validate_adaptive_summons(native, records, 28)[0]["classId"], 16)
            units = [{**source, "level": 1, "classId": 16}, {**ally, "level": 1}, *born]
            (native / "units.json").write_text(json.dumps(units))
            with self.assertRaises(ValueError):
                validate_adaptive_summons(native, records, 28)
            units = [{**source, "level": 2}, {**ally, "level": 1}, *born]
            (native / "units.json").write_text(json.dumps(units))
            with self.assertRaises(ValueError):
                validate_adaptive_summons(native, records, 28)

    def test_combined_m0_allows_only_documented_opening_visibility_normalization(self):
        records = [
            {"kind": 1, "sourceId": 67, "classId": 12, "faction": 2, "policy": 0},
            {"kind": 1, "sourceId": 0, "classId": 0, "faction": 0, "policy": 0},
        ]
        source = {
            "id": 67,
            "sourceId": 67,
            "classId": 13,
            "faction": 2,
            "formal": False,
            "level": 10,
            "flags": 1,
            "visible": False,
        }
        ally = {
            "id": 0,
            "sourceId": 0,
            "classId": 0,
            "faction": 0,
            "formal": True,
            "level": 1,
            "flags": 0,
            "visible": True,
        }
        born = [
            {"id": i, "sourceId": i, "classId": 29, "faction": f, "formal": False}
            for f, first in ((1, 20), (2, 70))
            for i in range(first, first + 10)
        ]
        with tempfile.TemporaryDirectory() as directory:
            native = Path(directory)
            files = {
                "adaptive_sources.json": [source, ally],
                "units.json": [{**source, "level": 1, "flags": 0, "visible": True}, ally, *born],
                "summons.json": [
                    {"sourceId": u["id"], "classId": 29, "faction": u["faction"]} for u in born
                ],
                "summon_casters.json": [
                    {"id": 0, "faction": 0, "beforeLevel": 1, "afterLevel": 1},
                    {"id": 67, "faction": 2, "beforeLevel": 10, "afterLevel": 1},
                ],
            }
            for name, value in files.items():
                (native / name).write_text(json.dumps(value))
            self.assertEqual(len(validate_adaptive_summons(native, records, 29, battle_id="m0")), 2)
            with self.assertRaises(ValueError):
                validate_adaptive_summons(native, records, 29, battle_id="m1")

    def test_adaptive_mode_requires_isolated_native_output(self):
        with self.assertRaisesRegex(ValueError, "isolated --native-output"):
            import_chapter(battle="m13", emulator=Path("emulator.jar"), adaptive=True)

    def test_adaptive_sample_retains_independent_original_promotion_identity(self):
        records = [
            {"kind": 1, "sourceId": 91, "classId": 16, "faction": 2, "policy": 0},
            {"kind": 1, "sourceId": 0, "classId": 0, "faction": 0, "policy": 0},
        ]
        sources = [
            {"id": 91, "sourceId": 91, "classId": 17, "faction": 2, "formal": False, "level": 10},
            {"id": 0, "sourceId": 0, "classId": 0, "faction": 0, "formal": True},
        ]
        units = [dict(sources[0]), {**sources[1], "classId": 1}]
        with tempfile.TemporaryDirectory() as directory:
            native = Path(directory)
            for name, value in {
                "promotion_sources.json": sources,
                "units.json": units,
                "promotion_units.json": [{"id": 0, "fromClassId": 0, "toClassId": 1}],
                "promotions.json": [{"fromClassId": 0, "toClassId": 1}],
            }.items():
                (native / name).write_text(json.dumps(value))
            self.assertEqual(validate_promotions(native, records, adaptive=True)[0]["classId"], 16)
            units[0]["classId"] = 16
            (native / "units.json").write_text(json.dumps(units))
            with self.assertRaises(ValueError):
                validate_promotions(native, records, adaptive=True)

    def test_only_native_eligible_records_select_the_next_class(self):
        records = [
            {"kind": 1, "sourceId": 91, "classId": 16, "faction": 2, "policy": 0},
            {"kind": 1, "sourceId": 10, "classId": 8, "faction": 1, "policy": 0},
            {"kind": 0, "sourceId": 92, "classId": 40, "faction": 2, "policy": 0},
            {"kind": 1, "sourceId": 83, "classId": 17, "faction": 2, "policy": 0},
        ]
        units = [
            {"id": 91, "sourceId": 91, "classId": 17, "faction": 2, "formal": False, "level": 10},
            {"id": 10, "sourceId": 10, "classId": 9, "faction": 1, "formal": False, "level": 10},
            {"id": 92, "sourceId": 92, "classId": 40, "faction": 2, "formal": False},
            {"id": 83, "sourceId": 83, "classId": 17, "faction": 2, "formal": False, "level": 10},
        ]
        spawns = sample_spawns(records, units, adaptive=True)
        self.assertEqual([row["classId"] for row in spawns], [16, 8, 40, 17])
        self.assertEqual([row["sourceId"] for row in spawns], [91, 10, 92, 83])
        for index, wrong in ((0, 16), (1, 10), (2, 41), (3, 18)):
            bad = [unit.copy() for unit in units]
            bad[index]["classId"] = wrong
            with self.subTest(index=index), self.assertRaises(ValueError):
                sample_spawns(records, bad, adaptive=True)
        with self.assertRaises(ValueError):
            sample_spawns(records, units)
        bad = [unit.copy() for unit in units]
        bad[0]["level"] = 9
        with self.assertRaises(ValueError):
            sample_spawns(records, bad, adaptive=True)


if __name__ == "__main__":
    unittest.main()
