"""Exercise the evidence bridge without sockets or user storage."""

import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from chapter_qa_bridge import Handler


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)

    def handler(self, path, value, *, origin="http://127.0.0.1:1234"):
        handler = Handler.__new__(Handler)
        raw = json.dumps(value).encode()
        handler.path = path
        handler.headers = {"Origin": origin, "Content-Length": str(len(raw))}
        handler.server = SimpleNamespace(output=self.output, origin="http://127.0.0.1:1234")
        handler.rfile, handler.wfile = io.BytesIO(raw), io.BytesIO()
        handler.status = None
        handler.respond_headers = lambda status, *args: setattr(handler, "status", status)
        return handler

    def post(self, handler):
        # Suppress expected fixture errors; assertions concern files and responses.
        with patch("chapter_qa_bridge.logging.exception"):
            handler.do_POST()
        return handler.status

    def test_wrong_origin_and_invalid_paths_never_write(self):
        self.assertEqual(
            self.post(self.handler("/backup.json", {}, origin="http://evil.test")), 400
        )
        self.assertEqual(self.post(self.handler("/../escape.json", {})), 400)
        self.assertEqual(list(self.output.iterdir()), [])

    def test_fresh_backup_readback_and_overwrite_protection(self):
        value = {"complete": True, "databases": []}
        self.assertEqual(self.post(self.handler("/backup.json", value)), 200)
        self.assertEqual(self.post(self.handler("/backup.json", {"changed": True})), 400)
        handler = self.handler("/backup.json", {})
        handler.do_GET()
        self.assertEqual(handler.status, 200)
        self.assertEqual(json.loads(handler.wfile.getvalue()), value)

    def test_failed_readback_never_acknowledges_verified_backup(self):
        handler = self.handler("/backup.json", {"complete": True})
        with patch.object(Path, "read_text", side_effect=OSError("readback failed")):
            self.assertEqual(self.post(handler), 400)
        self.assertNotIn("verified", json.loads(handler.wfile.getvalue()))
        # Retain the file for diagnosis; the failed backup cannot be overwritten.
        self.assertTrue((self.output / "backup.json").exists())
        self.assertEqual(self.post(self.handler("/backup.json", {})), 400)

    def test_storage_modules_resolve_from_tools(self):
        for path in ("/chapter_storage_api.js", "/chapter_storage_codec.js"):
            handler = self.handler(path, {})
            handler.do_GET()
            self.assertEqual(handler.status, 200)
            self.assertTrue(handler.wfile.getvalue())


if __name__ == "__main__":
    unittest.main()
