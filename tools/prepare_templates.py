"""Verify the official Godot 4.7.2 TPZ, then extract only Android/Web/ICU templates locally."""

import argparse
import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_SHA = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
FILES = (
    "android_debug.apk",
    "android_release.apk",
    "web_nothreads_debug.zip",
    "web_nothreads_release.zip",
    "icudt_godot.dat",
    "version.txt",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tpz", type=Path)
    args = parser.parse_args()
    with args.tpz.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != TEMPLATE_SHA:
            raise ValueError("Godot template SHA-256 mismatch")
    target = ROOT / "build/templates/4.7.2.stable"
    with zipfile.ZipFile(args.tpz) as archive:
        if archive.read("templates/version.txt").strip() != b"4.7.2.stable":
            raise ValueError("Godot template version mismatch")
        target.mkdir(parents=True, exist_ok=True)
        for name in FILES:
            (target / name).write_bytes(archive.read("templates/" + name))
    print(f"Prepared Android/Web/ICU templates in {target}")


if __name__ == "__main__":
    main()
