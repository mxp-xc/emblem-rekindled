"""Fail-closed backup and recovery of Android playtest records; no game-state editing."""

import argparse
import json
import re
from contextlib import contextmanager
from pathlib import Path
from typing import Protocol

KNOWN_RECORDS = (
    "battle_save.json",
    "settings.json",
    "world_save.json",
    *(f"battle_save_slot_{index}.json" for index in range(1, 5)),
)


def record_name(name: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_-]+\.json(?:\.tmp)?", name):
        raise ValueError(f"Invalid record name: {name!r}")
    return name


class RecordStore(Protocol):
    def record_names(self) -> list[str]: ...
    def record_exists(self, name: str) -> bool: ...
    def read_record(self, name: str) -> bytes: ...
    def write_record(self, name: str, data: bytes) -> None: ...
    def remove_record(self, name: str) -> None: ...


def names(store: RecordStore) -> set[str]:
    listed = [record_name(name) for name in store.record_names()]
    if len(listed) != len(set(listed)):
        raise RuntimeError("Duplicate record names; backup cannot be trusted")
    result = set(listed)
    for name in KNOWN_RECORDS:
        if store.record_exists(name) != (name in result):
            raise RuntimeError(f"Record listing disagrees with existence check: {name}")
    return result


def load_backup(path: Path) -> dict[str, bytes]:
    manifest = json.loads(path.read_text())
    if (
        manifest.get("version") != 1
        or manifest.get("complete") is not True
        or not isinstance(manifest.get("records"), dict)
        or manifest.get("originallyEmpty") is not (not manifest["records"])
    ):
        raise ValueError("Incomplete or invalid record backup")
    original = {}
    for name, data in manifest["records"].items():
        record_name(name)
        if not isinstance(data, list) or any(type(n) is not int or not 0 <= n <= 255 for n in data):
            raise ValueError(f"Invalid record bytes: {name}")
        original[name] = bytes(data)
    return original


def backup_records(store: RecordStore, directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=False)
    listed = names(store)
    original = {name: store.read_record(name) for name in sorted(listed)}
    if names(store) != listed or any(store.read_record(n) != data for n, data in original.items()):
        raise RuntimeError("Records changed during backup; stop the app before taking a snapshot")
    path = directory / "backup.json"
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(
            {
                "version": 1,
                "complete": True,
                "originallyEmpty": not original,
                "records": {name: list(data) for name, data in original.items()},
            }
        )
    )
    temporary.replace(path)
    if load_backup(path) != original:
        raise RuntimeError("Persisted backup differs from source records")
    return path


def restore_records(store: RecordStore, path: Path) -> None:
    original = load_backup(path)
    (path.parent / "restored.json").unlink(missing_ok=True)
    # Restore and verify every original before removing anything created by the test.
    for name, data in original.items():
        store.write_record(name, data)
        if store.read_record(name) != data:
            raise RuntimeError(f"Restoration verification failed: {name}; retain {path}")
    for name in names(store) - original.keys():
        store.remove_record(name)
    if names(store) != original.keys() or any(
        store.read_record(name) != data for name, data in original.items()
    ):
        raise RuntimeError(f"Restored records differ; recover from {path}")
    (path.parent / "restored.json").write_text(json.dumps({"allOriginalJsonBytesRestored": True}))


@contextmanager
def preserve_records(store: RecordStore, directory: Path):
    path = backup_records(store, directory)
    try:
        yield path
    finally:
        restore_records(store, path)


def main() -> None:
    from android_playtest import PACKAGE, Playtest

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backup", type=Path, help="Previously completed backup.json")
    parser.add_argument("--serial")
    args = parser.parse_args()
    load_backup(args.backup)
    client = Playtest(args.serial)
    client.adb("shell", "am", "force-stop", PACKAGE)
    restore_records(client, args.backup)
    print("Original record bytes restored and verified")


if __name__ == "__main__":
    main()
