"""Show bounded literal-match context, including fragments inside minified/generated files."""

import argparse
from pathlib import Path


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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("needle")
    parser.add_argument("--radius", type=int, default=160)
    parser.add_argument("--limit", type=int, default=5)
    args = parser.parse_args()
    for fragment in fragments(
        args.file.read_text(), args.needle, radius=args.radius, limit=args.limit
    ):
        print(fragment)


if __name__ == "__main__":
    main()
