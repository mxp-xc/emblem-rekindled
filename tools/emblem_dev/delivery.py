"""Shared build identity checks used by export, platform verification and QA."""

import json
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

from .paths import GODOT, ROOT


def run(*command: str, timeout: int = 180) -> str:
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    if result.returncode or re.search(r"(?:SCRIPT ERROR|ERROR):", result.stdout + result.stderr):
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def verify_pack(pack: Path, expected: str) -> None:
    run(
        "godot",
        "--headless",
        "--main-pack",
        str(pack),
        "--script",
        str(GODOT / "verify_web_build.gd"),
        "--",
        expected,
    )


def verify_apk(apk: Path, expected: str) -> None:
    with zipfile.ZipFile(apk) as archive:
        identity = json.loads(archive.read("assets/content/build_info.json"))
    if identity.get("buildId") != expected:
        raise RuntimeError(f"APK identity mismatch: expected {expected}, got {identity}")


def verify_android(serial: str | None = None, apk: Path | None = None) -> None:
    from .qa.client import PACKAGE, Playtest

    if apk is None:
        expected = json.loads((ROOT / "build/android/build-info.json").read_text())["buildId"]
    else:
        with zipfile.ZipFile(apk) as archive:
            expected = json.loads(archive.read("assets/content/build_info.json"))["buildId"]
    client = Playtest(serial)
    paths = client.adb("shell", "pm", "path", PACKAGE).decode().splitlines()
    base = next(
        (path.removeprefix("package:") for path in paths if path.endswith("/base.apk")), None
    )
    if base is None:
        raise RuntimeError("Installed base APK not found")
    with tempfile.TemporaryDirectory(prefix="emblem-installed-apk-") as directory:
        apk = Path(directory) / "base.apk"
        client.adb("pull", base, str(apk))
        verify_apk(apk, expected)
    print(f"PASS installed APK {expected}")
