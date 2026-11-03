"""导出带 buildId 的资源包。"""

import gzip
import hashlib
import json
import shutil
import tempfile
import uuid
import zipfile
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import typer

from emblem_dev import delivery
from emblem_dev.paths import GAME, ROOT

app = typer.Typer(help="导出带 buildId 的资源包。")

INFO = GAME / "content/build_info.json"


@contextmanager
def compressed_catalog():
    """Generate a compact export-only catalog without replacing checkout data."""
    source = GAME / "content/chapter_1/generated/library/catalog.json"
    target = source.with_name(source.name + ".gz")
    presets = GAME / "export_presets.cfg"
    original_presets = presets.read_bytes()
    include = b'include_filter="content/**/*.json,ui/fonts/OFL.txt"'
    exclude = b'exclude_filter="tests/*,tests/**/*,**/provenance.json"'
    if original_presets.count(include) != 2 or original_presets.count(exclude) != 2:
        raise ValueError("Export presets do not match the expected catalog filters")
    temporary_presets = original_presets.replace(
        include, b'include_filter="content/**/*.json,content/**/*.json.gz,ui/fonts/OFL.txt"'
    ).replace(
        exclude,
        b'exclude_filter="tests/*,tests/**/*,**/provenance.json,**/generated/library/catalog.json"',
    )
    value = json.loads(source.read_text())
    compact = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    compressed = gzip.compress(compact, mtime=0)
    if gzip.decompress(compressed) != compact:
        raise ValueError("Compressed catalog differs from the source")
    del value, compact
    with target.open("xb") as output:
        output.write(compressed)
    try:
        if presets.read_bytes() != original_presets:
            raise RuntimeError("Export presets changed during preparation")
        presets.write_bytes(temporary_presets)
        yield compressed
    finally:
        current = presets.read_bytes()
        preset_changed = current not in (temporary_presets, original_presets)
        if current == temporary_presets:
            presets.write_bytes(original_presets)
        if target.read_bytes() != compressed:
            raise RuntimeError(f"Export catalog changed; preserving it: {target}")
        target.unlink()
        if preset_changed:
            raise RuntimeError(f"Export presets changed; preserving them: {presets}")


def export(platform: str) -> dict:
    if platform not in ("web", "android"):
        raise ValueError(f"Unsupported export platform: {platform}")
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    identity = {
        "buildId": now.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8],
        "builtAt": now.strftime("%Y-%m-%d %H:%M:%S"),
        "revision": delivery.run("git", "-C", str(ROOT), "rev-parse", "--short", "HEAD").strip(),
        "dirty": bool(delivery.run("git", "-C", str(ROOT), "status", "--porcelain").strip()),
    }
    previous = INFO.read_bytes() if INFO.exists() else None
    try:
        INFO.write_text(json.dumps(identity, ensure_ascii=False, indent=2) + "\n")
        with tempfile.TemporaryDirectory(prefix="emblem-export-") as directory:
            filename = "index.html" if platform == "web" else "emblem-rekindled.apk"
            output = Path(directory) / filename
            with compressed_catalog() as catalog:
                print(f"[EXPORT] {platform} {identity['buildId']}", flush=True)
                delivery.run(
                    "godot",
                    "--headless",
                    "--path",
                    str(GAME),
                    "--export-debug",
                    "Web" if platform == "web" else "Android",
                    str(output),
                )
                if platform == "web":
                    delivery.verify_pack(
                        output.with_suffix(".pck"),
                        identity["buildId"],
                        require_compressed_catalog=True,
                    )
                else:
                    delivery.verify_apk(output, identity["buildId"])
                    with zipfile.ZipFile(output) as archive:
                        packed = archive.read(
                            "assets/content/chapter_1/generated/library/catalog.json.gz"
                        )
                        if packed != catalog:
                            raise RuntimeError("APK compressed catalog differs from the source")
            destination = ROOT / "build" / platform
            destination.mkdir(parents=True, exist_ok=True)
            if platform == "web":
                publish_web(Path(directory), destination, identity["buildId"])
                (destination / "build-info.json").write_text(json.dumps(identity, indent=2) + "\n")
            else:
                publish_android(output, destination, identity)
    finally:
        if previous is None:
            INFO.unlink(missing_ok=True)
        else:
            INFO.write_bytes(previous)
    return identity


def publish_android(source: Path, destination: Path, identity: dict) -> None:
    """Prepare both files before publication; the stable APK is the commit point.

    A failed commit restores the old metadata. After an uncatchable interruption,
    package identity remains authoritative rather than the advisory sidecar.
    """
    metadata = destination / "build-info.json"
    with tempfile.TemporaryDirectory(prefix=".android-publish-", dir=destination) as directory:
        staged = Path(directory)
        shutil.copy2(source, staged / "emblem-rekindled.apk")
        (staged / "build-info.json").write_text(json.dumps(identity, indent=2) + "\n")
        old_metadata = staged / "previous-info.json"
        if metadata.exists():
            old_metadata.write_bytes(metadata.read_bytes())
        (staged / "build-info.json").replace(metadata)
        try:
            (staged / "emblem-rekindled.apk").replace(destination / "emblem-rekindled.apk")
        except BaseException:
            if old_metadata.exists():
                old_metadata.replace(metadata)
            else:
                metadata.unlink()
            raise


def publish_web(source: Path, destination: Path, build_id: str) -> None:
    markup = (source / "index.html").read_text()
    if markup.count("<head>") != 1 or "<base " in markup:
        raise RuntimeError("Godot export must have one head and no existing asset base")
    # The stable entry points at a new asset URL for every build, including WASM/PCK/worklets.
    # Previous directories stay available to pages that are already running.
    assets = destination / build_id
    assets.mkdir(exist_ok=False)
    for file in source.iterdir():
        shutil.copy2(file, assets / file.name)
    markup = markup.replace("<head>", f'<head>\n\t\t<base href="./{build_id}/">', 1)
    temporary = destination / "index.html.tmp"
    temporary.write_text(markup)
    temporary.replace(destination / "index.html")


@app.command("web")
def build_web() -> None:
    export("web")


@app.command("android")
def build_android() -> None:
    export("android")


TEMPLATE_SHA = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
FILES = (
    "android_debug.apk",
    "android_release.apk",
    "web_nothreads_debug.zip",
    "web_nothreads_release.zip",
    "icudt_godot.dat",
    "version.txt",
)


@app.command("templates")
def prepare_templates(tpz: Path) -> None:
    """从已有 Godot 模板归档安装导出模板。"""
    with tpz.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != TEMPLATE_SHA:
            raise ValueError("Godot template SHA-256 mismatch")
    target = ROOT / "build/templates/4.7.2.stable"
    with zipfile.ZipFile(tpz) as archive:
        if archive.read("templates/version.txt").strip() != b"4.7.2.stable":
            raise ValueError("Godot template version mismatch")
        target.mkdir(parents=True, exist_ok=True)
        for name in FILES:
            (target / name).write_bytes(archive.read("templates/" + name))
    print(f"Prepared Android/Web/ICU templates in {target}")
