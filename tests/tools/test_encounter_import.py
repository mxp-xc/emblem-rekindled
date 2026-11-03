"""Original extra-map location data is preserved without drawing rewards."""

import contextlib
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from emblem_dev.commands.content import import_chapter
from emblem_dev.content.chapter1 import candidate_key, canonicalize_prepared_contexts, sample_spawns
from emblem_dev.content.configuration import recruit_contexts
from emblem_dev.content.definitions import map_locations, read_deployment


class EncounterImportTest(unittest.TestCase):
    def test_native_candidate_identity_includes_encounter_progress(self):
        first = {"battle": "m18", "context": {"route": 0, "worldStep": 6}}
        later = {"battle": "m18", "context": {"route": 0, "worldStep": 9}}
        self.assertNotEqual(candidate_key(first), candidate_key(later))
        mainline = {"battle": "m12", "context": {"route": 0, "worldStep": 6}}
        self.assertEqual(
            candidate_key(mainline),
            candidate_key({"battle": "m12", "context": {"route": 0, "worldStep": 9}}),
        )

    def test_prepared_encounter_samples_match_equivalent_rosters_without_collisions(self):
        context = {
            "route": 0,
            "worldStep": 6,
            "equivalentContexts": [{"route": 0, "worldStep": 6}, {"route": 1, "worldStep": 7}],
        }
        candidate = {"battle": "m18", "context": context}
        canonical = candidate_key(candidate)
        alias = candidate_key({"battle": "m18", "context": {"route": 1, "worldStep": 7}})
        self.assertEqual(
            canonicalize_prepared_contexts({alias: "sample"}, [candidate]), {canonical: "sample"}
        )
        with self.assertRaisesRegex(ValueError, "Duplicate equivalent"):
            canonicalize_prepared_contexts({canonical: "first", alias: "second"}, [candidate])
        unsupported = candidate_key({"battle": "m18", "context": {"route": 1, "worldStep": 6}})
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            canonicalize_prepared_contexts({unsupported: "sample"}, [candidate])

    def test_context_plan_covers_each_reachable_route_and_progress(self):
        game = Path(__file__).resolve().parents[2] / "game"
        chapter = game / "content/chapter_1"
        entry = json.loads((chapter / "chapter.json").read_text())
        bank = json.loads((game / entry["library"][6:]).read_text())
        routes = bank["storyCommon"]["world"]["routes"]
        contexts = recruit_contexts(chapter, "m18")
        self.assertEqual(contexts, recruit_contexts(chapter, "m17"))
        self.assertEqual(contexts, recruit_contexts(chapter, "m19"))
        covered = set()
        for context in contexts:
            for equivalent in context["equivalentContexts"]:
                route, step = equivalent["route"], equivalent["worldStep"]
                self.assertNotIn((route, step), covered)
                covered.add((route, step))
                party = list(entry["initialParty"])
                for node in routes[route][:step]:
                    member = entry["recruitByNode"].get(str(node))
                    if member is not None and member not in party:
                        party.append(member)
                self.assertEqual(context["party"], party)
            self.assertIn(
                {"route": context["route"], "worldStep": context["worldStep"]},
                context["equivalentContexts"],
            )
        self.assertEqual(
            covered,
            {
                (route, step)
                for route, path in enumerate(routes)
                for step in range(6, len(path) + 1)
            },
        )

    def test_empty_encounter_slots_do_not_hide_missing_units(self):
        slots = [
            {"sourceId": slot, "classId": 0, "faction": 0, "deploymentSlot": slot}
            for slot in range(3)
        ]
        enemy = {"sourceId": 20, "classId": 4, "faction": 1}
        allies = [
            {
                "id": slot,
                "sourceId": slot,
                "classId": 0,
                "faction": 0,
                "nativePolicy": slot,
                "formal": True,
            }
            for slot in range(2)
        ]
        native_enemy = {"id": 20, "sourceId": 20, "classId": 4, "faction": 1, "formal": False}
        result = sample_spawns(slots + [enemy], allies + [native_enemy], allow_empty_slots=True)
        self.assertEqual([row.get("deploymentSlot") for row in result], [0, 1, None])
        with self.assertRaises(ValueError):
            sample_spawns(slots + [enemy], allies, allow_empty_slots=True)
        with self.assertRaises(ValueError):
            sample_spawns(slots + [enemy], allies[1:] + [native_enemy], allow_empty_slots=True)
        unexpected = {**native_enemy, "id": 21, "sourceId": 21}
        with self.assertRaises(ValueError):
            sample_spawns(
                slots + [enemy], allies + [native_enemy, unexpected], allow_empty_slots=True
            )
        with self.assertRaises(ValueError):
            sample_spawns(slots + [enemy], allies + [native_enemy])

    def test_encounter_native_sampling_requires_explicit_route(self):
        with self.assertRaisesRegex(ValueError, "route"):
            import_chapter(battle="m17", emulator=Path("emulator.jar"), native_output=Path("out"))
        with self.assertRaisesRegex(ValueError, "world step"):
            import_chapter(
                battle="m18",
                emulator=Path("emulator.jar"),
                route=0,
                native_output=Path("out"),
                encounter_step=5,
            )
        with self.assertRaisesRegex(ValueError, "world step"):
            import_chapter(
                battle="m18",
                emulator=Path("emulator.jar"),
                route=0,
                native_output=Path("out"),
                encounter_step=11,
            )
        with self.assertRaisesRegex(ValueError, "encounter-step"):
            import_chapter(battle="m1", emulator=Path("emulator.jar"), encounter_step=6)
        with self.assertRaisesRegex(ValueError, "adaptive"):
            import_chapter(
                battle="m18",
                emulator=Path("emulator.jar"),
                route=2,
                native_output=Path("out"),
                adaptive=True,
            )
        with (
            patch("emblem_dev.commands.content.chapter1.export_native") as export,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            import_chapter(
                battle="m17",
                emulator=Path("emulator.jar"),
                route=0,
                native_output=Path("out"),
                encounter_step=6,
            )
        self.assertEqual(export.call_args.args[3]["battleId"], "m17")
        self.assertEqual(len(export.call_args.args[3]["units"]), 31)
        self.assertEqual(export.call_args.args[4], 0)
        self.assertEqual(export.call_args.kwargs["encounter_step"], 6)
        with (
            patch("emblem_dev.commands.content.chapter1.export_native") as export,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            import_chapter(
                battle="m19",
                emulator=Path("emulator.jar"),
                route=2,
                native_output=Path("out"),
                encounter_step=9,
                adaptive=True,
            )
        self.assertEqual(export.call_args.args[3]["battleId"], "m19")
        self.assertEqual(export.call_args.kwargs["encounter_step"], 9)
        self.assertTrue(export.call_args.kwargs["adaptive"])

    def test_encounter_publication_uses_the_chapter_update_workflow(self):
        for battle in ("m17", "m18", "m19"):
            with (
                self.subTest(battle=battle),
                patch(
                    "emblem_dev.commands.content.chapter1.update_chapter",
                    return_value={"contexts": []},
                ) as update,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                import_chapter(battle=battle, emulator=Path("emulator.jar"), route=2)
            self.assertEqual(update.call_args.args[1], battle)
            self.assertEqual(update.call_args.args[3], 2)

    def test_original_locations(self):
        source = Path(__file__).resolve().parents[2] / "reference/original-jars/chapter-1.jar"
        for battle, dimensions, count, locations in (
            (17, (20, 20), 31, 3),
            (18, (23, 25), 25, 4),
            (19, (16, 16), 17, 8),
        ):
            with self.subTest(battle=battle):
                data = read_deployment(source, battle)
                self.assertEqual((data["width"], data["height"]), dimensions)
                self.assertEqual(len(data["units"]), count)
                self.assertEqual(len(data["locations"]), locations)
                self.assertTrue(all(row["kind"] == "chest" for row in data["locations"]))
        m17 = read_deployment(source, 17)["locations"]
        self.assertEqual(m17[0]["emptyWeight"], 60)
        self.assertEqual(m17[1]["reward"], {"kind": "goldRange", "minimum": 1, "maximum": 2000})
        self.assertEqual(m17[2]["emptyWeight"], 39)
        m18 = read_deployment(source, 18)["locations"]
        self.assertEqual(m18[1]["emptyWeight"], 24)
        self.assertNotIn("emptyWeight", m18[3])
        m19 = read_deployment(source, 19)["locations"]
        self.assertEqual(m19[4]["reward"], {"kind": "item", "templateId": 64})
        self.assertEqual(m19[5]["reward"], {"kind": "item", "templateId": 76})

    def test_overweight_chest_is_rejected(self):
        invalid = bytes([1, 1, 79, 1, 3, 0, 0, 2, 9, 60, 18, 50])
        with self.assertRaises(ValueError):
            map_locations(invalid, 17)


if __name__ == "__main__":
    unittest.main()
