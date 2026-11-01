"""Convert the pinned chapter-1 deployment data into runtime spawn definitions."""

import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path

SOURCE_SHA = "67d1c77e823816e203244a15428ba9fb635d40edba04efa3180b3334025989fe"
EXPLICIT_STATS = ("maxHp", "strength", "skill", "speed", "defense", "magic", "luck", "move")


def _pak_member(pak: bytes, wanted: str) -> bytes:
    position = 2
    directory: list[tuple[str, int]] = []
    for _ in range(struct.unpack_from(">H", pak)[0]):
        size = struct.unpack_from(">H", pak, position)[0]
        position += 2
        # All names in this pinned archive are ASCII, also valid modified UTF-8.
        name = pak[position : position + size].decode("ascii")
        position += size
        length = struct.unpack_from(">H", pak, position)[0]
        position += 2
        directory.append((name, length))
    for name, length in directory:
        if name == wanted:
            result = pak[position : position + length]
            if len(result) != length:
                raise ValueError(f"Truncated archive resource: {wanted}")
            return result
        position += length
    raise ValueError(f"Archive resource not found: {wanted}")


def _spawn_definitions(data: bytes, battle: int = 0) -> list[dict]:
    if battle not in (0, 1):
        raise ValueError(f"Unverified chapter-1 battle: m{battle}")
    width, height = (20, 25) if battle == 0 else (22, 22)
    position = 0

    def byte() -> int:
        nonlocal position
        if position >= len(data):
            raise ValueError("Truncated chapter-1 deployment")
        value = data[position]
        position += 1
        return value - 256 if value > 127 else value

    count = byte()
    if count != 32:
        raise ValueError(f"Unexpected chapter-1 deployment count: {count}")
    result = []
    next_temporary_id = 95
    identities: set[int] = set()
    for _ in range(count):
        kind, class_id = byte(), byte()
        if kind not in (0, 1):
            raise ValueError(f"Unsupported deployment initialization kind: {kind}")
        explicit = (
            dict(zip(EXPLICIT_STATS, [byte() for _ in range(8)], strict=True))
            if kind == 0
            else None
        )
        source_id, level, faction = byte(), byte(), byte()
        byte()  # Original parser discards this byte.
        flags, policy = byte() & 255, byte() & 255
        random_equipment = byte()
        choices = [byte() for _ in range(3)]
        drop_template_id = byte()
        region_count = byte()
        if region_count != 0:
            raise ValueError("Random deployment regions are not part of the verified deployments")
        point = [byte(), byte()]
        if random_equipment not in (0, 1):
            raise ValueError(f"Unsupported equipment selection mode: {random_equipment}")
        if class_id < 0 or class_id > 40 or faction not in (0, 1, 2):
            raise ValueError("Invalid chapter-1 class or faction")
        if any(item < 0 or item > 87 for item in [*choices, drop_template_id]):
            raise ValueError("Invalid chapter-1 item reference")
        if not 0 <= point[0] < width or not 0 <= point[1] < height:
            raise ValueError(f"Chapter-1 deployment position is outside m{battle}")
        deployment_id = source_id
        deployment_slot = source_id if faction == 0 and policy & 32 else None
        if deployment_slot is not None:
            if battle == 1 and deployment_slot in (0, 1):
                deployment_id = (0, 9)[deployment_slot]
                source_id = deployment_id
            else:
                deployment_id = next_temporary_id
                next_temporary_id += 1
                if deployment_id > 99:
                    raise ValueError("Temporary deployment identities exhausted")
        if deployment_id in identities:
            raise ValueError(f"Duplicate deployment identity: {deployment_id}")
        identities.add(deployment_id)
        if battle == 0 and deployment_id == 10:
            point = [7, 9]
        elif battle == 0 and deployment_id == 11:
            point = [10, 13]
        if faction == 2 and battle == 0:
            flags &= ~1
        group = class_id // 4
        spawn = {
            "id": deployment_id,
            "sourceId": source_id,
            "formal": faction == 0 and 0 <= deployment_id < 10,
            "classId": class_id,
            "faction": faction,
            "level": max(1, level),
            "initialGrowthTemplateId": (source_id if source_id < 10 else 10 + group)
            if kind == 1
            else None,
            "growthTemplateId": deployment_id if deployment_id < 10 else 10 + group,
            "itemChoices": choices,
            "randomEquipment": random_equipment == 1,
            "dropTemplateId": drop_template_id,
            "position": point,
            "flags": flags,
            "policy": policy,
            "visible": flags & 1 == 0,
        }
        if battle and deployment_slot is not None:
            spawn["deploymentSlot"] = deployment_slot
        if explicit is not None:
            spawn["explicitStats"] = explicit
        else:
            spawn["baseTemplateId"] = source_id if source_id < 10 else 10 + class_id
        result.append(spawn)
    if position != len(data):
        raise ValueError(f"Unexpected trailing deployment bytes: {len(data) - position}")
    if next_temporary_id != (100 if battle == 0 else 99):
        raise ValueError(f"Unexpected temporary deployment count in m{battle}")
    return result


def export_definitions(source: Path, output: Path, battle: int = 0) -> None:
    """Write spawns.json under output, preserving random choices rather than sampling them."""
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA:
        raise ValueError("Chapter-1 source JAR SHA-256 mismatch")
    with zipfile.ZipFile(source) as archive:
        data = (
            _pak_member(archive.read("1.pak"), "p0") if battle == 0 else archive.read(f"p{battle}")
        )
        spawns = _spawn_definitions(data, battle)
    output.mkdir(parents=True, exist_ok=True)
    (output / "spawns.json").write_text(json.dumps(spawns, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, help="Directory to receive spawns.json")
    args = parser.parse_args()
    export_definitions(args.source, args.output)


if __name__ == "__main__":
    main()
