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
    if not 0 <= battle <= 19:
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

        map_data = resource(f"m{battle}")
        width, height = map_data[:2]
        records = deployment_records(resource(f"p{battle}"), width, height)
    result = {"battleId": f"m{battle}", "width": width, "height": height, "units": records}
    if battle in (1, 12, 13, 14, 15, 16, 17, 18, 19):
        result["locations"] = map_locations(map_data, battle)
    return result


def map_locations(data: bytes, battle: int) -> list[dict]:
    """Read verified map-specific location tails without drawing any reward."""
    if battle not in (1, 12, 13, 14, 15, 16, 17, 18, 19):
        raise ValueError("Unverified chapter-1 locations")
    if len(data) < 3:
        raise ValueError("Truncated chapter-1 map")
    width, height = data[:2]
    position = 2 + width * height

    def byte():
        nonlocal position
        if position >= len(data):
            raise ValueError("Truncated chapter-1 location")
        value = data[position]
        position += 1
        return value

    result = []
    for index in range(byte()):
        kind, x, y = byte(), byte(), byte()
        if not 0 <= x < width or not 0 <= y < height:
            raise ValueError("Location is outside the map")
        tile = data[2 + y * width + x]
        expected_tiles = {
            1: (58, 59, 79),
            12: (79,),
            13: (58, 59),
            14: (39, 44),
            15: (39, 58, 59, 79),
            16: (39, 49, 58, 59, 79),
            17: (79,),
            18: (79,),
            19: (79,),
        }[battle]
        if tile not in expected_tiles:
            raise ValueError("Location disagrees with verified terrain")
        location_kind = {
            12: "chest",
            13: "visit",
            14: "waitPickup",
            17: "chest",
            18: "chest",
            19: "chest",
        }.get(battle)
        if battle in (1, 15, 16):
            location_kind = {
                79: "chest",
                58: "visit",
                59: "visit",
                39: "waitPickup",
                49: "waitPickup",
            }[tile]
        if kind == 3 and (
            battle in (1, 12, 13)
            or battle == 15
            and location_kind == "waitPickup"
            or battle in (16, 17, 18, 19)
            and location_kind == "chest"
        ):
            choices = [{"templateId": byte(), "weight": byte()} for _ in range(byte())]
            if (
                not choices
                or any(not 1 <= row["templateId"] <= 87 or row["weight"] <= 0 for row in choices)
                or (
                    battle in (13, 15, 16, 17, 18, 19)
                    and sum(row["weight"] for row in choices) > 100
                )
            ):
                raise ValueError("Invalid weighted location choices")
            reward = {"kind": "weightedItem", "weightedChoices": choices}
        elif (
            kind == 1
            and battle in (1, 13, 14, 15, 16, 19)
            and (
                battle not in (15, 16)
                or location_kind in ("chest", "visit")
                or battle == 16
                and location_kind == "waitPickup"
            )
        ):
            template = byte()
            if not 1 <= template <= 87:
                raise ValueError("Invalid fixed location item")
            reward = {"kind": "item", "templateId": template}
        elif kind == 2 and battle in (15, 16) and location_kind == "visit":
            amount = int.from_bytes(bytes(byte() for _ in range(4)), "big", signed=True)
            if not 1 <= amount <= 9999999:
                raise ValueError("Invalid fixed location gold")
            reward = {"kind": "gold", "amount": amount}
        elif kind == 4 and (
            battle in (1, 13, 17, 18) or battle in (15, 16) and location_kind == "visit"
        ):
            values = [
                int.from_bytes(bytes(byte() for _ in range(4)), "big", signed=True)
                for _ in range(2)
            ]
            if not 1 <= values[0] <= values[1] <= 9999999:
                raise ValueError("Invalid location gold range")
            reward = {"kind": "goldRange", "minimum": values[0], "maximum": values[1]}
        else:
            raise ValueError("Unsupported verified location kind")
        prefix = {"chest": "chest", "visit": "visit", "waitPickup": "wait"}[location_kind]
        location = {
            "id": f"{prefix}_{index}",
            "sourceIndex": index,
            "kind": location_kind,
            "position": [x, y],
            "tileId": tile,
        }
        if location_kind == "chest" and reward["kind"] == "weightedItem":
            location["weightedChoices"] = reward["weightedChoices"]
            if battle in (16, 17, 18, 19) and sum(row["weight"] for row in choices) < 100:
                location["emptyWeight"] = 100 - sum(row["weight"] for row in choices)
        else:
            location["reward"] = reward
        result.append(location)
    if position != len(data):
        raise ValueError("Unexpected trailing chapter-1 map bytes")
    if len({tuple(row["position"]) for row in result}) != len(result):
        raise ValueError("Duplicate map location")
    return result
