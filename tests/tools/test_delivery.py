"""Artifact verification reads identity from the package, rejecting a mismatching manifest."""

import gzip
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from emblem_dev import delivery
from emblem_dev.commands import build
from emblem_dev.commands.build import publish_android, publish_web
from emblem_dev.delivery import verify_apk


class DeliveryTest(unittest.TestCase):
    def test_new_pack_requires_compressed_catalog_but_existing_pack_can_still_be_checked(self):
        with patch.object(delivery, "run") as run:
            delivery.verify_pack(Path("new.pck"), "new", require_compressed_catalog=True)
            self.assertEqual(run.call_args.args[-2:], ("new", "--compressed-catalog"))
            delivery.verify_pack(Path("existing.pck"), "existing")
            self.assertEqual(run.call_args.args[-1], "existing")

    def test_export_does_not_publish_if_presets_change_during_export(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game = root / "game"
            source = game / "content/chapter_1/generated/library/catalog.json"
            source.parent.mkdir(parents=True)
            source.write_text('{"profiles": {}}')
            presets = game / "export_presets.cfg"
            presets.write_text(
                (
                    'include_filter="content/**/*.json,ui/fonts/OFL.txt"\n'
                    'exclude_filter="tests/*,tests/**/*,**/provenance.json"\n'
                )
                * 2
            )

            def command(*args, **_kwargs):
                if args[0] == "godot":
                    presets.write_text("changed by another process")
                return "fixture" if "--short" in args else ""

            with (
                patch.object(build, "ROOT", root),
                patch.object(build, "GAME", game),
                patch.object(build, "INFO", game / "content/build_info.json"),
                patch.object(delivery, "run", side_effect=command),
                patch.object(delivery, "verify_pack"),
                patch.object(build, "publish_web") as publish,
                self.assertRaisesRegex(RuntimeError, "preserving"),
            ):
                build.export("web")
            publish.assert_not_called()
            self.assertEqual(presets.read_text(), "changed by another process")
            self.assertFalse(source.with_name(source.name + ".gz").exists())

    def test_export_catalog_is_compact_verified_and_removed_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            game = Path(directory)
            source = game / "content/chapter_1/generated/library/catalog.json"
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps({"profiles": {"角色": [1, 2, 3]}}, ensure_ascii=False))
            presets = game / "export_presets.cfg"
            original = (
                'include_filter="content/**/*.json,ui/fonts/OFL.txt"\n'
                'exclude_filter="tests/*,tests/**/*,**/provenance.json"\n'
            ) * 2
            presets.write_text(original)
            compressed = source.with_name(source.name + ".gz")
            with patch.object(build, "GAME", game):
                with self.assertRaisesRegex(RuntimeError, "fixture"):
                    with build.compressed_catalog() as data:
                        self.assertEqual(
                            json.loads(gzip.decompress(data)), json.loads(source.read_text())
                        )
                        self.assertEqual(compressed.read_bytes(), data)
                        self.assertIn("content/**/*.json.gz", presets.read_text())
                        raise RuntimeError("fixture")
                self.assertFalse(compressed.exists())
                self.assertEqual(presets.read_text(), original)
                compressed.write_bytes(b"existing")
                with self.assertRaises(FileExistsError), build.compressed_catalog():
                    pass
                self.assertEqual(compressed.read_bytes(), b"existing")
                compressed.unlink()
                with self.assertRaisesRegex(RuntimeError, "preserving"):
                    with build.compressed_catalog():
                        presets.write_text("changed by another process")
                self.assertEqual(presets.read_text(), "changed by another process")
                self.assertFalse(compressed.exists())

    def test_android_verification_uses_package_identity_even_with_stale_sidecar(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "build/android"
            destination.mkdir(parents=True)
            apk = destination / "emblem-rekindled.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("assets/content/build_info.json", '{"buildId":"committed"}')
            (destination / "build-info.json").write_text('{"buildId":"interrupted"}')

            def adb(*args):
                if args[:3] == ("shell", "pm", "path"):
                    return b"package:/installed/base.apk\n"
                if args[0] == "pull":
                    build.shutil.copy2(apk, args[2])
                return b""

            with (
                patch.object(delivery, "ROOT", root),
                patch("emblem_dev.qa.client.Playtest") as client,
            ):
                client.return_value.adb.side_effect = adb
                delivery.verify_android()

    def test_android_publication_preserves_previous_pair_on_failures(self):
        for failure in ("copy", "metadata", "commit"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source, destination = root / "new.apk", root / "published"
                source.write_bytes(b"new package")
                destination.mkdir()
                apk = destination / "emblem-rekindled.apk"
                metadata = destination / "build-info.json"
                apk.write_bytes(b"old package")
                metadata.write_bytes(b'{"buildId":"old"}\n')
                original_write = Path.write_text
                original_replace = Path.replace

                def write(
                    path, *args, destination=destination, original_write=original_write, **kwargs
                ):
                    if path.name == "build-info.json" and path.parent != destination:
                        raise OSError("metadata failed")
                    return original_write(path, *args, **kwargs)

                def replace(path, target, apk=apk, original_replace=original_replace):
                    if Path(target) == apk:
                        raise OSError("commit failed")
                    return original_replace(path, target)

                def copy(_source, target):
                    Path(target).write_bytes(b"partial")
                    raise OSError("copy failed")

                patches = {
                    "copy": patch.object(build.shutil, "copy2", side_effect=copy),
                    "metadata": patch.object(Path, "write_text", write),
                    "commit": patch.object(Path, "replace", replace),
                }
                with patches[failure], self.assertRaisesRegex(OSError, failure):
                    publish_android(source, destination, {"buildId": "new"})
                self.assertEqual(apk.read_bytes(), b"old package")
                self.assertEqual(metadata.read_bytes(), b'{"buildId":"old"}\n')

    def test_android_publication_commits_complete_package_and_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, destination = root / "new.apk", root / "published"
            destination.mkdir()
            source.write_bytes(b"new package")
            identity = {"buildId": "new"}
            publish_android(source, destination, identity)
            self.assertEqual((destination / "emblem-rekindled.apk").read_bytes(), b"new package")
            self.assertEqual(json.loads((destination / "build-info.json").read_text()), identity)

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

    def test_template_digest_and_version_fail_before_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tpz = root / "templates.tpz"
            with zipfile.ZipFile(tpz, "w") as archive:
                archive.writestr("templates/version.txt", "wrong-version")
            with patch.object(build, "ROOT", root):
                with self.assertRaisesRegex(ValueError, "SHA-256"):
                    build.prepare_templates(tpz)
                self.assertFalse((root / "build").exists())
                with patch.object(build.hashlib, "file_digest") as digest:
                    digest.return_value.hexdigest.return_value = build.TEMPLATE_SHA
                    with self.assertRaisesRegex(ValueError, "version"):
                        build.prepare_templates(tpz)
                self.assertFalse((root / "build").exists())

    def test_template_selection_uses_native_function(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tpz = root / "templates.tpz"
            with zipfile.ZipFile(tpz, "w") as archive:
                for name in build.FILES:
                    archive.writestr(
                        "templates/" + name, "4.7.2.stable" if name == "version.txt" else name
                    )
                archive.writestr("templates/unselected", "ignored")
            with patch.object(build, "ROOT", root):
                with patch.object(build.hashlib, "file_digest") as digest:
                    digest.return_value.hexdigest.return_value = build.TEMPLATE_SHA
                    build.prepare_templates(tpz)
            target = root / "build/templates/4.7.2.stable"
            self.assertEqual({p.name for p in target.iterdir()}, set(build.FILES))

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
