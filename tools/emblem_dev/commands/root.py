"""独立的顶层开发命令。"""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Annotated

import typer

from emblem_dev import workspace
from emblem_dev.paths import ROOT

app = typer.Typer(help="独立的顶层开发命令。")


class WebPreviewHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def fragments(text: str, needle: str, *, radius: int = 160, limit: int = 5) -> list[str]:
    if not needle or not 0 <= radius <= 500 or not 1 <= limit <= 20 or len(needle) > 200:
        raise ValueError("Use a nonempty needle (<=200 chars), radius 0..500 and limit 1..20")
    result = []
    cursor = 0
    while len(result) < limit:
        offset = text.find(needle, cursor)
        if offset < 0:
            break
        start, end = max(0, offset - radius), min(len(text), offset + len(needle) + radius)
        result.append(f"offset {offset}: " + text[start:end].replace("\n", "\\n"))
        cursor = offset + len(needle)
    return result


@app.command()
def setup(hooks: Annotated[bool, typer.Option(help="显式启用仓库 hooks")] = False) -> None:
    """安装本 checkout 的锁定依赖。"""
    workspace.setup(hooks=hooks)


@app.command("serve")
def serve_web(port: int = 8765) -> None:
    """在本机提供本 checkout 的 Web 导出。"""
    directory = ROOT / "build" / "web"
    if not (directory / "index.html").is_file():
        raise ValueError("Web export missing; run er build web")
    handler = partial(WebPreviewHandler, directory=str(directory))
    with ThreadingHTTPServer(("127.0.0.1", port), handler) as server:
        print(f"Game preview: http://127.0.0.1:{port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            # Ctrl-C is the ordinary local-server shutdown path.
            pass


@app.command("source-context")
def show_source(file: Path, needle: str, radius: int = 160, limit: int = 5) -> None:
    """按字符范围读取生成源码的有限上下文。"""
    for fragment in fragments(file.read_text(), needle, radius=radius, limit=limit):
        print(fragment)
