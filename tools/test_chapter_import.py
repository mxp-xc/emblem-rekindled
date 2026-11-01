"""Reimport keeps static deployment contracts and inherited texture locations."""

import tempfile
import unittest
from pathlib import Path

from chapter_1_definitions import _spawn_definitions
from import_chapter_1 import rebase_textures


class ChapterImportTest(unittest.TestCase):
    def test_rebase_changes_existing_texture_paths_without_changing_source_labels(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory) / "story", Path(directory) / "battles/m1/story"
            (source / "images").mkdir(parents=True)
            (source / "images/splash.png").write_bytes(b"source")
            definition = {
                "images": [
                    {"texture": "images/splash.png", "source": "splash.png", "offsetX": -12}
                ],
                "world": "res://content/world.png",
            }
            result = rebase_textures(definition, source, target)
            image = result["images"][0]
            self.assertEqual(
                (target / image["texture"]).resolve(), (source / "images/splash.png").resolve()
            )
            self.assertEqual(image["source"], "splash.png")
            self.assertEqual(image["offsetX"], -12)
            self.assertEqual(result["world"], definition["world"])

    def test_only_later_battles_expose_deployment_slots_for_inheritance(self):
        def deployment(battle):
            records = []
            for source_id in range(27) if battle == 0 else range(10, 36):
                records += [1, 0, source_id, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1]
            for slot in range(1, 6) if battle == 0 else range(6):
                records += [1, 0, slot, 1, 0, 0, 0, 32, 0, 0, 0, 0, 0, 0, 1, 1]
            return bytes([32, *records])

        first = _spawn_definitions(deployment(0), 0)
        second = _spawn_definitions(deployment(1), 1)
        self.assertFalse(any("deploymentSlot" in spawn for spawn in first))
        inherited = [spawn["id"] for spawn in second if spawn["formal"]]
        self.assertEqual(inherited, [0, 9])
        self.assertTrue(all("deploymentSlot" in spawn for spawn in second if spawn["formal"]))


if __name__ == "__main__":
    unittest.main()
