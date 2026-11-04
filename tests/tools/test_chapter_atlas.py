"""Atlas conversion preserves individual source pixels and import settings."""

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from emblem_dev.content.assets import texture_sources
from emblem_dev.content.atlas import extract_texture, pack_chapter, unpack_chapter
from PIL import Image


class ChapterAtlasTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.chapter = Path(self.temporary.name) / "game/content/chapter_1"
        shared = self.chapter / "generated/shared"
        shared.mkdir(parents=True)
        self.sidecar = (
            '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\ncompress/mode=0\n'
        )
        self.pixels = {}
        for name, color in [("one.png", (10, 20, 30, 0)), ("two.png", (40, 50, 60, 128))]:
            path = shared / name
            image = Image.new("RGBA", (3, 2), color)
            image.save(path)
            Path(str(path) + ".import").write_text(self.sidecar)
            self.pixels[name] = image.tobytes()
        (shared / "provenance.json").write_text(
            json.dumps(
                {"outputs": list(self.pixels), "textureImportParameters": {"compress/mode": "0"}}
            )
        )

    def test_round_trip_preserves_pixels_and_sidecar_and_is_reproducible(self):
        pack_chapter(self.chapter)
        atlas = self.chapter / "generated/atlas"
        self.assertEqual(len(list(atlas.glob("*.png"))), 1)
        self.assertIn(
            "process/fix_alpha_border=false",
            next(atlas.glob("*.png.import")).read_text(),
        )
        self.assertFalse(list((self.chapter / "generated/shared").glob("*.png")))
        before = {p.name: p.read_bytes() for p in atlas.iterdir() if p.is_file()}
        unpack_chapter(self.chapter)
        for name, pixels in self.pixels.items():
            path = self.chapter / "generated/shared" / name
            with Image.open(path) as image:
                self.assertEqual(image.convert("RGBA").tobytes(), pixels)
            self.assertEqual(Path(str(path) + ".import").read_text(), self.sidecar)
        pack_chapter(self.chapter)
        self.assertEqual({p.name: p.read_bytes() for p in atlas.iterdir() if p.is_file()}, before)

    def test_invalid_atlas_cannot_delete_or_partially_restore_resources(self):
        pack_chapter(self.chapter)
        atlas = self.chapter / "generated/atlas"
        image = next(atlas.glob("*.png"))
        image.write_bytes(b"not a PNG")
        before = {
            p.relative_to(self.chapter): p.read_bytes()
            for p in self.chapter.rglob("*")
            if p.is_file()
        }
        with self.assertRaises(ValueError):
            unpack_chapter(self.chapter)
        after = {
            p.relative_to(self.chapter): p.read_bytes()
            for p in self.chapter.rglob("*")
            if p.is_file()
        }
        self.assertEqual(after, before)

    def test_extract_texture_preserves_pixels_and_will_not_overwrite(self):
        pack_chapter(self.chapter)
        target = Path(self.temporary.name) / "edit.png"
        logical = "res://content/chapter_1/generated/shared/one.png"
        extract_texture(self.chapter, logical, target)
        with Image.open(target) as image:
            self.assertEqual(image.convert("RGBA").tobytes(), self.pixels["one.png"])
        before = target.read_bytes()
        with self.assertRaises(FileExistsError):
            extract_texture(self.chapter, logical, target)
        self.assertEqual(target.read_bytes(), before)

    def test_changed_and_new_textures_can_be_repacked_without_losing_other_sources(self):
        pack_chapter(self.chapter)
        unpack_chapter(self.chapter)
        shared = self.chapter / "generated/shared"
        changed = Image.new("RGBA", (3, 2), (100, 110, 120, 255))
        changed.save(shared / "one.png")
        added = Image.new("RGBA", (2, 3), (8, 7, 6, 255))
        added.save(shared / "three.png")
        provenance = json.loads((shared / "provenance.json").read_text())
        provenance["outputs"].append("three.png")
        (shared / "provenance.json").write_text(json.dumps(provenance))

        pack_chapter(self.chapter)
        unpack_chapter(self.chapter)

        for name, expected in [
            ("one.png", changed.tobytes()),
            ("two.png", self.pixels["two.png"]),
            ("three.png", added.tobytes()),
        ]:
            with Image.open(shared / name) as actual:
                self.assertEqual(actual.convert("RGBA").tobytes(), expected)

    def test_unsupported_import_settings_do_not_modify_source_images(self):
        sidecar = self.chapter / "generated/shared/one.png.import"
        sidecar.write_text(self.sidecar + "mipmaps/generate=true\n")
        before = {
            path.relative_to(self.chapter): path.read_bytes()
            for path in self.chapter.rglob("*")
            if path.is_file()
        }
        with self.assertRaisesRegex(ValueError, "Unsupported atlas import settings"):
            pack_chapter(self.chapter)
        after = {
            path.relative_to(self.chapter): path.read_bytes()
            for path in self.chapter.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)

    def test_write_failure_restores_inputs_and_allows_retry(self):
        before = {
            path.relative_to(self.chapter): path.read_bytes()
            for path in self.chapter.rglob("*")
            if path.is_file()
        }
        original = Path.write_bytes
        failed = False

        def fail_once(path, data):
            nonlocal failed
            if path.name == "atlas_000.png.import" and not failed:
                failed = True
                raise OSError("controlled write failure")
            return original(path, data)

        with patch.object(Path, "write_bytes", fail_once), self.assertRaises(OSError):
            pack_chapter(self.chapter)
        after = {
            path.relative_to(self.chapter): path.read_bytes()
            for path in self.chapter.rglob("*")
            if path.is_file()
        }
        self.assertEqual(after, before)
        self.assertEqual(pack_chapter(self.chapter)["textures"], 2)


class ChapterResourceBudgetTest(unittest.TestCase):
    def test_chapter_resource_files_do_not_exceed_original_pak_entries(self):
        chapter = Path(__file__).resolve().parents[2] / "game/content/chapter_1"
        files = [path for path in chapter.rglob("*") if path.is_file()]
        self.assertLessEqual(len(files), 402, f"Chapter contains {len(files)} resource files")

    def test_game_assets_including_fixtures_stay_within_original_pak_entries(self):
        game = Path(__file__).resolve().parents[2] / "game"
        source_suffixes = {".gd", ".uid", ".godot", ".cfg"}
        files = []
        for directory, children, names in os.walk(game):
            children[:] = [name for name in children if name != ".godot"]
            files.extend(
                Path(directory) / name for name in names if Path(name).suffix not in source_suffixes
            )
        self.assertLessEqual(len(files), 402, f"Game contains {len(files)} asset files")

    def test_live_texture_references_and_source_targets_are_resolvable(self):
        game = Path(__file__).resolve().parents[2] / "game"
        chapter = game / "content/chapter_1"
        atlas = json.loads((chapter / "generated/atlas/manifest.json").read_text())["textures"]
        referenced = set()
        missing_references = set()

        def collect(value, directory):
            if isinstance(value, dict):
                for child in value.values():
                    collect(child, directory)
            elif isinstance(value, list):
                for child in value:
                    collect(child, directory)
            elif isinstance(value, str) and value.endswith(".png"):
                path = game / value[6:] if value.startswith("res://") else directory / value
                referenced.add(path.resolve())
                if value.startswith("res://") and not path.is_file() and value not in atlas:
                    missing_references.add(value)

        for manifest in chapter.rglob("*.json"):
            if manifest.name == "provenance.json" or manifest.parent.name == "atlas":
                continue
            collect(json.loads(manifest.read_text()), manifest.parent)

        missing = []
        stale = []
        for metadata_path in (chapter / "generated").rglob("provenance.json"):
            sources = texture_sources(json.loads(metadata_path.read_text()))
            for target in sources.values():
                path = (chapter / target).resolve()
                logical = "res://" + path.relative_to(game).as_posix()
                if not path.is_file() and logical not in atlas:
                    missing.append(logical)
                if path not in referenced:
                    stale.append(logical)
        self.assertFalse(
            missing_references, f"Missing live textures: {sorted(missing_references)[:5]}"
        )
        self.assertFalse(missing, f"Unresolved source targets: {missing[:5]}")
        self.assertFalse(stale, f"Unreferenced source targets: {stale[:5]}")
