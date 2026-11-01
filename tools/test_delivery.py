"""Artifact verification reads identity from the package, rejecting a mismatching manifest."""

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from delivery import publish_web, verify_apk


class DeliveryTest(unittest.TestCase):
    def test_web_builds_have_distinct_asset_urls_and_keep_running_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, destination = root / "export", root / "published"
            source.mkdir()
            destination.mkdir()
            markup = '<html><head><script src="index.js"></script></head><body></body></html>'
            (source / "index.html").write_text(markup)
            for build_id in ("build-a", "build-b"):
                for name in ("index.js", "index.wasm", "index.pck", "index.audio.worklet.js"):
                    (source / name).write_text(build_id + ":" + name)
                publish_web(source, destination, build_id)
                entry = (destination / "index.html").read_text()
                self.assertIn(f'<base href="./{build_id}/">', entry)
                self.assertIn('src="index.js"', entry)
                for name in ("index.js", "index.wasm", "index.pck", "index.audio.worklet.js"):
                    self.assertEqual(
                        (destination / build_id / name).read_text(), build_id + ":" + name
                    )
            self.assertEqual((destination / "build-a/index.pck").read_text(), "build-a:index.pck")

    def test_invalid_web_entry_keeps_the_current_published_page(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, destination = root / "export", root / "published"
            source.mkdir()
            destination.mkdir()
            (source / "index.html").write_text("invalid")
            (destination / "index.html").write_text("current")
            with self.assertRaisesRegex(RuntimeError, "one head"):
                publish_web(source, destination, "new")
            self.assertEqual((destination / "index.html").read_text(), "current")

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
