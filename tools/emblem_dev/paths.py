"""Shared repository and tool resource locations."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
RESOURCES = ROOT / "tools" / "resources"
JAVA = RESOURCES / "content"
GODOT = RESOURCES / "godot"
WEB = RESOURCES / "web"
TESTS = ROOT / "tests" / "tools"
