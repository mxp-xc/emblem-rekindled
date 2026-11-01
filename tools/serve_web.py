"""Serve the local Godot export at a stable URL without retaining stale game packs."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class WebPreviewHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    directory = ROOT / "build" / "web"
    if not (directory / "index.html").is_file():
        parser.error("Web export missing; run godot --headless --path game --export-debug Web")
    handler = partial(WebPreviewHandler, directory=str(directory))
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Game preview: http://127.0.0.1:{args.port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            # Ctrl-C is the ordinary local-server shutdown path.
            pass


if __name__ == "__main__":
    main()
