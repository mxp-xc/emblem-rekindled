extends RefCounted

const MAXIMUM: int = 2147483647
const KEYS: Array[String] = ["rounds", "playerRetirements", "allyRetirements"]


static func fresh() -> Dictionary:
	return {"rounds": 1, "playerRetirements": 0, "allyRetirements": 0}


static func unknown() -> Dictionary:
	return {"rounds": null, "playerRetirements": null, "allyRetirements": null}


# null is the caller's explicit legacy sentinel; a present field must be an object.
static func decode(value: Variant) -> Dictionary:
	if value == null:
		return {"ok": true, "stats": unknown()}
	if not value is Dictionary or value.size() != KEYS.size():
		return {"ok": false, "error": "INVALID_CHAPTER_STATS"}
	var stats: Dictionary = {}
	for key: String in KEYS:
		if not value.has(key):
			return {"ok": false, "error": "INVALID_CHAPTER_STATS"}
		var counter: Variant = value[key]
		if counter != null and not _integer_in(counter, 1 if key == "rounds" else 0, MAXIMUM):
			return {"ok": false, "error": "INVALID_CHAPTER_STATS"}
		stats[key] = null if counter == null else int(counter)
	return {"ok": true, "stats": stats}


static func increment(stats: Dictionary, key: String) -> void:
	if key in KEYS and stats.get(key) != null:
		stats[key] = mini(MAXIMUM, int(stats[key]) + 1)


static func command_ability(stats: Dictionary) -> Variant:
	if stats.get("allyRetirements") == null:
		return null
	return maxi(0, 9999 - 153 * int(stats["allyRetirements"]))


static func rating(stats: Dictionary, total_power: int) -> String:
	if total_power > 4000:
		return "SSS"
	for key: String in KEYS:
		if stats.get(key) == null:
			return ""
	var player: int = int(stats["playerRetirements"])
	var ally: int = int(stats["allyRetirements"])
	var rounds: int = int(stats["rounds"])
	if player == 0 and ally < 4 and rounds <= 200:
		return "SSS"
	if (player < 3 and ally < 8 and rounds <= 220) or total_power > 3000:
		return "S"
	if player < 6 and ally < 12 and rounds <= 240:
		return "A"
	if player < 9 and ally < 16 and rounds <= 300:
		return "B"
	return "C"


static func validate_result(
	value: Variant, party: Array, stats: Dictionary, historical: bool = false
) -> Dictionary:
	if (
		not value is Dictionary
		or value.size() != 4
		or not value.get("party") is Array
		or value["party"].size() != party.size()
		or not _integer_in(value.get("gold"), 0, 9999999)
		or not _integer_in(value.get("totalPower"), 0, MAXIMUM)
		or not value.get("chapterStats") is Dictionary
	):
		return {"ok": false, "error": "INVALID_CHAPTER_RESULT"}
	var decoded: Dictionary = decode(value["chapterStats"])
	if not decoded["ok"] or (not historical and decoded["stats"] != stats):
		return {"ok": false, "error": "INVALID_CHAPTER_RESULT"}
	var identities: Dictionary = {}
	for actor: Dictionary in party:
		identities[int(actor["id"])] = int(actor["level"])
	var previous: int = -1
	var total: int = 0
	var entries: Array = []
	for entry: Variant in value["party"]:
		if (
			not entry is Dictionary
			or entry.size() != 3
			or not _integer_in(entry.get("id"), 0, 9)
			or not _integer_in(entry.get("level"), 1, 20)
			or not _integer_in(entry.get("power"), 0, MAXIMUM)
		):
			return {"ok": false, "error": "INVALID_CHAPTER_RESULT"}
		var id: int = int(entry["id"])
		if (
			id <= previous
			or not identities.has(id)
			or (not historical and int(entry["level"]) != identities[id])
		):
			return {"ok": false, "error": "INVALID_CHAPTER_RESULT"}
		previous = id
		total += int(entry["power"])
		entries.append({"id": id, "level": int(entry["level"]), "power": int(entry["power"])})
	if total != int(value["totalPower"]):
		return {"ok": false, "error": "INVALID_CHAPTER_RESULT"}
	return {
		"ok": true,
		"result":
		{
			"party": entries,
			"gold": int(value["gold"]),
			"totalPower": total,
			"chapterStats": decoded["stats"]
		}
	}


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)
