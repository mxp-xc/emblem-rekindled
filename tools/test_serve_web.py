"""Keep a fixed local preview URL fresh without clearing saved game data."""

import tempfile
import threading
import unittest
from functools import partial
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from pathlib import Path

from serve_web import WebPreviewHandler


class WebPreviewTest(unittest.TestCase):
    def test_export_refresh_uses_cache_only_clearing(self) -> None:
        with tempfile.TemporaryDirectory(prefix="emblem-web-preview-") as directory:
            root = Path(directory)
            root.joinpath("index.html").write_text("<canvas></canvas>")
            pack = root / "index.pck"
            pack.write_bytes(b"old game")
            handler = partial(WebPreviewHandler, directory=directory)
            with ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                connection = HTTPConnection(*server.server_address, timeout=5)
                try:
                    for path in ("/", "/index.html"):
                        connection.request("GET", path)
                        response = connection.getresponse()
                        self.assertEqual(response.status, 200)
                        self.assertEqual(response.getheader("Cache-Control"), "no-store")
                        # Never send "storage", "cookies" or "*": IDBFS holds real saves.
                        self.assertEqual(response.getheader("Clear-Site-Data"), '"cache"')
                        response.read()
                    for content in (b"old game", b"updated game"):
                        pack.write_bytes(content)
                        connection.request("GET", "/index.pck")
                        response = connection.getresponse()
                        self.assertEqual(response.status, 200)
                        self.assertEqual(response.getheader("Cache-Control"), "no-store")
                        self.assertIsNone(response.getheader("Clear-Site-Data"))
                        self.assertEqual(response.read(), content)
                finally:
                    connection.close()
                    server.shutdown()
                    thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
