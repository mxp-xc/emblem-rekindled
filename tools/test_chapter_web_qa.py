"""Run Node-compatible JS fixture assertions as part of the standard tools suite."""

import subprocess
import unittest
from pathlib import Path


class ChapterWebQaTest(unittest.TestCase):
    def test_shared_web_contracts(self):
        result = subprocess.run(
            ["rtk", "bun", str(Path(__file__).with_suffix(".mjs"))],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
