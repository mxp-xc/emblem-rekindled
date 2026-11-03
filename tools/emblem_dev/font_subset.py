"""Build and validate the game's subset of its upstream Noto CJK font."""

import json
import re
import sys
import tempfile
import unicodedata
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

from emblem_dev.paths import GAME

FONT = GAME / "ui/fonts/NotoSansCJKsc-Regular.woff2"
TEXT_SUFFIXES = {".gd", ".json", ".tscn", ".godot", ".cfg", ".md", ".txt"}


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _strings(key)
            yield from _strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _strings(item)


def required_codepoints(game: Path = GAME) -> set[int]:
    """Cover all current project text, escaped JSON strings, and GB2312."""
    chars = {chr(code) for code in range(32, 127)}
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                chars.add(bytes((high, low)).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    for path in game.rglob("*"):
        if not path.is_file() or ".godot" in path.parts or path.suffix not in TEXT_SUFFIXES:
            continue
        text = path.read_text(encoding="utf-8")
        chars.update(text)
        if path.suffix == ".json":
            for item in _strings(json.loads(text)):
                chars.update(item)
        elif path.suffix in {".gd", ".tscn", ".godot"}:
            chars.update(chr(int(code, 16)) for code in re.findall(r"\\u([0-9A-Fa-f]{4})", text))
    return {ord(char) for char in chars if not unicodedata.category(char).startswith("C")}


def missing_codepoints(font: Path = FONT, game: Path = GAME) -> set[int]:
    with TTFont(font, lazy=True) as current:
        return required_codepoints(game) - set(current.getBestCmap())


def generate(source: Path, target: Path = FONT, game: Path = GAME) -> None:
    if source.resolve() == target.resolve():
        raise ValueError("Use a separate, complete upstream font as input")
    required = required_codepoints(game)
    with TTFont(source) as font:
        missing = required - set(font.getBestCmap())
        if missing:
            raise ValueError("Upstream font lacks required characters: " + _format_missing(missing))
        options = subset.Options()
        options.name_IDs = ["*"]
        options.name_languages = ["*"]
        options.name_legacy = True
        processor = subset.Subsetter(options=options)
        processor.populate(unicodes=required)
        processor.subset(font)
        font.flavor = "woff2"
        with tempfile.NamedTemporaryFile(dir=target.parent, suffix=".woff2") as output:
            font.save(output.name)
            remaining = missing_codepoints(Path(output.name), game)
            if remaining:
                raise ValueError(
                    "Generated font lacks required characters: " + _format_missing(remaining)
                )
            Path(output.name).replace(target)


def _format_missing(values: set[int]) -> str:
    return ", ".join(f"U+{value:04X}" for value in sorted(values))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: uv run python -m emblem_dev.font_subset /path/to/original.otf")
    generate(Path(sys.argv[1]))
    print(f"Generated {FONT}")


if __name__ == "__main__":
    main()
