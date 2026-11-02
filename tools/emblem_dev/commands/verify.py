"""核对服务或已安装包。"""

import json
import shutil
import tempfile
from pathlib import Path
from urllib.request import urlopen

import typer

from emblem_dev import delivery
from emblem_dev.paths import ROOT

app = typer.Typer(help="核对服务或已安装包。")


@app.command("web")
def verify_web(origin: str = "http://127.0.0.1:8765") -> None:
    expected = json.loads((ROOT / "build/web/build-info.json").read_text())["buildId"]
    with tempfile.TemporaryDirectory(prefix="emblem-served-pack-") as directory:
        for resource in ("", expected + "/index.pck"):
            with urlopen(origin.rstrip("/") + "/" + resource, timeout=30) as response:
                if response.headers.get("Cache-Control") != "no-store":
                    raise RuntimeError("Preview server must disable HTTP caching")
                if response.headers.get("Clear-Site-Data") is not None:
                    raise RuntimeError("Preview navigation must not clear browser data")
                if not resource:
                    markup = response.read().decode()
                    if f'<base href="./{expected}/">' not in markup:
                        raise RuntimeError(
                            "Served HTML does not point at the expected build assets"
                        )
                if resource:
                    pack = Path(directory) / "index.pck"
                    with pack.open("wb") as output:
                        shutil.copyfileobj(response, output)
                    delivery.verify_pack(pack, expected)
    print(f"PASS served PCK {expected}; browser runtime still requires canvas dataset check")


@app.command("android")
def verify_android(serial: str | None = None, apk: Path | None = None) -> None:
    delivery.verify_android(serial=serial, apk=apk)
