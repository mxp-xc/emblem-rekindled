"""Texture publication keeps nearest-owner and containment validation intact."""

import json
import tempfile
import unittest
from pathlib import Path

from emblem_dev.content.assets import owned_output_paths, share_textures


class AdaptiveResourceOwnershipTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.chapter = self.root / "game/content/chapter_1"
        self.generated = self.chapter / "generated"
        self.shared = self.generated / "shared"
        self.shared.mkdir(parents=True)
        self.write_json(
            self.shared / "provenance.json",
            {"outputs": [], "textureImportParameters": {"compress/mode": "0"}},
        )

    def write_json(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def test_nested_output_uses_nearest_owner_and_keeps_parent_owner(self):
        parent = self.generated / "battles/m1"
        child = parent / "nested"
        child.mkdir(parents=True)
        (parent / "parent.png").write_bytes(b"parent")
        (child / "child.png").write_bytes(b"child")
        self.write_json(parent / "provenance.json", {"outputs": ["parent.png"]})
        self.write_json(child / "provenance.json", {"outputs": ["child.png"]})
        share_textures(self.chapter, dry_run=True)
        self.assertTrue((parent / "parent.png").exists())
        self.assertTrue((child / "child.png").exists())

    def test_unowned_texture_is_rejected(self):
        (self.generated / "orphan.png").write_bytes(b"orphan")
        with self.assertRaisesRegex(ValueError, "Unowned generated texture"):
            share_textures(self.chapter, dry_run=True)

    def test_parent_cannot_claim_nested_owner_output(self):
        parent = self.generated / "battle"
        child = parent / "nested"
        child.mkdir(parents=True)
        (child / "child.png").write_bytes(b"child")
        self.write_json(parent / "provenance.json", {"outputs": ["nested/child.png"]})
        self.write_json(child / "provenance.json", {"outputs": ["child.png"]})
        with self.assertRaisesRegex(ValueError, "another owner"):
            share_textures(self.chapter, dry_run=True)

    def test_parent_traversal_and_symlink_escape_are_rejected(self):
        owned = self.generated / "owner"
        owned.mkdir()
        outside = self.root / "outside.png"
        outside.write_bytes(b"outside")
        (owned / "link.png").symlink_to(outside)
        for path in ("../../../../outside.png", "link.png"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "outside"):
                owned_output_paths(owned, [path])


if __name__ == "__main__":
    unittest.main()
