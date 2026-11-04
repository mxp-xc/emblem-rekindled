extends RefCounted

const Matrix = preload("res://tests/test_m9_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")


# Controlled m9 boundaries shared by flow and phase-order tests.
static func prepare_boundary(
	context: Dictionary, round_number: int, mode: String = "quiet"
) -> Dictionary:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m9", prepared["source"], _zero)
	if not opened["ok"]:
		return opened
	while opened["battle"].round_number < round_number:
		var advanced: Dictionary = Rounds.advance(opened["battle"])
		if not advanced["ok"]:
			return advanced
	var state: Dictionary = opened["battle"].snapshot()
	state["events"]["opening"] = true
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 0:
			continue
		actor["move"] = 0
		if actor["id"] in [31, 32]:
			actor["x"] = 1 if actor["id"] == 31 else 18
			actor["y"] = 1 if actor["id"] == 31 else 18
			if mode in ["ai", "mixed"]:
				actor["inventory"] = actor["inventory"].filter(
					func(item: Dictionary) -> bool: return int(item["templateId"]) == 59
				)
				actor["equippedInstanceId"] = ""
	if mode in ["ordinary", "first", "last"]:
		if mode == "last":
			for actor: Dictionary in state["units"]:
				if int(actor["id"]) == 31:
					actor["hp"] = 0
					actor["visible"] = false
					actor["flags"] |= 1
		duel_state(state, 32 if mode == "last" else 31, mode != "ordinary")
	return Session.new().open(Matrix.CHAPTER, "m9", {"snapshot": state}, _zero)


static func duel_state(state: Dictionary, target: int, lethal: bool) -> void:
	for actor: Dictionary in state["units"]:
		if int(actor["id"]) not in [0, target]:
			continue
		actor["visible"] = true
		actor["flags"] &= ~1
		actor["x"] = 9
		actor["y"] = 9 if int(actor["id"]) == 0 else 10
		actor["hp"] = 1 if lethal and int(actor["id"]) == target else 60
		actor["maxHp"] = 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = (
				(30 if int(actor["id"]) == 0 else 0) if lethal else (30 if key == "defense" else 0)
			)
		if int(actor["id"]) == 0:
			actor["inventory"] = [{"id": "m9:controlled:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m9:controlled:sword"


static func _zero(_limit: int) -> int:
	return 0
