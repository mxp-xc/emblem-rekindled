"""Loopback-only transfer for this QA batch's complete IndexedDB backups and evidence."""

import argparse
import json
import logging
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent


class Handler(BaseHTTPRequestHandler):
    def respond_headers(self, status: int, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Access-Control-Allow-Origin", self.server.origin)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Type", content_type)
        self.end_headers()

    def do_OPTIONS(self) -> None:
        self.respond_headers(204)

    def filename(self) -> Path:
        if not re.fullmatch(r"/[A-Za-z0-9_-]+\.json", self.path):
            raise ValueError("Invalid evidence filename")
        return self.server.output / self.path[1:]

    def do_GET(self) -> None:
        try:
            if self.path in ("/chapter_storage_codec.js", "/chapter_storage_api.js"):
                module = (
                    "chapter_storage_codec.js" if "codec" in self.path else "chapter_storage_api.js"
                )
                data = (ROOT / module).read_bytes()
                self.respond_headers(200, "text/javascript")
                self.wfile.write(data)
                return
            data = self.filename().read_bytes()
            self.respond_headers(200)
            self.wfile.write(data)
        except Exception as error:
            logging.exception("QA evidence transfer failed")
            self.respond_headers(400)
            self.wfile.write(json.dumps({"error": str(error)}).encode())

    def do_POST(self) -> None:
        try:
            if self.headers.get("Origin") != self.server.origin:
                raise ValueError("Unexpected origin")
            path = self.filename()
            size = int(self.headers["Content-Length"])
            if not 0 < size <= 30_000_000:
                raise ValueError("Unexpected evidence size")
            value = json.loads(self.rfile.read(size))
            # Exclusive creation protects a retained backup even across overlapping requests.
            with path.open("x" if path.name == "backup.json" else "w") as output:
                output.write(json.dumps(value, ensure_ascii=False))
            if json.loads(path.read_text()) != value:
                raise ValueError("Persisted evidence verification failed")
            self.respond_headers(200)
            self.wfile.write(json.dumps({"saved": path.name, "verified": True}).encode())
        except Exception as error:
            logging.exception("QA evidence transfer failed")
            self.respond_headers(400)
            self.wfile.write(json.dumps({"error": str(error)}).encode())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--origin", required=True)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"http://127\.0\.0\.1:[0-9]+", args.origin):
        parser.error("Explicit loopback game origin required")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with HTTPServer(("127.0.0.1", args.port), Handler) as server:
        server.origin, server.output = args.origin, output
        print(f"QA evidence bridge: 127.0.0.1:{args.port} -> {output}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
