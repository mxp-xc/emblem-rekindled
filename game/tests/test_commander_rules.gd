extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Matrix = preload("res://tests/test_m2_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _draws: int = 0


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, _roll)
	if not _expect(opened["ok"], "The commander rules test must open the real chapter"):
		return
	if not _custom_declaration(opened):
		return
	for stage: Dictionary in [
		{"battle": "m1", "opening": [6], "active": [9, 0, 6], "arrival": "allied_arrival"},
		{"battle": "m2", "opening": [7], "active": [9, 0, 6, 7], "arrival": "party_arrival"}
	]:
		if not _expect(
			opened["battle"].win_with_assistance()["ok"], "Prepare a real world frontier"
		):
			return
		var completed: Dictionary = opened["battle"].complete_victory(0)
		if not _expect(
			completed["ok"], "Complete the configured route without natural full-map play"
		):
			return
		opened = Session.new().open(
			CHAPTER, stage["battle"], {"progress": completed["progress"]}, _roll
		)
		if not _expect(opened["ok"], "Open the actual commander entry " + stage["battle"]):
			return
		if not _entry(opened, stage["opening"], stage["active"], stage["arrival"]):
			return
	if not _retired_commander_record(opened):
		return
	print("PASS commander rules: opening, arrivals, roster order, guards and JSON")
	quit(0)


func _late_entry() -> bool:
	# This existing helper supplies a validated late route from real profiles and
	# a legal synthetic world point; it does not claim natural play through unavailable maps.
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[2], _roll)
	if not _expect(prepared["ok"], "Prepare the declared late m2 roster"):
		return false
	var opened: Dictionary = Session.new().open(
		CHAPTER, "m2", {"progress": prepared["progress"]}, _roll
	)
	if not _expect(opened["ok"], "Open the actual late-context m2 roster"):
		return false
	return _entry(opened, [7], [9, 0, 2, 4, 5, 1, 6, 7], "party_arrival")


func _entry(opened: Dictionary, initial: Array, active: Array, arrival: String) -> bool:
	var battle: RefCounted = opened["battle"]
	if not _expect(
		_ids(battle) == initial and not battle.unit(0)["visible"] and battle.unit(0)["hp"] > 0,
		"The real opening exposes only its visible declared recruit; hidden living0 is unavailable"
	):
		return false
	if not _reject(battle, 0) or not _reject(battle, 9999):
		return false
	if not _expect(
		(
			battle.configure_commander(int(initial[0]), true, true)["ok"]
			and battle.command_policy == 5
		),
		"The declared visible opening commander can commit both policy choices"
	):
		return false
	battle.complete_event("opening")
	if not _expect(
		_ids(battle) == initial, "Opening completion cannot reveal hidden roster members"
	):
		return false
	if not _reject(battle, 0) or not _first_arrival(battle):
		return false
	if not _expect(
		battle.event_completed(arrival) and _ids(battle) == active,
		"After the real first wave all visible formal members follow native unitOrder"
	):
		return false
	for id: int in active:
		if not _expect(
			battle.configure_commander(id, id % 2 == 0, true)["ok"],
			"An arrived formal member can be selected, including late recruits: " + str(id)
		):
			return false
		var encoded: Dictionary = Store.new(opened["content"]).encode(battle)
		if not _expect(encoded["ok"], "Each selected active commander is a stable save state"):
			return false
		_draws = 0
		var decoded: Dictionary = Store.new(opened["content"]).decode(
			JSON.parse_string(JSON.stringify(encoded["record"])), _roll
		)
		if not _expect(
			(
				decoded["ok"]
				and _draws == 0
				and decoded["battle"].commander_id == id
				and decoded["battle"].command_policy == battle.command_policy
				and _ids(decoded["battle"]) == active
			),
			"JSON restore preserves commander, policy and opening-complete eligibility without RNG"
		):
			return false
	var checked_enemy: bool = false
	for actor: Dictionary in battle.snapshot()["units"]:
		if actor["faction"] == 2 and actor["visible"] and not checked_enemy:
			if not _reject(battle, int(actor["id"])):
				return false
			checked_enemy = true
		if actor["faction"] == 0 and actor["visible"] and not actor["formal"]:
			if not _reject(battle, int(actor["id"])):
				return false
	return _guards(battle, int(initial[0]))


func _first_arrival(battle: RefCounted) -> bool:
	while battle.round_number == 1:
		if battle.phase != 0:
			if not _reject(battle, battle.commander_id):
				return false
			var id: int = battle.automatic_actor()
			while id >= 0:
				if not _expect(
					battle.wait_unit(id)["ok"], "Finish the actual automatic queue by waiting"
				):
					return false
				id = battle.automatic_actor()
		if not _expect(battle.end_phase()["ok"], "Advance the actual phase and arrival event"):
			return false
	return _expect(
		battle.phase == 0 and battle.round_number == 2, "The first wave returns to player phase"
	)


func _retired_commander_record(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	if not _expect(battle.configure_commander(9, true, true)["ok"], "Select the arrived formal9"):
		return false
	var before: Dictionary = battle.snapshot()
	var occupied: Dictionary = {}
	for unit: Dictionary in before["units"]:
		if unit["visible"] and unit["hp"] > 0 and unit["id"] not in [9, 35]:
			occupied[Vector2i(unit["x"], unit["y"])] = true
	var cell := Vector2i(-1, -1)
	for y: int in range(opened["content"]["map"]["height"]):
		for x: int in range(opened["content"]["map"]["width"] - 1):
			var point := Vector2i(x, y)
			if not occupied.has(point) and not occupied.has(point + Vector2i.RIGHT):
				cell = point
				break
		if cell.x >= 0:
			break
	for unit: Dictionary in before["units"]:
		if unit["id"] == 9:
			unit["hp"] = 1
			unit["x"] = cell.x
			unit["y"] = cell.y
		elif unit["id"] == 35:
			unit["x"] = cell.x + 1
			unit["y"] = cell.y
			unit["visible"] = true
			unit["flags"] &= ~1
			unit["inventory"] = [
				{"id": "commander-record:fire", "templateId": 40, "durability": 10}
			]
			unit["equippedInstanceId"] = "commander-record:fire"
	if not _expect(
		battle.restore_snapshot(before)["ok"], "Restore legal HP1 and adjacent positions"
	):
		return false
	if not _expect(battle.end_phase()["ok"], "Begin the actual next automatic phase"):
		return false
	while battle.phase != 2:
		while battle.automatic_actor() >= 0:
			battle.wait_unit(battle.automatic_actor())
		if not _expect(battle.end_phase()["ok"], "Reach the actual enemy phase"):
			return false
	var combat: Dictionary = battle.attack_unit(35, 9)
	if not _expect(
		combat["ok"] and battle.unit(9)["hp"] == 0 and not battle.unit(9)["visible"],
		"A real ordinary combat command must retire the selected non-required commander"
	):
		return false
	while battle.automatic_actor() >= 0:
		battle.wait_unit(battle.automatic_actor())
	if not _expect(
		battle.end_phase()["ok"] and battle.can_save() and battle.outcome.is_empty(),
		"Living0/7 and boss keep this an ordinary stable player save boundary"
	):
		return false
	var state: Dictionary = battle.snapshot()
	if not _reject(battle, 9):
		return false
	if not _expect(
		battle.commander_id == 9 and battle._commander().is_empty(),
		"Death preserves historical selection while removing the commander's combat contribution"
	):
		return false
	var encoded: Dictionary = Store.new(opened["content"]).encode(battle)
	if not _expect(
		encoded["ok"], "A real retired commander must remain encodable: " + str(encoded)
	):
		return false
	_draws = 0
	var restored: Dictionary = Store.new(opened["content"]).decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	return _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == state,
		"JSON restore keeps the actual retired commander and complete battle without RNG"
	)


func _guards(battle: RefCounted, safe_id: int) -> bool:
	if not _expect(
		battle.configure_commander(safe_id, false, false)["ok"], "Select a surviving test commander"
	):
		return false
	var before: Dictionary = battle.snapshot()
	var actor: Dictionary = battle.unit(safe_id)
	if not _expect(
		battle.move_unit(safe_id, Vector2i(actor["x"], actor["y"]))["ok"],
		"A real pending move holds command configuration"
	):
		return false
	if (
		not _reject(battle, safe_id)
		or not _expect(battle.cancel_move()["ok"], "Cancel the pending move")
	):
		return false
	var dead: Dictionary = before.duplicate(true)
	for unit: Dictionary in dead["units"]:
		if unit["id"] == 9:
			unit["hp"] = 0
			unit["visible"] = false
			unit["flags"] |= 1
	if not _expect(
		battle.restore_snapshot(dead)["ok"], "A retired non-required member is valid business state"
	):
		return false
	if not _reject(battle, 9):
		return false
	var rejected_before: Dictionary = battle.snapshot()
	dead["commander"] = 9999
	_draws = 0
	if not _expect(
		(
			not battle.restore_snapshot(dead)["ok"]
			and battle.snapshot() == rejected_before
			and _draws == 0
		),
		"An unknown historical commander remains invalid and cannot partially restore"
	):
		return false
	if not _expect(battle.restore_snapshot(before)["ok"], "Restore the independent guard boundary"):
		return false
	if not _expect(battle.win_with_assistance()["ok"], "Enter an actual completed outcome"):
		return false
	if not _reject(battle, safe_id):
		return false
	return _expect(
		battle.restore_snapshot(before)["ok"], "Restore the completed-outcome test boundary"
	)


func _custom_declaration(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"].duplicate(true)
	var units: Array = [opened["battle"].unit(0), opened["battle"].unit(9)]
	var declared: Dictionary = units[1].duplicate(true)
	declared["id"] = 300
	declared["x"] = 0
	declared["y"] = 0
	declared["inventory"] = []
	declared["equippedInstanceId"] = ""
	units.append(declared)
	content["units"] = units
	content["unitOrder"] = [9, 300, 0]
	content["spawns"] = []
	content["story"]["outcomeRules"]["checks"] = []
	for step: Dictionary in content["story"]["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			step["candidates"] = [300, 0]
			step["defaultCommanderId"] = 300
	var battle: RefCounted = Battle.new(content, _roll, false)
	if not _expect(
		_ids(battle).is_empty(), "A non-initialized battle has no fabricated candidates"
	):
		return false
	var state: Dictionary = battle.snapshot()
	state["units"] = units
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Declare a custom high-ID formal source9 prototype"
	):
		return false
	if not _expect(
		_ids(battle) == [300, 0], "Opening order uses the custom declaration, not unitOrder"
	):
		return false
	if not _reject(battle, 9):
		return false
	state = battle.snapshot()
	state["commander"] = 9
	if not _expect(
		battle.restore_snapshot(state)["ok"],
		"A valid saved commander need not be an opening candidate"
	):
		return false
	battle.complete_event("opening")
	if not _expect(
		_ids(battle) == [9, 300, 0], "An active declared high ID follows native roster order"
	):
		return false
	if not _expect(
		battle.configure_commander(300, true, true)["ok"],
		"High-ID members remain selectable after opening"
	):
		return false
	state = JSON.parse_string(JSON.stringify(battle.snapshot()))
	var restored: RefCounted = Battle.new(content, _roll, false)
	_draws = 0
	return _expect(
		(
			restored.restore_snapshot(state)["ok"]
			and _draws == 0
			and restored.commander_id == 300
			and restored.command_policy == 5
			and _ids(restored) == [9, 300, 0]
		),
		"Custom declared high-ID commander and active eligibility survive JSON without RNG"
	)


func _ids(battle: RefCounted) -> Array:
	return battle.command_configuration()["candidates"].map(
		func(candidate: Dictionary) -> int: return int(candidate["id"])
	)


func _reject(battle: RefCounted, id: int) -> bool:
	var before: Dictionary = battle.snapshot()
	_draws = 0
	return _expect(
		(
			not battle.configure_commander(id, true, true)["ok"]
			and battle.snapshot() == before
			and _draws == 0
		),
		"An ineligible or blocked commander must reject without state or random changes: " + str(id)
	)


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
