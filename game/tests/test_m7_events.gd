extends SceneTree

const Matrix = preload("res://tests/test_m7_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
# Oracle: temp/m3-m7/events/{summary.json,m7-z.txt,m7-k.txt}.
# Automatic turns wait; combat and occupancy boundaries are explicit fixtures.
const QUEUE: Array[int] = [107, 108, 109, 110]
var _draws: int = 0
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(0, 1), false)


func _run_contexts(contexts: Array, include_boundaries: bool) -> void:
	_owned = "user://m7_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim fresh owned m7 event directory")
		return
	var combat_source: Dictionary = {}
	for context: Dictionary in contexts:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare m7 event context: " + str(prepared.get("error"))):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m7", prepared["source"], _roll)
		if not _expect(opened["ok"], "Open actual m7 events: " + str(opened.get("error"))):
			_cleanup()
			return
		if context["route"] == 3:
			combat_source = opened
		if (
			not _opening(opened["content"])
			or not _phases(opened)
			or not _settlement(opened, context)
			or not _priority(opened)
		):
			_cleanup()
			return
		print("PASS actual m7 events dr%d step%d" % [context["route"], context["step"]])
	if include_boundaries:
		for boundary: Callable in [_combat, _native_first_flag, _map_magic, _blocked_queue]:
			var forked: Dictionary = _fork(combat_source)
			if not forked["ok"] or not boundary.call(forked):
				_cleanup()
				return
	_cleanup()
	print("PASS actual m7 events: selected routes and requested combat boundaries")
	quit(0)


func _opening(content: Dictionary) -> bool:
	var sequence: Array = content["story"]["sequences"]["opening"]
	var focus: Dictionary = {}
	var objective: Dictionary = {}
	var commander: Dictionary = {}
	var after_dialogue: int = -1
	for step: Dictionary in sequence:
		match step["kind"]:
			"focus":
				focus = step
			"objective":
				objective = step
			"commanderSetup":
				commander = step
			"dialogue":
				after_dialogue = step.get("sourceWaitTicksAfter", -1)
	return _expect(
		(
			_cell(focus["cell"]) == Vector2i(11, 1)
			and focus.get("sourceWaitTicks") == 12
			and _dialogues(content, "opening") == [[550, 86], [551, 5]]
			and after_dialogue == 10
			and objective["text"]["sourceTextIndex"] == 163
			and _ints(commander["candidates"]) == [5]
			and commander["defaultCommanderId"] == 5
		),
		"Opening focuses11,1/waits12,550boss/551new5/waits10,objective163 and commander5"
	)


func _phases(opened: Dictionary) -> bool:
	var fresh: Dictionary = _fork(opened)
	if not fresh["ok"]:
		return false
	var battle: RefCounted = fresh["battle"]
	var content: Dictionary = opened["content"]
	var by_round: Dictionary = {}
	for event: Dictionary in content["story"]["turnEvents"]:
		by_round[int(event["afterEnemyPhaseOfRound"])] = event
	if not _expect(
		by_round.size() == 2 and by_round.has(2) and by_round.has(4),
		"Only native round2/4 arrivals exist"
	):
		return false
	var party: Array[int] = []
	for slot: int in range(6):
		party.append(int(content["slots"][slot]))
	var second: Dictionary = by_round[2]
	var fourth: Dictionary = by_round[4]
	if not _expect(
		(
			_ints(second["unitIds"]) == party
			and 5 not in party
			and _ints(fourth["unitIds"]) == QUEUE
			and fourth.get("arrivalMode") == "nativeQueue"
			and _dialogues(content, second["sequence"]) == [[552, 0], [553, 5], [554, 0], [555, 86]]
			and _dialogues(content, fourth["sequence"]) == [[556, 5]]
		),
		"Round2 selects six old slots excluding new5;round4 preserves107..110 source traversal then556"
	):
		return false
	var sequence: Array = content["story"]["sequences"][second["sequence"]]
	var entrances: Dictionary = sequence[0]
	if not _expect(
		(
			entrances["kind"] == "parallelEntrances"
			and _cell(entrances["focus"]) == Vector2i(10, 23)
			and entrances["units"].size() == 6
		),
		"Round2 focuses10,23 for six parallel southern entrances"
	):
		return false
	for index: int in range(6):
		var entry: Dictionary = entrances["units"][index]
		var actor: Dictionary = battle.unit(party[index])
		if not _expect(
			(
				entry["unitId"] == party[index]
				and _cell(entry["to"]) == Vector2i(actor["x"], actor["y"])
				and _cell(entry["from"]) == Vector2i(actor["x"], actor["y"] + 3)
			),
			"Slot entrance keeps actual cell and offsets origin three rows south"
		):
			return false
	var restored: Dictionary = _roundtrip(content, battle, "before_arrivals")
	if not restored["ok"]:
		return false
	battle = restored["battle"]
	var emitted: Dictionary = {2: 0, 4: 0}
	while battle.round_number < 6:
		var previous: int = battle.round_number
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(advanced["ok"], "Advance actual m7 phases with controlled automatic waits"):
			return false
		for event: Dictionary in advanced["events"]:
			if not _expect(
				emitted.has(previous) and event["sequence"] == by_round[previous]["sequence"],
				"Only completed old round2/4 emits its source event"
			):
				return false
			emitted[previous] += 1
			if previous == 2:
				if not _expect(
					event["arrivals"].size() == 6 and battle.unit(5)["visible"],
					"Six old slots arrive;new5 remains visible"
				):
					return false
			else:
				var actual: Array[int] = []
				for entry: Dictionary in event["arrivalQueue"]:
					actual.append(int(entry["unit"]))
				if not _expect(
					actual == QUEUE and event["arrivalMode"] == "nativeQueue",
					"Round4 emits complete native queue before authored dialogue"
				):
					return false
		for timing: int in [2, 4]:
			if not _expect(
				battle.event_completed(by_round[timing]["id"]) == (previous >= timing),
				"Once marker follows original old-round boundary"
			):
				return false
		restored = _roundtrip(content, battle, "round_%d" % battle.round_number)
		if not restored["ok"]:
			return false
		battle = restored["battle"]
	return _expect(
		emitted == {2: 1, 4: 1}, "Cold JSON before and after both waves cannot replay either event"
	)


func _blocked_queue(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var content: Dictionary = opened["content"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 4
	# Source107 appears in place;108 is displaced upward because its left is
	# already occupied by107;109 stays hidden when all four neighbours block.
	var points: Dictionary = {
		107: Vector2i(6, 6),
		108: Vector2i(7, 6),
		109: Vector2i(10, 10),
		110: Vector2i(15, 15),
		39: Vector2i(7, 6),
		42: Vector2i(10, 10),
		44: Vector2i(9, 10),
		45: Vector2i(10, 9),
		51: Vector2i(10, 11),
		52: Vector2i(11, 10)
	}
	for actor: Dictionary in state["units"]:
		if points.has(int(actor["id"])):
			actor["x"] = points[int(actor["id"])].x
			actor["y"] = points[int(actor["id"])].y
			actor["visible"] = actor["id"] not in QUEUE
			actor["flags"] = 0 if actor["visible"] else 1
	if not _expect(
		battle.restore_snapshot(state)["ok"],
		"Restore controlled occupancy using actual m7 actors and event"
	):
		return false
	var advanced: Dictionary = Rounds.advance(battle)
	var expected: Array = [
		{"unit": 107, "from": Vector2i(6, 6), "to": Vector2i(6, 6), "revealed": true},
		{"unit": 108, "from": Vector2i(7, 6), "to": Vector2i(7, 5), "revealed": true},
		{"unit": 109, "from": Vector2i(10, 10), "to": Vector2i(10, 10), "revealed": false},
		{"unit": 110, "from": Vector2i(15, 15), "to": Vector2i(15, 15), "revealed": true}
	]
	if not _expect(
		(
			advanced["ok"]
			and advanced["events"].size() == 1
			and advanced["events"][0]["arrivalQueue"] == expected
			and advanced["events"][0]["arrivals"].size() == 3
		),
		"Native queue retains source order,in-place107,upward108 and blocked hidden109"
	):
		return false
	var restored: Dictionary = _roundtrip(content, battle, "blocked_queue")
	if not restored["ok"]:
		return false
	var next: Dictionary = Rounds.advance(restored["battle"])
	return _expect(
		next["ok"] and next["events"].is_empty() and not restored["battle"].unit(109)["visible"],
		"Saved once marker prevents later retry of blocked109"
	)


func _settlement(opened: Dictionary, context: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var story: Dictionary = content["story"]
	var early: bool = context["step"] == 1
	var options: Array = []
	var selection_count: int = 0
	for option: Dictionary in story["routeChoices"]:
		options.append([int(option["nodeId"]), int(option["routeIndex"])])
	for step: Dictionary in story["sequences"]["victory"]:
		if step["kind"] == "routeChoice":
			selection_count += 1
		if step["kind"] == "dialogue" and step["text"]["sourceTextIndex"] == 559:
			if not _expect(
				step.get("sourceWaitTicksAfter") == 10, "step1 text559 keeps its ten-tick wait"
			):
				return false
	if not _expect(
		(
			options == ([[6, 7], [8, 6]] if early else [[context["next"], context["route"]]])
			and selection_count == (1 if early else 0)
			and _dialogues(content, "victory") == ([[559, 5]] if early else [])
		),
		"Only step1 asks next6/8 -> route7/6; later m7 retains its route and actual next node"
	):
		return false
	for option: Array in options:
		var state: Dictionary = opened["battle"].snapshot()
		# Non-required formal9 is dead at this controlled settlement boundary.
		for actor: Dictionary in state["units"]:
			if actor["id"] == 9:
				actor["hp"] = 0
				actor["visible"] = false
				actor["flags"] |= 1
		var boundary: RefCounted = Battle.new(content, _roll, false)
		var applied: Dictionary = boundary.restore_snapshot(state)
		var fresh: Dictionary = {"ok": applied["ok"], "battle": boundary}
		if not _expect(fresh["ok"], "Controlled formal-death m7 settlement snapshot remains valid"):
			return false
		var battle: RefCounted = fresh["battle"]
		if not _expect(
			battle.win_with_assistance()["ok"], "Controlled m7 victory can reach real settlement"
		):
			return false
		if not early:
			var wrong: int = (int(context["route"]) + 1) % 8
			if not _expect(
				not battle.complete_victory(wrong)["ok"], "Fixed-route m7 rejects a different route"
			):
				return false
		var settled: Dictionary = battle.complete_victory(option[1])
		if not _expect(settled["ok"], "Actual m7 route settlement succeeds"):
			return false
		var world: Dictionary = settled["progress"]
		var expected: Array = context["party"].duplicate()
		expected.append(5)
		var actual: Array = []
		for actor: Dictionary in world["party"]:
			actual.append(int(actor["id"]))
			if not _expect(
				(
					actor["formal"]
					and actor["visible"]
					and actor["hp"] == actor["maxHp"]
					and actor["action"] == 0
					and actor["flags"] == 0
				),
				"m7 settlement revives formal9, restores formal state and omits temporary troops"
			):
				return false
			for original: Dictionary in state["units"]:
				if original["id"] == actor["id"]:
					if not _expect(
						actor["inventory"] == original["inventory"],
						"m7 settlement preserves held item identity/durability"
					):
						return false
		var repeated: Dictionary = battle.complete_victory(option[1])
		if not _expect(
			(
				actual == expected
				and world["route"] == option[1]
				and world["worldNode"] == 7
				and world["worldStep"] == context["step"] + 1
				and world["completedBattle"] == "m7"
				and world["gold"] == state["gold"] + 1000
				and world["warehouse"] == state["warehouse"]
				and repeated["ok"]
				and repeated["alreadyComplete"]
				and repeated["progress"] == world
				and battle.gold == world["gold"]
			),
			"m7 commits route,1000 gold,formal roster and warehouse exactly once while residing at node7"
		):
			return false
		var store: RefCounted = Store.new(
			content, _owned.path_join("world_%d_%d.json" % [context["route"], option[1]])
		)
		if not _expect(
			store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
			"m7 world writes owned continue and slot"
		):
			return false
		_draws = 0
		var continued: Dictionary = store.read()
		var slotted: Dictionary = store.read_slot(1)
		if not _expect(
			(
				continued["ok"]
				and slotted["ok"]
				and _draws == 0
				and continued["progress"] == world
				and slotted["progress"] == world
				and continued["content"]["story"]["battleNumber"] == context["step"] + 1
			),
			"m7 world JSON restores chosen route, inventory and completed step-1 projection"
		):
			return false
	return true


func _combat_setup(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [5, 86]:
			actor["x"] = 13
			actor["y"] = 12 if actor["id"] == 5 else 13
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["attributes"]["magic"] = 0
			actor["attributes"]["strength"] = 0
			actor["attributes"]["defense"] = 30
			actor["attributes"]["skill"] = 0
			actor["attributes"]["speed"] = 0
	return _expect(
		opened["battle"].restore_snapshot(state)["ok"],
		"Legal controlled m7 boss duel retains actual hero5/boss86 equipment"
	)


func _combat(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var config: Dictionary = _boss_events(content)
	var first_event: Dictionary = config["firstCombat"]
	var death_event: Dictionary = config["unitDeath"]
	var library := Clips.new(content)
	if not _expect(
		library.preload_pair(battle.attack_preview(5, 86))["ok"],
		"Actual m7 boss pair resolves complete ordinary clips"
	):
		return false
	_draws = 0
	var first: Dictionary = battle.attack_unit(5, 86)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == [first_event["sequence"]]
			and first["retirements"].is_empty()
			and battle.event_completed(first_event["id"])
			and (int(battle.unit(86)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _dialogues(content, first_event["sequence"]) == [[557, 86]]
			and _draws > 0
		),
		"Ordinary actual boss86 first combat triggers557/native B4 once through shared combat RNG"
	):
		return false
	var ready: Dictionary = battle.snapshot()
	for actor: Dictionary in ready["units"]:
		if actor["id"] == 5:
			actor["action"] = 0
	if not _expect(
		battle.restore_snapshot(ready)["ok"], "Prepare post-first-combat stable boundary"
	):
		return false
	var restored: Dictionary = _roundtrip(content, battle, "first_combat")
	if not restored["ok"]:
		return false
	battle = restored["battle"]
	var second: Dictionary = battle.attack_unit(5, 86)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"Cold JSON restore cannot repeat557"
	):
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 5:
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 86:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore controlled lethal m7 boss boundary"
	):
		return false
	var killed: Dictionary = battle.attack_unit(5, 86)
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 86,
						"beforeRetirement": [death_event["beforeRetirement"]],
						"afterRetirement": []
					}
				]
			)
			and _dialogues(content, death_event["beforeRetirement"]) == [[558, 86]]
			and not death_event.has("afterRetirement")
			and battle.event_completed(death_event["id"])
			and battle.unit(86)["hp"] == 0
			and not battle.unit(86)["visible"]
			and battle.outcome.is_empty()
			and killed["rewards"]["loot"].size() == 1
			and not killed["rewards"]["experience"].is_empty()
			and library.prepare(killed)["ok"]
		),
		"m7 commits death/drop/XP, schedules558 before retirement and waits for remaining enemies"
	):
		return false
	var reward: Dictionary = killed["rewards"]["experience"]
	if not _expect(
		battle.unit(reward["unit"])["experience"] == reward["after"],
		"m7 boss XP is already committed before presentation"
	):
		return false
	restored = _roundtrip(content, battle, "boss_death")
	if not restored["ok"]:
		return false
	var stored: Dictionary = restored["battle"].snapshot()
	var replay: Dictionary = Events.new(content).combat_events(
		killed["participants"], killed["retirements"], stored["events"]
	)
	return _expect(
		(
			restored["battle"].event_completed(death_event["id"])
			and replay["completed"].is_empty()
			and replay["before"].is_empty()
			and replay["retirements"][0]["beforeRetirement"].is_empty()
			and replay["retirements"][0]["afterRetirement"].is_empty()
		),
		"Stable m7 boss-death JSON preserves558 once and committed inventory/XP without replay"
	)


func _native_first_flag(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 86:
			actor["flags"] |= 4
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore m7 native B4-only boundary"):
		return false
	var event: Dictionary = _boss_events(opened["content"])["firstCombat"]
	var attacked: Dictionary = battle.attack_unit(5, 86)
	return _expect(
		(
			attacked["ok"]
			and attacked["storyBefore"].is_empty()
			and not battle.event_completed(event["id"])
		),
		"Native B4 already set suppresses557 without requiring its configured once marker"
	)


func _map_magic(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 3
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["inventory"] = [{"id": "m7:controlled:map", "templateId": 46, "durability": 3}]
			actor["equippedInstanceId"] = "m7:controlled:map"
			actor["attributes"]["magic"] = 30
		if actor["id"] == 86:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore legal actual m7 map-attack boundary"
	):
		return false
	var cast: Dictionary = battle.cast_map_attack(7, "m7:controlled:map")
	var config: Dictionary = _boss_events(opened["content"])
	return _expect(
		(
			cast["ok"]
			and battle.unit(86)["hp"] == 0
			and cast["storyBefore"].is_empty()
			and cast["storyAfter"].is_empty()
			and not battle.event_completed(config["firstCombat"]["id"])
			and not battle.event_completed(config["unitDeath"]["id"])
			and (int(battle.unit(86)["flags"]) & 4) == 0
		),
		"m7 map_attack excludes ordinary557/558 and preserves native/configured once markers"
	)


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	var initial: Array = opened["battle"].snapshot()["units"]
	for required: int in [0, 5]:
		var units: Array = initial.duplicate(true)
		for actor: Dictionary in units:
			if actor["id"] == required:
				actor["hp"] = 0
				actor["visible"] = true
		if not _expect(
			rules.outcome(units).is_empty(), "Visible HP0 required actor is a death transition"
		):
			return false
		for actor: Dictionary in units:
			if actor["id"] == required:
				actor["visible"] = false
		if not _expect(
			rules.outcome(units).get("kind") == "defeat",
			"Required0/5 retirement loses with enemies present"
		):
			return false
		for actor: Dictionary in units:
			if actor["faction"] == 2:
				actor["hp"] = 0
				actor["visible"] = false
		var both: Dictionary = rules.outcome(units)
		if not _expect(
			both.get("kind") == "defeat" and both.get("unit") == required,
			"Required0/5 retirement takes priority over simultaneous visible-enemy clear"
		):
			return false
	var boss_only: Array = initial.duplicate(true)
	var others: int = 0
	for actor: Dictionary in boss_only:
		if actor["id"] == 86:
			actor["hp"] = 0
			actor["visible"] = false
		elif actor["faction"] == 2 and actor["visible"] and actor["hp"] > 0:
			others += 1
	if not _expect(
		others > 0 and rules.outcome(boss_only).is_empty(),
		"Boss86 retirement cannot win while another visible enemy remains"
	):
		return false
	var cleared: Array = initial.duplicate(true)
	for actor: Dictionary in cleared:
		if actor["faction"] == 2:
			actor["hp"] = 0
			actor["visible"] = false
			if actor["id"] == 86:
				actor["hp"] = actor["maxHp"]
	if not _expect(
		rules.outcome(cleared).get("kind") == "victory",
		"A living hidden boss cannot block noVisibleEnemies victory"
	):
		return false
	for actor: Dictionary in cleared:
		if actor["id"] == 86:
			actor["hp"] = 0
			actor["visible"] = true
	return _expect(
		rules.outcome(cleared).is_empty(),
		"Visible HP0 enemy still blocks noVisibleEnemies until its retirement"
	)


func _fork(opened: Dictionary) -> Dictionary:
	var before: int = _draws
	var battle := Battle.new(opened["content"], _roll, false)
	var restored: Dictionary = battle.restore_snapshot(opened["battle"].snapshot().duplicate(true))
	if not _expect(
		restored["ok"] and _draws == before,
		"Fork an independent deep m7 boundary without initialization RNG"
	):
		return {"ok": false}
	return {"ok": true, "content": opened["content"], "battle": battle}


func _boss_events(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in content["story"]["combatEvents"]:
		if event["unitId"] == 86:
			result[event["trigger"]] = event
	return result


func _dialogues(content: Dictionary, sequence: String) -> Array:
	var result: Array = []
	for step: Dictionary in content["story"]["sequences"][sequence]:
		if step["kind"] == "dialogue":
			result.append([int(step["text"]["sourceTextIndex"]), int(step["text"]["speakerId"])])
	return result


func _roundtrip(content: Dictionary, battle: RefCounted, name: String) -> Dictionary:
	var store: RefCounted = Store.new(content, _owned.path_join(name + ".json"))
	var encoded: Dictionary = store.encode(battle)
	if not _expect(encoded["ok"], "Actual m7 stable boundary encodes: " + name):
		return {"ok": false}
	_draws = 0
	var restored: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == battle.snapshot(),
		(
			"m7 Store JSON cold restore keeps once/phase/units/items with zero initialization RNG: "
			+ name
		)
	):
		return {"ok": false}
	return restored


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _ints(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _cell(point: Array) -> Vector2i:
	return Vector2i(int(point[0]), int(point[1]))


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
