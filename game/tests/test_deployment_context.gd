extends SceneTree

const Context = preload("res://gameplay/deployment_context.gd")


func _initialize() -> void:
	var units: Array = [
		unit(0, 5, 20, 4, 50),
		unit(0, 8, 30, 8, 90),
		unit(1, 50, 80, 20, 700),
		unit(2, 60, 90, 20, 800)
	]
	var original: Array = units.duplicate(true)
	var first: Variant = Context.accumulate(null, units)
	if not first is Dictionary:
		fail("A first successful statistics event must establish a context")
		return
	if (
		first["attributes"]["strength"] != 8
		or first["maxHp"] != 30
		or first["maxInternalLevel"] != 7
		or first["averageInternalLevel"] != 5
		or first["maxProficiency"] != 9
		or units != original
	):
		fail("Statistics must use C0 units, internal levels and proficiency tens without mutation")
		return
	var before: Dictionary = first.duplicate(true)
	var second: Variant = Context.accumulate(first, [unit(0, 3, 18, 2, 20)])
	if (
		second["attributes"]["strength"] != 8
		or second["maxHp"] != 30
		or second["maxInternalLevel"] != 7
		or second["averageInternalLevel"] != 1
		or second["maxProficiency"] != 9
		or first != before
	):
		fail("History keeps maxima while each event recomputes the average")
		return
	var high: Variant = Context.accumulate(null, [unit(0, 3, 18, 2, 1200)])
	if high["maxProficiency"] != 99 or Context.accumulate(null, [unit(1, 3, 18, 2, 20)]) != null:
		fail("Statistics cap proficiency units at 99 and cannot invent an empty C0 result")
		return
	print("PASS deployment context: C0 statistics, retained maxima and current average")
	quit(0)


func unit(faction: int, strength: int, max_hp: int, level: int, proficiency: int) -> Dictionary:
	return {
		"faction": faction,
		"attributes":
		{"strength": strength, "skill": 1, "speed": 2, "defense": 3, "magic": 4, "luck": 5},
		"maxHp": max_hp,
		"level": level,
		"proficiency": proficiency
	}


func fail(message: String) -> void:
	push_error(message)
	quit(1)
