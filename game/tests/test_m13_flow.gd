extends SceneTree

const Terminal = preload("res://tests/test_chapter_session.gd")
const Events = preload("res://gameplay/battle_events.gd")
const NPCS: Array[int] = [10, 18, 16, 17, 14, 11, 13, 12, 15]
const ALLY_PURSUIT: Array[int] = [10, 18, 16, 17, 11, 13, 12, 15]
const ENEMY_PURSUIT: Array[int] = [
	63, 60, 61, 62, 42, 33, 43, 34, 32, 31, 30, 36, 41, 37, 39, 40, 35, 38
]
# Original p13 deployment slots, in source order; coordinates do not depend on route.
const SLOTS: Array = [
	[7, 18, 2], [1, 18, 1], [6, 17, 2], [5, 16, 2], [4, 15, 2], [3, 17, 1], [0, 15, 1], [2, 16, 1]
]
const WAVES: Array = [[2, [46, 47, 48, 86]], [3, [44, 45, 81]], [6, [57, 59, 91, 52, 53, 83]]]


func _initialize() -> void:
	for route: int in [4, 7]:
		var opened: Dictionary = Terminal.prepare_terminal(
			route, func(_limit: int) -> int: return 0
		)
		if not _expect(
			opened["ok"],
			"Actual m9 settlement opens m13 route %d: %s" % [route, opened.get("error", "")]
		):
			return
		if (
			not _roster(opened, route)
			or not _waves(opened)
			or not _pursuit(opened)
			or not _outcomes(opened)
			or not _teleport(opened)
		):
			return
	print(
		(
			"PASS actual m13 flow: two rosters/slots, native queues, phase pursuit, "
			+ "defeat priority, teleport58"
		)
	)
	quit(0)


func _roster(opened: Dictionary, route: int) -> bool:
	var battle: RefCounted = opened["battle"]
	var units: Array = battle.snapshot()["units"]
	var counts: Array[int] = [0, 0, 0]
	var formal: Array[int] = []
	var hidden: int = 0
	for actor: Dictionary in units:
		counts[int(actor["faction"])] += 1
		if not actor["visible"]:
			hidden += 1
		if actor["formal"]:
			formal.append(int(actor["id"]))
	var expected: Array = [9, 0, 2, 4, 5, 1, 6, 7] if route == 4 else [9, 0, 5, 4, 2, 8, 3, 7]
	if not _expect(
		units.size() == 53 and counts == [8, 9, 36] and formal == expected,
		(
			"m13 preserves original 53-unit faction counts and native formal traversal for route %d"
			% route
		)
	):
		return false
	var recruits: Array = [0, 9, 2, 4, 5, 1, 6, 7] if route == 4 else [0, 9, 5, 4, 2, 8, 3, 7]
	for slot: Array in SLOTS:
		var actor: Dictionary = battle.unit(recruits[slot[0]])
		if not _expect(
			actor["x"] == slot[1] and actor["y"] == slot[2],
			"Recruit order binds each actual m13 deployment slot"
		):
			return false
	return _expect(
		(
			battle.commander_id == -1
			and battle.command_policy == 5
			and hidden == 13
			and battle.unit(13)["visible"]
		),
		"None mode preserves inherited policy and the original thirteen hidden enemies"
	)


func _waves(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var initial: Dictionary = battle.snapshot()
	for wave: Array in WAVES:
		var state: Dictionary = initial.duplicate(true)
		state["round"] = wave[0]
		if not _expect(
			battle.restore_snapshot(state)["ok"],
			"Actual wave fixture restores its player-phase state"
		):
			return false
		var advanced: Dictionary = _round(battle)
		if not advanced["ok"]:
			return false
		var emitted: Array = advanced["events"]
		if not _expect(
			emitted.size() == 1 and emitted[0].get("arrivalMode") == "nativeQueue",
			"Each actual round 2/3/6 wave emits its native presentation queue"
		):
			return false
		var queued: Array[int] = []
		for arrival: Dictionary in emitted[0]["arrivalQueue"]:
			queued.append(int(arrival["unit"]))
		if not _expect(
			queued == wave[1], "Actual reinforcement queues retain the original unit order"
		):
			return false
		for id: int in wave[1]:
			if not _expect(battle.unit(id)["visible"], "Unblocked original reinforcement arrives"):
				return false
		state = battle.snapshot()
		state["round"] = wave[0]
		if not _expect(
			battle.restore_snapshot(state)["ok"],
			"Consumed event state restores without another arrival"
		):
			return false
		advanced = _round(battle)
		if (
			not advanced["ok"]
			or not _expect(
				advanced["events"].is_empty(), "Saved consumed reinforcement events never replay"
			)
		):
			return false
	# The edge origin (24,6) has only three in-bounds neighbours. Occupy all four cells.
	var blocked: Dictionary = initial.duplicate(true)
	blocked["round"] = 2
	var positions: Array = [Vector2i(24, 6), Vector2i(23, 6), Vector2i(24, 5), Vector2i(24, 7)]
	var index: int = 0
	for actor: Dictionary in blocked["units"]:
		if actor["formal"] and index < positions.size():
			actor["x"] = positions[index].x
			actor["y"] = positions[index].y
			index += 1
	if not _expect(
		battle.restore_snapshot(blocked)["ok"],
		"Blocked native queue uses valid occupied tactical cells"
	):
		return false
	var advanced: Dictionary = _round(battle)
	if not advanced["ok"]:
		return false
	var queue: Array = advanced["events"][0]["arrivalQueue"]
	return _expect(
		(
			queue.size() == 4
			and queue[0]["unit"] == 46
			and not queue[0]["revealed"]
			and not battle.unit(46)["visible"]
			and battle.unit(47)["visible"]
		),
		"A fully blocked arrival stays hidden while the remaining original queue continues"
	)


func _pursuit(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var fresh: Dictionary = Terminal.prepare_terminal(
		int(opened["sourceProgress"]["route"]), func(_limit: int) -> int: return 0
	)
	if not _expect(fresh["ok"], "Pursuit starts from actual unmodified m13 deployment"):
		return false
	var initial: Dictionary = fresh["battle"].snapshot()
	initial["round"] = 8
	if not _expect(
		battle.restore_snapshot(initial)["ok"], "Round-eight actual deployment restores"
	):
		return false
	var before: Dictionary = _policies(battle)
	var advanced: Dictionary = _round(battle)
	if (
		not advanced["ok"]
		or not _expect(
			_policies(battle) == before, "Round eight leaves both pursuit groups unchanged"
		)
	):
		return false
	if not _expect(
		battle.end_phase()["ok"] and battle.phase == 1, "Round nine reaches the allied phase first"
	):
		return false
	for id: int in ALLY_PURSUIT:
		if not _expect(
			(
				(battle.unit(id)["flags"] & 16) != 0
				and (battle.unit(id)["policy"] & 4) == 0
				and battle.unit(id)["visible"] == before[id][2]
			),
			"Round-nine allied pursuit changes only flags/policy and preserves hidden status"
		):
			return false
	for id: int in ENEMY_PURSUIT:
		if not _expect(
			(battle.unit(id)["flags"] & 16) == (before[id][0] & 16),
			"Enemy pursuit waits until its own ninth-round phase"
		):
			return false
	if (
		not _drain(battle)
		or not _expect(
			battle.end_phase()["ok"] and battle.phase == 2, "Round nine then reaches enemy actions"
		)
	):
		return false
	for id: int in ENEMY_PURSUIT:
		if not _expect(
			(battle.unit(id)["flags"] & 16) != 0 and (battle.unit(id)["policy"] & 4) == 0,
			"Every original eligible monster enters pursuit before round-nine enemy actions"
		):
			return false
	if not _expect(
		_policies(battle)[14] == before[14], "NPC14 is excluded from the pursuit change"
	):
		return false
	if (
		not _drain(battle)
		or not _expect(
			battle.end_phase()["ok"] and battle.phase == 0,
			"Ninth-round enemy phase completes normally"
		)
	):
		return false
	var settled: Dictionary = _policies(battle)
	for round_number: int in [10, 11]:
		advanced = _round(battle)
		if (
			not advanced["ok"]
			or not _expect(
				(
					_policies(battle) == settled
					and battle.outcome.is_empty()
					and battle.round_number == round_number + 1
				),
				"Rounds ten and eleven preserve pursuit without an extra automatic defeat"
			)
		):
			return false
	return true


func _policies(battle: RefCounted) -> Dictionary:
	var values: Dictionary = {}
	for actor: Dictionary in battle.snapshot()["units"]:
		if actor["id"] in ALLY_PURSUIT or actor["id"] in ENEMY_PURSUIT or actor["id"] == 14:
			values[int(actor["id"])] = [int(actor["flags"]), int(actor["policy"]), actor["visible"]]
	return values


func _outcomes(opened: Dictionary) -> bool:
	var rules: RefCounted = Events.new(opened["content"])
	for survivor: int in [14, 10, -1]:
		var units: Array = opened["battle"].snapshot()["units"]
		for actor: Dictionary in units:
			if actor["id"] == 80 or (actor["id"] in NPCS and actor["id"] != survivor):
				actor["hp"] = 0
				actor["visible"] = false
		var outcome: Dictionary = rules.outcome(units)
		if not _expect(
			outcome.get("kind") == ("defeat" if survivor == -1 else "victory"),
			"Only14/only10 survives can win; all NPC retirements precede the boss victory"
		):
			return false
		for actor: Dictionary in units:
			if actor["id"] == 0:
				actor["hp"] = 0
				actor["visible"] = false
		outcome = rules.outcome(units)
		if not _expect(
			outcome.get("kind") == "defeat" and outcome.get("unit") == 0,
			"Alm's final retirement takes priority over both NPC and boss outcomes"
		):
			return false
	return true


func _teleport(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 1
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["inventory"] = [{"id": "m13_teleport58", "templateId": 58, "durability": 15}]
			actor["equippedInstanceId"] = ""
			actor["action"] = 0
			actor["x"] = 15
			actor["y"] = 1
		elif actor["id"] == 0:
			actor["x"] = 16
			actor["y"] = 1
		elif actor["visible"] and actor["x"] in [15, 16] and actor["y"] == 1:
			actor["visible"] = false
	if not _expect(
		battle.restore_snapshot(state)["ok"],
		"A legal original staff holder restores with teleport58"
	):
		return false
	var field: Dictionary = battle.teleport_field(9, 0, "m13_teleport58")
	if not _expect(not field.is_empty(), "m13 adds no gate that disables legal teleport58"):
		return false
	var destination: Vector2i = field.keys()[0]
	var result: Dictionary = battle.teleport_unit(9, 0, "m13_teleport58", destination)
	return _expect(
		(
			result["ok"]
			and Vector2i(battle.unit(0)["x"], battle.unit(0)["y"]) == destination
			and battle.unit(9)["action"] == 2
		),
		"The actual m13 teleport command commits destination and staff action"
	)


func _round(battle: RefCounted) -> Dictionary:
	for expected: int in [1, 2, 0]:
		var result: Dictionary = battle.end_phase()
		if not _expect(
			result["ok"] and battle.phase == expected,
			"Actual m13 advances each phase: " + str(result)
		):
			return {"ok": false}
		if expected == 0:
			return result
		if not _drain(battle):
			return {"ok": false}
	return {"ok": false}


func _drain(battle: RefCounted) -> bool:
	while battle.automatic_actor() >= 0:
		if not _expect(
			battle.wait_unit(battle.automatic_actor())["ok"],
			"Automatic actors finish normally without introducing fixture combat"
		):
			return false
	return true


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
