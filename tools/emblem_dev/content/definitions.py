"""Read ordered unresolved deployments from the pinned chapter-1 source."""

import hashlib
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
    raise KeyError(wanted)


def deployment_records(data: bytes, width: int, height: int) -> list[dict]:
    """Parse ordered source records without choosing a route, roster or random result."""
    position = 0

    def byte() -> int:
        nonlocal position
        if position >= len(data):
            raise ValueError("Truncated chapter-1 deployment")
        value = data[position]
        position += 1
        return value - 256 if value > 127 else value

    count = byte()
    if count < 1 or width < 1 or height < 1:
        raise ValueError("Invalid deployment dimensions or record count")
    result = []
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
        if region_count < 0:
            raise ValueError("Invalid deployment region count")
        regions = [[byte() for _ in range(4)] for _ in range(region_count)]
        point = [byte(), byte()] if region_count == 0 else None
        if random_equipment not in (0, 1):
            raise ValueError(f"Unsupported equipment selection mode: {random_equipment}")
        if not 0 <= class_id <= 40 or source_id < 0 or faction not in (0, 1, 2):
            raise ValueError("Invalid chapter-1 class, source identity or faction")
        if any(item < 0 or item > 87 for item in [*choices, drop_template_id]):
            raise ValueError("Invalid chapter-1 item reference")
        if point is not None and (not 0 <= point[0] < width or not 0 <= point[1] < height):
            raise ValueError("Chapter-1 deployment position is outside map")
        if any(
            not 0 <= left <= right < width or not 0 <= top <= bottom < height
            for left, top, right, bottom in regions
        ):
            raise ValueError("Chapter-1 deployment region is outside map")
        record = {
            "kind": kind,
            "classId": class_id,
            "sourceId": source_id,
            "level": max(1, level),
            "faction": faction,
            "flags": flags,
            "policy": policy,
            "randomEquipment": random_equipment == 1,
            "itemChoices": choices,
            "dropTemplateId": drop_template_id,
        }
        if regions:
            record["deploymentRegions"] = regions
        else:
            record["position"] = point
        if explicit is not None:
            record["explicitStats"] = explicit
        if faction == 0 and policy & 32:
            record["deploymentSlot"] = source_id
        result.append(record)
    if position != len(data):
        raise ValueError(f"Unexpected trailing deployment bytes: {len(data) - position}")
    return result


def read_deployment(source: Path, battle: int) -> dict:
    """Read one verified map's raw deployment; normal runtime never requires the JAR."""
    if not 0 <= battle <= 7:
        raise ValueError(f"Unverified chapter-1 battle: m{battle}")
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA:
        raise ValueError("Chapter-1 source JAR SHA-256 mismatch")
    with zipfile.ZipFile(source) as archive:
        pak = archive.read("1.pak")

        def resource(name):
            try:
                return _pak_member(pak, name)
            except KeyError:
                return archive.read(name)

        width, height = resource(f"m{battle}")[:2]
        records = deployment_records(resource(f"p{battle}"), width, height)
    return {"battleId": f"m{battle}", "width": width, "height": height, "units": records}
