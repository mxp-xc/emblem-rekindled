extends RefCounted

const STATS: Array[String] = [
	"strength", "skill", "speed", "defense", "magic", "luck", "maxHp", "move"
]


# The immutable source profiles establish each formal member's original class.
# Saved class values and optional saved metadata never establish that provenance.
static func context(rules: Dictionary, profiles: Dictionary) -> Dictionary:
	var pairs: Dictionary = {}
	var targets: Dictionary = {}
	var definitions: Variant = rules.get("promotions", [])
	if not definitions is Array:
		return {"ok": false, "error": "INVALID_PROMOTION_RULES"}
	for value: Variant in definitions:
		if not value is Dictionary:
			return {"ok": false, "error": "INVALID_PROMOTION_RULES"}
		var row: Dictionary = value
		if (
			not _integer(row.get("fromClassId"))
			or not _integer(row.get("toClassId"))
			or not _integer(row.get("minimumLevel"))
			or row["fromClassId"] < 0
			or row["toClassId"] > 40
			or row["minimumLevel"] < 1
			or row["minimumLevel"] > 20
			or int(row["fromClassId"]) % 4 != 0
			or row["toClassId"] != row["fromClassId"] + 1
			or pairs.has(int(row["fromClassId"]))
			or targets.has(int(row["toClassId"]))
			or not row.get("gains") is Dictionary
			or row["gains"].size() != STATS.size()
		):
			return {"ok": false, "error": "INVALID_PROMOTION_RULES"}
		for stat: String in STATS:
			if not _integer(row["gains"].get(stat)) or row["gains"][stat] < 0:
				return {"ok": false, "error": "INVALID_PROMOTION_RULES"}
		pairs[int(row["fromClassId"])] = int(row["toClassId"])
		targets[int(row["toClassId"])] = true
	var bases: Dictionary = {}
	for value: Variant in profiles.values():
		if not value is Dictionary or not value.get("unit") is Dictionary:
			continue
		var unit: Dictionary = value["unit"]
		if (
			unit.get("formal") != true
			or unit.get("faction") != 0
			or not _integer(unit.get("sourceId"))
			or unit["sourceId"] < 0
			or unit["sourceId"] >= 10
			or not _integer(unit.get("classId"))
			or not pairs.has(int(unit["classId"]))
		):
			continue
		var source: int = int(unit["sourceId"])
		var class_id: int = int(unit["classId"])
		if bases.has(source) and bases[source] != class_id:
			return {"ok": false, "error": "AMBIGUOUS_PROMOTION_SOURCE"}
		bases[source] = class_id
	return {"ok": true, "pairs": pairs, "bases": bases}


static func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and value == floorf(float(value))
	)
