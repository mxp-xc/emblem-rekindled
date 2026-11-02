"""Shared texture ownership protects other battles and authored replacements."""

import json
import tempfile
import unittest
from pathlib import Path

from emblem_dev.content.assets import publish_generated, share_textures


class ChapterAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.chapter = Path(self.temporary.name) / "game/content/chapter_1"
        self.generated = self.chapter / "generated"
        self.shared = self.generated / "shared"
        self.write_json(
            self.shared / "provenance.json",
            {"outputs": [], "textureImportParameters": {"compress/mode": "0"}},
        )

    def write_json(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def battle(self, name, images):
        directory = self.generated if name == "m0" else self.generated / "battles" / name
        directory.mkdir(parents=True, exist_ok=True)
        for image, data in images.items():
            path = directory / image
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.write_json(
            directory / "units.json",
            [{"sprite": image, "offsetX": -24, "id": index} for index, image in enumerate(images)],
        )
        self.write_json(directory / "provenance.json", {"outputs": [*images, "units.json"]})
        return directory

    def images(self, directory):
        return [
            (directory / unit["sprite"]).resolve()
            for unit in json.loads((directory / "units.json").read_text())
        ]

    def snapshot(self):
        return {
            p.relative_to(self.chapter): p.read_bytes()
            for p in self.chapter.rglob("*")
            if p.is_file()
        }

    def stage(self, images):
        directory = Path(tempfile.mkdtemp(dir=self.temporary.name))
        for name, data in images.items():
            (directory / name).write_bytes(data)
        self.write_json(directory / "units.json", [{"sprite": name} for name in images])
        self.write_json(directory / "provenance.json", {"outputs": [*images, "units.json"]})
        return directory

    def test_full_bytes_shared_across_different_names_but_same_name_can_differ(self):
        first = self.battle("m0", {"unit_0.png": b"one", "same.png": b"first"})
        second = self.battle("m1", {"another.png": b"one", "same.png": b"second"})
        result = share_textures(self.chapter)
        self.assertEqual(result["sharedTextures"], 3)
        self.assertEqual(self.images(first)[0], self.images(second)[0])
        self.assertNotEqual(self.images(first)[1], self.images(second)[1])
        self.assertEqual([p.read_bytes() for p in self.images(second)], [b"one", b"second"])
        units = json.loads((second / "units.json").read_text())
        self.assertEqual(units[1]["offsetX"], -24)
        self.assertEqual(
            json.loads((first / "provenance.json").read_text())["outputs"], ["units.json"]
        )

    def test_different_import_parameters_remain_separate_and_keep_uid(self):
        first = self.battle("m0", {"same.png": b"one"})
        second = self.battle("m1", {"same.png": b"one"})
        sidecar = second / "same.png.import"
        sidecar.write_text(
            '[remap]\nimporter="texture"\nuid="uid://original"\n[params]\ncompress/mode=1\n'
        )
        share_textures(self.chapter)
        self.assertNotEqual(self.images(first)[0], self.images(second)[0])
        self.assertIn(
            'uid="uid://original"', Path(str(self.images(second)[0]) + ".import").read_text()
        )

    def test_reimport_reuses_existing_and_changed_source_preserves_other_battle(self):
        first = self.battle("m0", {"same.png": b"old"})
        second = self.battle("m1", {"same.png": b"old"})
        share_textures(self.chapter)
        old = self.images(second)[0]
        self.battle("m0", {"same.png": b"old"})
        share_textures(self.chapter)
        self.assertEqual(self.images(first)[0], old)
        self.battle("m0", {"same.png": b"new"})
        share_textures(self.chapter)
        self.assertEqual(self.images(second)[0], old)
        self.assertEqual(old.read_bytes(), b"old")
        self.assertEqual(self.images(first)[0].read_bytes(), b"new")
        self.assertIn("compress/mode=0", Path(str(self.images(first)[0]) + ".import").read_text())
        self.assertNotEqual(self.images(first)[0], old)
        # Once the last battle stops using the old image, shared ownership can remove it.
        self.battle("m1", {"same.png": b"new"})
        share_textures(self.chapter)
        self.assertFalse(old.exists())
        self.assertEqual(self.images(first), self.images(second))

    def test_authored_bytes_and_references_are_preserved_during_cleanup(self):
        first = self.battle("m0", {"same.png": b"old"})
        share_textures(self.chapter)
        old = self.images(first)[0]
        authored = self.chapter / "authored/override.json"
        self.write_json(authored, {"texture": "../generated/shared/same.png", "own": "own.png"})
        (authored.parent / "own.png").write_bytes(b"authored")
        original = authored.read_bytes()
        self.battle("m0", {"same.png": b"new"})
        share_textures(self.chapter)
        self.assertEqual(authored.read_bytes(), original)
        self.assertEqual((authored.parent / "own.png").read_bytes(), b"authored")
        self.assertEqual(old.read_bytes(), b"old")

    def test_dry_run_then_apply_is_idempotent_and_rewrites_absolute_entry(self):
        battle = self.battle("m0", {"map.png": b"map"})
        self.write_json(
            battle / "battle.json", {"mapTexture": "res://content/chapter_1/generated/map.png"}
        )
        self.write_json(
            battle / "provenance.json", {"outputs": ["map.png", "units.json", "battle.json"]}
        )
        before = self.snapshot()
        plan = share_textures(self.chapter, dry_run=True)
        self.assertEqual(self.snapshot(), before)
        self.assertGreater(plan["filesWritten"], 0)
        self.assertEqual(share_textures(self.chapter), plan)
        entry = json.loads((battle / "battle.json").read_text())
        self.assertEqual(entry["mapTexture"], "res://content/chapter_1/generated/shared/map.png")
        self.assertEqual(self.images(battle)[0].read_bytes(), b"map")
        after = self.snapshot()
        self.assertEqual(share_textures(self.chapter)["filesWritten"], 0)
        self.assertEqual(self.snapshot(), after)

    def test_chapter_entry_keeps_its_stable_private_texture_across_imports(self):
        battle = self.battle("m0", {"map.png": b"map", "sprite.png": b"sprite"})
        entry = self.chapter / "chapter.json"
        self.write_json(entry, {"mapTexture": "res://content/chapter_1/generated/map.png"})
        original = entry.read_bytes()
        share_textures(self.chapter)
        self.assertEqual(entry.read_bytes(), original)
        self.assertEqual((battle / "map.png").read_bytes(), b"map")
        self.assertEqual(self.images(battle)[1].read_bytes(), b"sprite")

    def test_outside_ownership_and_unowned_images_fail_before_writing(self):
        battle = self.battle("m0", {"map.png": b"map"})
        (self.generated / "unowned.png").write_bytes(b"unknown")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "Unowned"):
            share_textures(self.chapter)
        self.assertEqual(self.snapshot(), before)
        (self.generated / "unowned.png").unlink()
        self.write_json(battle / "provenance.json", {"outputs": ["../chapter.json"]})
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "outside"):
            share_textures(self.chapter)
        self.assertEqual(self.snapshot(), before)

    def test_publish_restores_nondefault_parameters_and_preserves_other_battles_uid(self):
        first = self.battle("m0", {"same.png": b"old"})
        second = self.battle("m1", {"same.png": b"old"})
        for directory in (first, second):
            (directory / "same.png.import").write_text(
                '[remap]\nimporter="texture"\nuid="uid://original"\n[params]\ncompress/mode=1\n'
            )
        share_textures(self.chapter)
        old = self.images(first)[0]
        result = publish_generated(self.stage({"same.png": b"old"}), first, self.chapter)
        self.assertEqual(result["texturesReused"], 1)
        self.assertEqual(self.images(first)[0], old)
        self.assertIn('uid="uid://original"', Path(str(old) + ".import").read_text())
        publish_generated(self.stage({"same.png": b"new"}), first, self.chapter)
        new = self.images(first)[0]
        self.assertEqual(self.images(second)[0], old)
        self.assertEqual(old.read_bytes(), b"old")
        self.assertEqual(new.read_bytes(), b"new")
        settings = Path(str(new) + ".import").read_text()
        self.assertIn("compress/mode=1", settings)
        self.assertNotIn("uid=", settings)

    def test_publish_rejects_cross_owner_outputs_before_copying_or_deleting(self):
        first = self.battle("m0", {"same.png": b"old"})
        share_textures(self.chapter)
        kept = self.images(first)[0]
        provenance = first / "provenance.json"
        clean = provenance.read_bytes()
        self.write_json(provenance, {"outputs": ["units.json", "shared/same.png"]})
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "another owner"):
            publish_generated(self.stage({"same.png": b"new"}), first, self.chapter)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(kept.read_bytes(), b"old")
        provenance.write_bytes(clean)
        second = self.battle("m1", {"same.png": b"second"})
        incoming = self.stage({"same.png": b"new"})
        self.write_json(incoming / "provenance.json", {"outputs": ["battles/m1/same.png"]})
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "another owner"):
            publish_generated(incoming, first, self.chapter)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((second / "same.png").read_bytes(), b"second")
        for rogue in ("shared/same.png.import", "battles/m1/provenance.json"):
            incoming = self.stage({"same.png": b"new"})
            path = incoming / rogue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"rogue")
            before = self.snapshot()
            with self.assertRaisesRegex(ValueError, "ownership list"):
                publish_generated(incoming, first, self.chapter)
            self.assertEqual(self.snapshot(), before)


if __name__ == "__main__":
    unittest.main()
