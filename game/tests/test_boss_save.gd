extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	var first: Dictionary = Session.new().open(CHAPTER, "", {"new": true}, _zero)
	if not first["ok"]:
		fail("Open the first battle: " + str(first))
		return
	first["battle"].win_with_assistance()
	var completed: Dictionary = first["battle"].complete_victory(0)
	if not completed["ok"]:
		fail("Complete the first battle: " + str(completed))
		return
	var second: Dictionary = Session.new().open(
		CHAPTER, "m1", {"progress": completed["progress"]}, _zero
	)
	if not second["ok"]:
		fail("Open m1 from world progress: " + str(second))
		return
	var store: RefCounted = Store.new(second["content"])
	var encoded: Dictionary = store.encode(second["battle"])
	if not encoded["ok"]:
		fail("Encode the unmodified battle: " + str(encoded))
		return
	var record: Dictionary = encoded["record"].duplicate(true)
	var found: bool = false
	for unit: Dictionary in record["state"]["units"]:
		if unit["id"] == 81:
			unit["maxHp"] = 70
			unit["hp"] = 40
			unit["attributes"]["strength"] = 40
			found = true
	if not found:
		fail("m1 must contain its source 81 boss")
		return
	var restored: Dictionary = store.decode(JSON.parse_string(JSON.stringify(record)), _zero)
	if not restored["ok"]:
		fail("A trusted boss must cold-read adaptive values above ordinary caps: " + str(restored))
		return
	var boss: Dictionary = restored["battle"].unit(81)
	if boss["hp"] != 40 or boss["maxHp"] != 70 or boss["attributes"]["strength"] != 40:
		fail("Cold restore must preserve both current HP and adaptive maximum values")
		return
	for limit: int in [99, 100]:
		var boundary: Dictionary = record.duplicate(true)
		for unit: Dictionary in boundary["state"]["units"]:
			if unit["id"] == 81:
				unit["maxHp"] = limit
				unit["attributes"]["strength"] = limit
		var checked: Dictionary = store.decode(JSON.parse_string(JSON.stringify(boundary)), _zero)
		if checked["ok"] != (limit == 99):
			fail("Trusted boss adaptive stats must accept 99 and reject 100")
			return
	var ordinary: Dictionary = encoded["record"].duplicate(true)
	found = false
	for unit: Dictionary in ordinary["state"]["units"]:
		if unit["faction"] == 2 and (unit["id"] < 80 or unit["id"] > 94):
			unit["maxHp"] = 70
			unit["attributes"]["strength"] = 40
			unit["bossInheritedStats"] = true
			found = true
			break
	if not found or store.decode(JSON.parse_string(JSON.stringify(ordinary)), _zero)["ok"]:
		fail("An ordinary enemy cannot acquire boss bounds from a save-supplied marker")
		return
	var forged: Dictionary = encoded["record"].duplicate(true)
	for unit: Dictionary in forged["state"]["units"]:
		if unit["faction"] == 2 and (unit["id"] < 80 or unit["id"] > 94):
			unit["sourceId"] = 81
			break
	if store.decode(JSON.parse_string(JSON.stringify(forged)), _zero)["ok"]:
		fail("A save cannot forge the boss source identity")
		return
	print("PASS boss save: trusted adaptive values survive Session, Store and JSON")
	quit(0)


func _zero(_limit: int) -> int:
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
