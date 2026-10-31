"""Artifact verification reads identity from the package, rejecting a mismatching manifest."""

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from delivery import verify_apk


class DeliveryTest(unittest.TestCase):
    def test_identity_is_read_from_apk(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "game.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("assets/content/build_info.json", json.dumps({"buildId": "new"}))
            verify_apk(apk, "new")
            with self.assertRaisesRegex(RuntimeError, "mismatch"):
                verify_apk(apk, "old")


if __name__ == "__main__":
    unittest.main()
