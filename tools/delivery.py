"""Export identified builds and verify the served PCK or installed Android package."""

import argparse
import json
import re
import shutil
import subprocess
import tempfile
import uuid
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.request import urlopen
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
INFO = GAME / "content/build_info.json"


def run(*command: str, timeout: int = 180) -> str:
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    if result.returncode or re.search(r"(?:SCRIPT ERROR|ERROR):", result.stdout + result.stderr):
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def export(platform: str) -> dict:
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    identity = {
        "buildId": now.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8],
        "builtAt": now.strftime("%Y-%m-%d %H:%M:%S"),
        "revision": run("git", "-C", str(ROOT), "rev-parse", "--short", "HEAD").strip(),
        "dirty": bool(run("git", "-C", str(ROOT), "status", "--porcelain").strip()),
    }
    previous = INFO.read_bytes() if INFO.exists() else None
    try:
        INFO.write_text(json.dumps(identity, ensure_ascii=False, indent=2) + "\n")
        with tempfile.TemporaryDirectory(prefix="emblem-export-") as directory:
            filename = "index.html" if platform == "web" else "emblem-rekindled.apk"
            output = Path(directory) / filename
            print(f"[EXPORT] {platform} {identity['buildId']}", flush=True)
            run(
                "godot",
                "--headless",
                "--path",
                str(GAME),
                "--export-debug",
                "Web" if platform == "web" else "Android",
                str(output),
            )
            if platform == "web":
                verify_pack(output.with_suffix(".pck"), identity["buildId"])
            else:
                verify_apk(output, identity["buildId"])
            destination = ROOT / "build" / platform
            destination.mkdir(parents=True, exist_ok=True)
            for file in Path(directory).iterdir():
                shutil.copy2(file, destination / file.name)
            (destination / "build-info.json").write_text(json.dumps(identity, indent=2) + "\n")
    finally:
        if previous is None:
            INFO.unlink(missing_ok=True)
        else:
            INFO.write_bytes(previous)
    return identity


def verify_pack(pack: Path, expected: str) -> None:
    run(
        "godot",
        "--headless",
        "--main-pack",
        str(pack),
        "--script",
        str(ROOT / "tools/verify_web_build.gd"),
        "--",
        expected,
    )


def verify_apk(apk: Path, expected: str) -> None:
    with zipfile.ZipFile(apk) as archive:
        identity = json.loads(archive.read("assets/content/build_info.json"))
    if identity.get("buildId") != expected:
        raise RuntimeError(f"APK identity mismatch: expected {expected}, got {identity}")


def verify_web(origin: str) -> None:
    expected = json.loads((ROOT / "build/web/build-info.json").read_text())["buildId"]
    with tempfile.TemporaryDirectory(prefix="emblem-served-pack-") as directory:
        for resource in ("", "index.pck"):
            with urlopen(origin.rstrip("/") + "/" + resource, timeout=30) as response:
                if response.headers.get("Cache-Control") != "no-store":
                    raise RuntimeError("Preview server must disable HTTP caching")
                if not resource and response.headers.get("Clear-Site-Data") != '"cache"':
                    raise RuntimeError("Root navigation must retire old HTTP cache")
                if resource:
                    pack = Path(directory) / "index.pck"
                    with pack.open("wb") as output:
                        shutil.copyfileobj(response, output)
                    verify_pack(pack, expected)
    print(f"PASS served PCK {expected}; browser runtime still requires canvas dataset check")


def verify_android(serial: str | None = None, apk: Path | None = None) -> None:
    from android_playtest import PACKAGE, Playtest

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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("web", "android", "verify-web", "verify-android"))
    parser.add_argument("--origin", default="http://127.0.0.1:8765/")
    parser.add_argument("--serial")
    args = parser.parse_args()
    if args.command == "verify-web":
        verify_web(args.origin)
    elif args.command == "verify-android":
        verify_android(args.serial)
    else:
        print(json.dumps(export(args.command), ensure_ascii=False))


if __name__ == "__main__":
    main()
