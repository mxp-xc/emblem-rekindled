import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from emblem_dev.font_subset import FONT, generate, missing_codepoints, required_codepoints
from fontTools.ttLib import TTFont


class FontSubsetTests(unittest.TestCase):
    def test_game_text_and_gb2312_are_covered(self):
        self.assertEqual(missing_codepoints(), set())

    def test_escaped_json_text_is_collected(self):
        with tempfile.TemporaryDirectory() as directory:
            game = Path(directory)
            (game / "content.json").write_text(json.dumps({"name": "䶮"}), encoding="utf-8")
            (game / "script.gd").write_text('var label = "\\u4d18"', encoding="utf-8")
            self.assertIn(ord("䶮"), required_codepoints(game))
            self.assertIn(0x4D18, required_codepoints(game))
            self.assertIn(0x4D18, missing_codepoints(game=game))

    def test_generated_woff2_covers_required_text(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "subset.woff2"
            with patch("emblem_dev.font_subset.required_codepoints", return_value={65, 0x4E2D}):
                generate(FONT, target)
                self.assertEqual(missing_codepoints(target), set())
            with TTFont(target) as font:
                self.assertEqual(font.flavor, "woff2")


if __name__ == "__main__":
    unittest.main()
