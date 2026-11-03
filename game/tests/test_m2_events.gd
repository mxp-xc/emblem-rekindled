extends SceneTree

const Matrix = preload("res://tests/test_m2_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
const WESTERN: Array = [63, 64, 65, 66, 68, 69, 30, 31]
const PURSUIT: Array = [82, 57, 69, 68, 31, 58, 32, 30]
var _draws: int = 0
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(0, 2), false)


func _run_contexts(contexts: Array, include_boundaries: bool) -> void:
	var directory: String = "user://m2_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(directory) != OK:
		_fail("Cannot claim a fresh owned m2 events directory")
		return
	_owned = directory
	for context: Dictionary in contexts:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(
			prepared["ok"], "Prepare true m2 event route: " + str(prepared.get("error"))
		):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m2", {"progress": prepared["progress"]}, _roll
		)
		if not _expect(opened["ok"], "Open true m2 event route: " + str(opened.get("error"))):
			_cleanup()
			return
		if not _phases(opened) or not _pursuit(opened) or not _settlement(opened, context):
			_cleanup()
			return
		print(
			(
				"PASS real m2 events dr%d: phases1/3/11, AI9 and fixed-route settlement"
				% context["route"]
			)
		)
	if include_boundaries:
		var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _roll)
		for boundary: Callable in [_combat, _map_magic, _priority]:
			var opened: Dictionary = Session.new().open(
				Matrix.CHAPTER, "m2", {"progress": prepared["progress"]}, _roll
			)
			if (
				not _expect(opened["ok"], "Independent real m2 combat boundary must open")
				or not boundary.call(opened)
			):
				_cleanup()
				return
	_cleanup()
	print("PASS real m2 events: selected contexts and requested combat boundaries")
	quit(0)


func _phases(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var initial: Dictionary = battle.snapshot()
	var cells: Dictionary = {}
	for actor: Dictionary in initial["units"]:
		cells[int(actor["id"])] = Vector2i(actor["x"], actor["y"])
	var expected_party: Array = []
	for slot: int in range(7):
		expected_party.append(opened["content"]["slots"][slot])
	if not _expect(
		(
			_texts(opened["content"], "opening") == [499, 500]
			and _texts(opened["content"], "party_arrival") == [501, 502]
		),
		"Actual m2 opening and first arrival use the captured source dialogues"
	):
		return false
	var arrivals: Dictionary = {}
	while battle.round_number < 12:
		var round_before: int = battle.round_number
		if battle.phase != 0:
			# Real phase queue, deliberately waiting instead of naturally fighting a whole map.
			var id: int = battle.automatic_actor()
			while id >= 0:
				if not _expect(
					battle.wait_unit(id)["ok"],
					"An automatic actor can finish its real phase by waiting"
				):
					return false
				id = battle.automatic_actor()
		var changed: Dictionary = battle.end_phase()
		if not _expect(changed["ok"], "Real m2 phase transition: " + str(changed.get("error"))):
			return false
		for event: Dictionary in changed["events"]:
			var ids: Array = []
			for arrival: Dictionary in event["arrivals"]:
				ids.append(int(arrival["unit"]))
			if not _expect(
				not arrivals.has(round_before), "Each source round emits one arrival batch once"
			):
				return false
			arrivals[round_before] = ids
		if battle.round_number == 2 and battle.phase == 0:
			if not _expect(
				battle.event_completed("party_arrival") and battle.can_save(),
				"First enemy-phase completion reveals the slots and returns to a stable player phase"
			):
				return false
			var store: RefCounted = Store.new(opened["content"], _owned.path_join("phase.json"))
			var encoded: Dictionary = store.encode(battle)
			if not _expect(encoded["ok"], "Actual post-arrival m2 state must encode"):
				return false
			_draws = 0
			var restored: Dictionary = store.decode(
				JSON.parse_string(JSON.stringify(encoded["record"])), _roll
			)
			if not _expect(
				(
					restored["ok"]
					and _draws == 0
					and restored["battle"].snapshot() == battle.snapshot()
				),
				"Real arrival flags and event markers survive JSON without RNG"
			):
				return false
	if not _expect(
		arrivals == {1: expected_party, 3: WESTERN, 11: [67, 35]},
		"Real m2 arrival targets and round boundaries must match source slots and IDs"
	):
		return false
	for actor: Dictionary in battle.snapshot()["units"]:
		if not _expect(
			(
				actor["visible"]
				and (int(actor["flags"]) & 1) == 0
				and Vector2i(actor["x"], actor["y"]) == cells[int(actor["id"])]
			),
			"All three arrivals reveal in place; animation offsets must not move final deployment"
		):
			return false
	var entrances: Array = opened["content"]["story"]["sequences"]["party_arrival"][0]["units"]
	for entrance: Dictionary in entrances:
		var cell: Vector2i = cells[int(entrance["unitId"])]
		if not _expect(
			(
				Vector2(entrance["to"][0], entrance["to"][1]) == Vector2(cell)
				and Vector2(entrance["from"][0], entrance["from"][1]) == Vector2(cell.x, cell.y - 3)
			),
			"Configured arrival %s uses captured cell %s" % [entrance, cell]
		):
			return false
	# Preserve the original stable state for independent controlled boundaries.
	return _expect(
		battle.restore_snapshot(initial)["ok"],
		"Reset to true m2 entry for independent event boundaries"
	)


func _pursuit(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var initial: Dictionary = battle.snapshot()
	var state: Dictionary = initial.duplicate(true)
	state["round"] = 9
	if not _expect(
		battle.restore_snapshot(state)["ok"],
		"Controlled round9 boundary remains a valid m2 snapshot"
	):
		return false
	while battle.phase != 2:
		if battle.phase != 0:
			var id: int = battle.automatic_actor()
			while id >= 0:
				battle.wait_unit(id)
				id = battle.automatic_actor()
		if not _expect(battle.end_phase()["ok"], "Enter actual ninth enemy phase"):
			return false
	for before: Dictionary in initial["units"]:
		var actor: Dictionary = battle.unit(before["id"])
		var expected_flags: int = int(before["flags"]) | (16 if before["id"] in PURSUIT else 0)
		if not _expect(
			(
				actor["flags"] == expected_flags
				and actor["visible"] == before["visible"]
				and actor["policy"] == (0 if before["id"] in PURSUIT else before["policy"])
			),
			"AI9 updates only captured strategies and preserves hidden flags, including IDs30/31/68/69"
		):
			return false
	return _expect(battle.restore_snapshot(initial)["ok"], "Reset after AI9 controlled boundary")


func _settlement(opened: Dictionary, context: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var content: Dictionary = opened["content"]
	var expected_texts: Array = [505, 506, 507, 488 if context["step"] == 2 else 508]
	if not _expect(
		(
			_texts(content, "victory") == expected_texts
			and content["story"]["routeChoices"].size() == 1
			and content["story"]["routeChoices"][0]["routeIndex"] == context["route"]
		),
		"Victory dialogue branches on actual battle step and offers only the retained route"
	):
		return false
	for step: Dictionary in content["story"]["sequences"]["victory"]:
		if not _expect(step["kind"] != "routeChoice", "m2 has no route selection menu"):
			return false
	var before: Dictionary = battle.snapshot()
	if not _expect(battle.win_with_assistance()["ok"], "Controlled victory enters real settlement"):
		return false
	var completed: Dictionary = battle.complete_victory(context["route"])
	if not _expect(completed["ok"], "m2 fixed route settlement must succeed"):
		return false
	var world: Dictionary = completed["progress"]
	var formal: Array = []
	for actor: Dictionary in world["party"]:
		formal.append(int(actor["id"]))
		if not _expect(
			(
				actor["formal"]
				and actor["visible"]
				and actor["flags"] == 0
				and actor["hp"] == actor["maxHp"]
				and actor["action"] == 0
			),
			"Settlement restores every formal member to legal world state and drops temporary troops"
		):
			return false
	var expected: Array = context["party"].duplicate()
	expected.append(7)
	formal.sort()
	expected.sort()
	var repeated: Dictionary = battle.complete_victory(context["route"])
	if not _expect(
		(
			world["route"] == context["route"]
			and world["worldStep"] == context["step"] + 1
			and world["worldNode"] == 2
			and world["completedBattle"] == "m2"
			and world["gold"] == before["gold"] + 1000
			and formal == expected
			and repeated["ok"]
			and repeated["alreadyComplete"]
			and repeated["progress"] == world
			and battle.gold == world["gold"]
		),
		"m2 retains route/world residence and grants exactly one 1000 reward"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("world_%d.json" % context["route"]))
	if not _expect(
		store.write_progress(world)["ok"] and store.write_slot(2, world)["ok"],
		"Actual completed m2 world record writes to owned continue and named slot"
	):
		return false
	var continued: Dictionary = store.read()
	var slotted: Dictionary = store.read_slot(2)
	return _expect(
		(
			continued["ok"]
			and slotted["ok"]
			and continued["progress"] == slotted["progress"]
			and continued["progress"]["route"] == context["route"]
			and continued["content"]["story"]["battleNumber"] == context["step"] + 1
		),
		"Continue and slot restore actual world roster and completed m2's step-1 projection"
	)


func _combat(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	# Controlled combat boundary: legal positions/equipment and capped attributes,
	# not a natural full-map battle. Production attack_unit resolves both dialogues.
	for actor: Dictionary in state["units"]:
		if actor["id"] == 82:
			actor["x"] = 17
			actor["y"] = 11
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["attributes"]["defense"] = 30
			actor["attributes"]["magic"] = 30
			actor["inventory"] = []
			actor["equippedInstanceId"] = ""
		if actor["id"] == 7:
			actor["attributes"]["magic"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Legal actual m2 ordinary boss combat setup"
	):
		return false
	var library := Clips.new(opened["content"])
	if not _expect(
		library.preload_pair(battle.attack_preview(7, 82))["ok"],
		"Actual m2 normal pair must have real complete clips"
	):
		return false
	var first: Dictionary = battle.attack_unit(7, 82)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == ["boss_first_combat"]
			and first["retirements"].is_empty()
			and battle.event_completed("boss_first_combat")
			and (int(battle.unit(82)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _texts(opened["content"], "boss_first_combat") == [503]
		),
		"Actual ordinary attack triggers source503 once and prepares real battle presentation"
	):
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["action"] = 0
	var store: RefCounted = Store.new(opened["content"], _owned.path_join("boss.json"))
	var saved: Dictionary = {
		"version": 1, "chapterId": "chapter_1", "battleId": "m2", "state": state
	}
	_draws = 0
	var restored: Dictionary = store.decode(JSON.parse_string(JSON.stringify(saved)), _roll)
	if not _expect(
		restored["ok"] and _draws == 0, "Actual first-combat once marker survives JSON restore"
	):
		return false
	battle = restored["battle"]
	var second: Dictionary = battle.attack_unit(7, 82)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"Restored normal combat cannot repeat source503"
	):
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["action"] = 0
			actor["attributes"]["magic"] = 30
		if actor["id"] == 82:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Controlled real boss lethal boundary must restore"
	):
		return false
	var killed: Dictionary = battle.attack_unit(7, 82)
	return _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [{"unitId": 82, "beforeRetirement": ["boss_death"], "afterRetirement": []}]
			)
			and battle.event_completed("boss_death")
			and battle.outcome.get("kind") == "victory"
			and library.prepare(killed)["ok"]
			and _texts(opened["content"], "boss_death") == [504]
		),
		"Actual ordinary boss kill schedules source504 before map retirement and wins"
	)


func _map_magic(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 3
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["inventory"] = [{"id": "m2:map", "templateId": 46, "durability": 3}]
			actor["equippedInstanceId"] = "m2:map"
			actor["attributes"]["magic"] = 30
		if actor["id"] == 82:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Legal real m2 map-magic controlled boundary"
	):
		return false
	var cast: Dictionary = battle.cast_map_attack(7, "m2:map")
	return _expect(
		(
			cast["ok"]
			and battle.unit(82)["hp"] == 0
			and cast["storyBefore"].is_empty()
			and cast["storyAfter"].is_empty()
			and not battle.event_completed("boss_first_combat")
			and not battle.event_completed("boss_death")
			and (int(battle.unit(82)["flags"]) & 4) == 0
			and battle.outcome.get("kind") == "victory"
		),
		"Actual m2 map-magic boss kill skips ordinary503/504 without consuming once markers"
	)


func _priority(opened: Dictionary) -> bool:
	# Outcome queries operate on actual m2 business units. These deliberately
	# probe source transitional states (visible HP0), not valid save snapshots.
	var events := Events.new(opened["content"])
	for required: int in [0, 7]:
		var units: Array = opened["battle"].snapshot()["units"]
		for actor: Dictionary in units:
			if actor["id"] == required:
				actor["hp"] = 0
				actor["visible"] = true
		if not _expect(
			events.outcome(units).is_empty(), "Visible required HP0 is still the source transition"
		):
			return false
		for actor: Dictionary in units:
			if actor["id"] == required:
				actor["visible"] = false
		if not _expect(
			events.outcome(units).get("kind") == "defeat",
			"Required0/7 retired with live boss must lose"
		):
			return false
		for actor: Dictionary in units:
			if actor["id"] == 82:
				actor["hp"] = 0
		if not _expect(
			events.outcome(units).get("kind") == "victory",
			"Boss victory has priority over required0/7 death"
		):
			return false
	return true


func _texts(content: Dictionary, sequence: String) -> Array:
	var indices: Array = []
	for step: Dictionary in content["story"]["sequences"][sequence]:
		if step["kind"] == "dialogue":
			indices.append(int(step["text"]["sourceTextIndex"]))
	return indices


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _cleanup() -> void:
	if _owned.is_empty():
		return
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
