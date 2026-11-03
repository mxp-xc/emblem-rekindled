extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _draws: int = 0


func _initialize() -> void:
	var session := Session.new()
	var first: Dictionary = session.open(CHAPTER, "", {"new": true}, _zero)
	first["battle"].win_with_assistance()
	var progress: Dictionary = first["battle"].complete_victory(0)["progress"]
	var baseline: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _zero)
	if not baseline["ok"]:
		fail("Open baseline from completed world progress: " + str(baseline))
		return
	var context: Dictionary = {
		"attributes": {"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
		"maxHp": 90,
		"maxInternalLevel": 0,
		"averageInternalLevel": 0,
		"maxProficiency": 0
	}
	var before: Dictionary = context.duplicate(true)
	var invalid_values: Array = []
	var too_high: Dictionary = context.duplicate(true)
	too_high["maxProficiency"] = 100
	invalid_values.append(too_high)
	var missing: Dictionary = context.duplicate(true)
	missing.erase("averageInternalLevel")
	invalid_values.append(missing)
	var negative: Dictionary = context.duplicate(true)
	negative["maxHp"] = -1
	invalid_values.append(negative)
	var high_level: Dictionary = context.duplicate(true)
	high_level["maxInternalLevel"] = 20
	invalid_values.append(high_level)
	var high_stat: Dictionary = context.duplicate(true)
	high_stat["attributes"]["strength"] = 128
	invalid_values.append(high_stat)
	var fractional: Dictionary = context.duplicate(true)
	fractional["attributes"]["strength"] = 1.5
	invalid_values.append(fractional)
	invalid_values.append("not a context")
	for invalid: Variant in invalid_values:
		_draws = 0
		var rejected: Dictionary = session.open(
			CHAPTER, "m1", {"progress": progress}, _zero, invalid
		)
		if rejected.get("error") != "INVALID_DEPLOYMENT_CONTEXT" or _draws != 0:
			fail("Invalid context must fail before binding or random initialization")
			return
	var opened: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _zero, context)
	if not opened["ok"]:
		fail("Open with an explicit context: " + str(opened))
		return
	var base_hp: int = baseline["battle"].unit(81)["maxHp"]
	var boss: Dictionary = opened["battle"].unit(81)
	if (
		boss["hp"] != base_hp
		or boss["maxHp"] != base_hp + ((90 - base_hp) >> 1)
		or context != before
	):
		fail("World entry must pass the supplied context without changing current HP or input")
		return
	var trained: Dictionary = context.duplicate(true)
	trained["maxInternalLevel"] = 8
	trained["averageInternalLevel"] = 5
	var scaled: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _zero, trained)
	if not scaled["ok"]:
		fail("Open m1 with a trained party context: " + str(scaled))
		return
	for unit: Dictionary in scaled["battle"].snapshot()["units"]:
		if unit["id"] == 81 and unit["level"] != 9:
			fail("A new enemy must use the party maximum level")
			return
		if unit["faction"] == 1 and unit["level"] != 6:
			fail("A new allied unit must use the party average level")
			return
	scaled["battle"].win_with_assistance()
	var m1_progress: Dictionary = scaled["battle"].complete_victory(0)["progress"]
	var m2: Dictionary = session.open(CHAPTER, "m2", {"progress": m1_progress}, _zero, trained)
	if not m2["ok"] or m2["battle"].unit(7)["level"] != 6:
		fail("A newly recruited formal member must use the party average level")
		return
	var snapshot: Dictionary = opened["battle"].snapshot()
	_draws = 0
	var restored: Dictionary = session.open(CHAPTER, "m1", {"snapshot": snapshot}, _zero, context)
	if not restored["ok"] or _draws != 0 or restored["battle"].snapshot() != snapshot:
		fail(
			"A battle snapshot must restore directly without applying context or drawing randomness"
		)
		return
	print("PASS deployment context Session: new battle applies it; snapshot restores directly")
	quit(0)


func _zero(_limit: int) -> int:
	_draws += 1
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
