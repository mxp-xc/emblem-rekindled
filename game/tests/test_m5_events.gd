extends SceneTree

const Matrix = preload("res://tests/test_m5_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
const M4Events = preload("res://tests/test_m4_events.gd")
# Oracle: temp/m3-m7/events/{summary.json,m5/observations.json}, and
# p5.json and m5-route-*.json. All battle boundaries below are controlled.
const CAVALRY: Array[int] = [64, 65, 66, 67, 68, 69]
var _draws: int = 0
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(0, 2), true)


func _run_contexts(contexts: Array, include_boundaries: bool) -> void:
	_owned = "user://m5_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim a fresh owned m5 events directory")
		return
	var first_content: Dictionary = {}
	var first_snapshot: Dictionary = {}
	for context: Dictionary in contexts:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare m5 event context: " + str(prepared.get("error"))):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m5", {"progress": prepared["progress"]}, _roll
		)
		if not _expect(opened["ok"], "Open actual m5 events: " + str(opened.get("error"))):
			_cleanup()
			return
		if first_content.is_empty():
			first_content = opened["content"]
			first_snapshot = opened["battle"].snapshot()
		if not _phases(opened) or not _settlement(opened, context) or not _priority(opened):
			_cleanup()
			return
		print("PASS actual m5 events dr%d step%d" % [context["route"], context["step"]])
	if include_boundaries:
		for boundary: Callable in [_combat, _native_first_flag, _map_magic, _source_pairs]:
			var opened: Dictionary = _fork(first_content, first_snapshot)
			if (
				not _expect(opened["ok"], "Independent m5 combat boundary must open")
				or not boundary.call(opened)
			):
				_cleanup()
				return
	_cleanup()
	print("PASS actual m5 events: selected routes and requested combat boundaries")
	quit(0)


# Each business case owns a fresh Battle; definitions remain the first loaded content.
func _fork(content: Dictionary, state: Dictionary) -> Dictionary:
	var battle: RefCounted = Battle.new(content, _roll, false)
	var restored: Dictionary = battle.restore_snapshot(state.duplicate(true))
	if not restored["ok"]:
		return restored
	return {"ok": true, "content": content, "battle": battle}


func _phases(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var initial: Dictionary = battle.snapshot()
	var events: Dictionary = {}
	for event: Dictionary in content["story"]["turnEvents"]:
		events[int(event["afterEnemyPhaseOfRound"])] = event
	if not _expect(
		(
			events.size() == 2
			and events.has(1)
			and events.has(3)
			and content["story"]["aiChanges"].is_empty()
			and _dialogues(content, "opening") == [[532, 2], [533, 84]]
		),
		"m5 only has source round1/3 arrivals and no unreachable round12 AI policy change"
	):
		return false
	var first: Dictionary = events[1]
	var third: Dictionary = events[3]
	var party: Array[int] = []
	for slot: int in range(6):
		party.append(int(content["slots"][slot]))
	if not _expect(
		(
			_ints(first["unitIds"]) == party
			and not first.has("arrivalMode")
			and third.get("arrivalMode") == "nativeQueue"
			and _ints(third["unitIds"]) == CAVALRY
			and _dialogues(content, first["sequence"]) == [[534, 2], [535, 18], [536, 0], [537, 84]]
			and _dialogues(content, third["sequence"]) == [[538, 0]]
		),
		"Actual m5 event selectors and dialogues preserve native source order"
	):
		return false
	var entrances: Array = []
	for step: Dictionary in content["story"]["sequences"][first["sequence"]]:
		if step["kind"] == "parallelEntrances":
			if not _expect(
				_cell(step["focus"]) == Vector2i(20, 7), "Round1 party entrance focuses20,7"
			):
				return false
			entrances.append_array(step["units"])
	if not _expect(entrances.size() == 6, "Round1 uses the six existing slot entrances"):
		return false
	for index: int in range(6):
		var entrance: Dictionary = entrances[index]
		var actor: Dictionary = battle.unit(party[index])
		if not _expect(
			(
				entrance["unitId"] == party[index]
				and _cell(entrance["to"]) == Vector2i(actor["x"], actor["y"])
				and _cell(entrance["from"]) == Vector2i(actor["x"] + 3, actor["y"])
			),
			"Round1 side entrance offsets visual origin by3 while retaining its deployment cell"
		):
			return false
	var third_sequence: Array = content["story"]["sequences"][third["sequence"]]
	if not _expect(
		third_sequence.size() == 1 and third_sequence[0]["kind"] == "dialogue",
		"Native queue completes before its sole538 sequence; no parallel entrances or reveals"
	):
		return false
	var before_arrivals: Dictionary = _roundtrip(content, battle, "before_arrivals")
	if not before_arrivals["ok"]:
		return false
	battle = before_arrivals["battle"]
	var emitted: Dictionary = {1: 0, 3: 0}
	while battle.round_number < 5:
		var previous: int = battle.round_number
		var advanced: Dictionary = M4Events.advance(battle)
		if not _expect(advanced["ok"], "Advance actual m5 phases using controlled automatic waits"):
			return false
		for event: Dictionary in advanced["events"]:
			if not _expect(
				(
					emitted.has(previous)
					and event["kind"] == "reinforcements"
					and event["sequence"] == events[previous]["sequence"]
					and (
						event.get("arrivalMode") == "nativeQueue"
						if previous == 3
						else not event.has("arrivalMode")
					)
				),
				"Only real enemy phase completion of round1/3 emits reinforcements"
			):
				return false
			emitted[previous] += 1
			if previous == 1:
				if not _expect(
					event["arrivals"].size() == 6, "Round1 reveals all six slot occupants"
				):
					return false
			else:
				var queue: Array = event.get("arrivalQueue", [])
				if not _expect(
					queue.size() == 6, "Native queue retains all six existing cavalry objects"
				):
					return false
				for index: int in range(queue.size()):
					var entry: Dictionary = queue[index]
					var actor: Dictionary = battle.unit(CAVALRY[index])
					var original: Dictionary = {}
					for candidate: Dictionary in initial["units"]:
						if candidate["id"] == CAVALRY[index]:
							original = candidate
					if not _expect(
						(
							entry["unit"] == CAVALRY[index]
							and entry["from"] == Vector2i(original["x"], original["y"])
							and entry["to"] == Vector2i(actor["x"], actor["y"])
							and entry["revealed"] == actor["visible"]
						),
						"Round3 queue uses64..69 source order and each actor's actual original/final cell"
					):
						return false
		for timing: int in [1, 3]:
			if not _expect(
				battle.event_completed(events[timing]["id"]) == (previous >= timing),
				"Arrival once markers change only at their original phase boundaries"
			):
				return false
		var restored: Dictionary = _roundtrip(
			content, battle, "dr%d_round%d" % [initial["campaign"]["route"], battle.round_number]
		)
		if not restored["ok"]:
			return false
		battle = restored["battle"]
	if not _expect(
		emitted == {1: 1, 3: 1}, "JSON restore before and after each wave cannot replay arrivals"
	):
		return false
	for original: Dictionary in initial["units"]:
		var actor: Dictionary = battle.unit(original["id"])
		if not _expect(
			(
				actor["sourceId"] == original["sourceId"]
				and actor["classId"] == original["classId"]
				and actor["attributes"] == original["attributes"]
				and actor["inventory"] == original["inventory"]
				and Vector2i(actor["x"], actor["y"]) == Vector2i(original["x"], original["y"])
			),
			"Arrivals retain source, properties, inventory and free deployment cells"
		):
			return false
	return true


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
		if step["kind"] == "dialogue" and step["text"]["sourceTextIndex"] == 541:
			if not _expect(
				step.get("sourceWaitTicksAfter") == 15, "step1 text541 keeps its fifteen-tick wait"
			):
				return false
	if not _expect(
		(
			options == ([[4, 5], [6, 4]] if early else [[context["next"], context["route"]]])
			and selection_count == (1 if early else 0)
			and _dialogues(content, "victory") == ([[541, 2]] if early else [])
		),
		"Only step1 asks next4/6 -> route5/4; later m5 retains its route and actual next node"
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
		var fresh: Dictionary = _fork(content, state)
		if not _expect(fresh["ok"], "Controlled formal-death m5 settlement snapshot remains valid"):
			return false
		var battle: RefCounted = fresh["battle"]
		if not _expect(
			battle.win_with_assistance()["ok"], "Controlled m5 victory can reach real settlement"
		):
			return false
		if not early:
			var wrong: int = (int(context["route"]) + 1) % 8
			if not _expect(
				not battle.complete_victory(wrong)["ok"], "Fixed-route m5 rejects a different route"
			):
				return false
		var settled: Dictionary = battle.complete_victory(option[1])
		if not _expect(settled["ok"], "Actual m5 route settlement succeeds"):
			return false
		var world: Dictionary = settled["progress"]
		var expected: Array = context["party"].duplicate()
		expected.append(2)
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
				"m5 settlement revives formal9, restores formal state and omits temporary troops"
			):
				return false
			for original: Dictionary in state["units"]:
				if original["id"] == actor["id"]:
					if not _expect(
						actor["inventory"] == original["inventory"],
						"m5 settlement preserves held item identity/durability"
					):
						return false
		var repeated: Dictionary = battle.complete_victory(option[1])
		if not _expect(
			(
				actual == expected
				and world["route"] == option[1]
				and world["worldNode"] == 5
				and world["worldStep"] == context["step"] + 1
				and world["completedBattle"] == "m5"
				and world["gold"] == state["gold"] + 1000
				and world["warehouse"] == state["warehouse"]
				and repeated["ok"]
				and repeated["alreadyComplete"]
				and repeated["progress"] == world
				and battle.gold == world["gold"]
			),
			"m5 commits route,1000 gold,formal roster and warehouse exactly once while residing at node5"
		):
			return false
		var store: RefCounted = Store.new(
			content, _owned.path_join("world_%d_%d.json" % [context["route"], option[1]])
		)
		if not _expect(
			store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
			"m5 world writes owned continue and slot"
		):
			return false
		var continued: Dictionary = store.read()
		var slotted: Dictionary = store.read_slot(1)
		if not _expect(
			(
				continued["ok"]
				and slotted["ok"]
				and continued["progress"] == world
				and slotted["progress"] == world
				and continued["content"]["story"]["battleNumber"] == context["step"] + 1
			),
			"m5 world JSON restores chosen route, inventory and completed step-1 projection"
		):
			return false
	return true


func _combat_setup(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 2:
			actor["x"] = 21
			actor["y"] = 17
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["attributes"]["magic"] = 0
			actor["attributes"]["strength"] = 0
			actor["attributes"]["defense"] = 30
		if actor["id"] == 84:
			actor["x"] = 21
			actor["y"] = 18
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["attributes"]["defense"] = 30
			actor["attributes"]["strength"] = 0
			actor["attributes"]["magic"] = 0
			actor["attributes"]["skill"] = 0
			actor["attributes"]["speed"] = 0
	return _expect(
		opened["battle"].restore_snapshot(state)["ok"],
		"Legal controlled m5 boss duel with actual equipment"
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
		library.preload_pair(battle.attack_preview(2, 84))["ok"],
		"Actual m5 boss pair resolves real complete clips"
	):
		return false
	var first: Dictionary = battle.attack_unit(2, 84)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == [first_event["sequence"]]
			and first["retirements"].is_empty()
			and battle.event_completed(first_event["id"])
			and (int(battle.unit(84)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _dialogues(content, first_event["sequence"]) == [[539, 84]]
		),
		"Ordinary actual boss84 combat triggers539 and native B4 once"
	):
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 2:
			actor["action"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Reset actor for post-first-combat JSON boundary"
	):
		return false
	var restored: Dictionary = _roundtrip(content, battle, "first_combat")
	if not restored["ok"]:
		return false
	battle = restored["battle"]
	var second: Dictionary = battle.attack_unit(2, 84)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"JSON restore cannot repeat539"
	):
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 2:
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 84:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Controlled lethal m5 boss boundary restores"
	):
		return false
	var killed: Dictionary = battle.attack_unit(2, 84)
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 84,
						"beforeRetirement": [death_event["beforeRetirement"]],
						"afterRetirement": []
					}
				]
			)
			and _dialogues(content, death_event["beforeRetirement"]) == [[540, 84]]
			and not death_event.has("afterRetirement")
			and battle.event_completed(death_event["id"])
			and battle.unit(84)["hp"] == 0
			and not battle.unit(84)["visible"]
			and killed["rewards"]["loot"].size() == 1
			and not killed["rewards"]["experience"].is_empty()
			and library.prepare(killed)["ok"]
		),
		"m5 immediately settles death/drop/XP, scheduling540 before retirement"
	):
		return false
	var reward: Dictionary = killed["rewards"]["experience"]
	if not _expect(
		battle.unit(reward["unit"])["experience"] == reward["after"],
		"m5 XP is already committed before presentation"
	):
		return false
	var terminal_store: RefCounted = Store.new(content, _owned.path_join("boss_death.json"))
	var rejected: Dictionary = terminal_store.encode(battle)
	if not _expect(
		not rejected["ok"] and rejected.get("error") == "BATTLE_NOT_STABLE",
		"Immediate boss victory cannot be encoded as a stable battle save"
	):
		return false
	# Terminal snapshots are not restorable battle records. Inspect the JSON event
	# state directly, then persist the legal completed-world boundary below.
	var stored: Dictionary = JSON.parse_string(JSON.stringify(battle.snapshot()))
	var replay: Dictionary = Events.new(content).combat_events(
		killed["participants"], killed["retirements"], stored["events"]
	)
	if not _expect(
		(
			stored["events"].get(death_event["id"], false)
			and replay["completed"].is_empty()
			and replay["before"].is_empty()
			and replay["retirements"][0]["beforeRetirement"].is_empty()
			and replay["retirements"][0]["afterRetirement"].is_empty()
		),
		"JSON death event markers suppress540 after immediate victory"
	):
		return false
	var completed: Dictionary = battle.complete_victory(int(stored["campaign"]["route"]))
	if not _expect(completed["ok"], "Actual boss victory reaches its legal world boundary"):
		return false
	if not _expect(
		terminal_store.write_progress(completed["progress"])["ok"],
		"Actual boss victory persists a completed world record in the owned directory"
	):
		return false
	_draws = 0
	var world: Dictionary = terminal_store.read()
	return _expect(
		world["ok"] and _draws == 0 and world["progress"] == completed["progress"],
		"Completed boss world JSON preserves committed rewards and inventory without initialization draws"
	)


func _native_first_flag(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 84:
			actor["flags"] |= 4
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Source B4-only first-combat boundary restores"
	):
		return false
	var event: Dictionary = _boss_events(opened["content"])["firstCombat"]
	var attacked: Dictionary = battle.attack_unit(2, 84)
	return _expect(
		(
			attacked["ok"]
			and attacked["storyBefore"].is_empty()
			and not battle.event_completed(event["id"])
		),
		"Native B4 already set suppresses539 even without its configured event marker"
	)


func _map_magic(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 3  # Actual earthquake contract: every third round.
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["inventory"] = [{"id": "m5:controlled:map", "templateId": 46, "durability": 3}]
			actor["equippedInstanceId"] = "m5:controlled:map"
			actor["attributes"]["magic"] = 30
		if actor["id"] == 84:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Legal real m5 map-magic controlled boundary"
	):
		return false
	var cast: Dictionary = battle.cast_map_attack(7, "m5:controlled:map")
	var config: Dictionary = _boss_events(opened["content"])
	return _expect(
		(
			cast["ok"]
			and battle.unit(84)["hp"] == 0
			and cast["storyBefore"].is_empty()
			and cast["storyAfter"].is_empty()
			and not battle.event_completed(config["firstCombat"]["id"])
			and not battle.event_completed(config["unitDeath"]["id"])
			and (int(battle.unit(84)["flags"]) & 4) == 0
		),
		"Actual m5 map magic skips ordinary539/540 and preserves all ordinary once markers"
	)


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	var initial: Array = opened["battle"].snapshot()["units"]
	for required: int in [0, 2]:
		var units: Array = initial.duplicate(true)
		for actor: Dictionary in units:
			if actor["id"] == required or actor["id"] == 84:
				actor["hp"] = 0
				actor["visible"] = false
		var outcome: Dictionary = rules.outcome(units)
		if not _expect(
			outcome.get("kind") == "defeat" and outcome.get("unit") == required,
			"Required0/2 retired takes precedence over simultaneous boss84 retirement"
		):
			return false
	var units: Array = initial.duplicate(true)
	var living: int = 0
	for actor: Dictionary in units:
		if actor["id"] == 84:
			actor["hp"] = 0
			actor["visible"] = false
		elif actor["faction"] == 2 and actor["hp"] > 0:
			living += 1
	return _expect(
		living > 0 and rules.outcome(units).get("kind") == "victory",
		"Boss84 retirement wins even while other enemies remain alive"
	)


func _source_pairs(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	for target: int in [46, 70]:
		var fresh: Dictionary = _fork(content, opened["battle"].snapshot())
		if not _expect(fresh["ok"], "Open distinct source46 combat boundary"):
			return false
		var battle: RefCounted = fresh["battle"]
		var state: Dictionary = battle.snapshot()
		for actor: Dictionary in state["units"]:
			if actor["id"] == 2 or actor["id"] == target:
				actor["x"] = 21
				actor["y"] = 17 if actor["id"] == 2 else 18
				actor["hp"] = 60
				actor["maxHp"] = 60
				actor["attributes"]["strength"] = 0
				actor["attributes"]["magic"] = 0
				actor["attributes"]["skill"] = 0
				actor["attributes"]["speed"] = 0
				actor["attributes"]["defense"] = 30
		if not _expect(battle.restore_snapshot(state)["ok"], "Restore legal actual source46 duel"):
			return false
		var library := Clips.new(content)
		var preview: Dictionary = battle.attack_preview(2, target)
		if not _expect(
			preview["ok"] and library.preload_pair(preview)["ok"],
			"Both actual source46 jobs preflight their own ordinary combat clips"
		):
			return false
		var result: Dictionary = battle.attack_unit(2, target)
		if not _expect(result["ok"], "Actual ordinary source46 attack resolves"):
			return false
		var presentation: Dictionary = library.prepare(result)
		if not _expect(
			(
				presentation["ok"]
				and result["participants"][1]["id"] == target
				and result["participants"][1]["sourceId"] == 46
				and result["participants"][1]["classId"] == (8 if target == 46 else 24)
				and presentation["appearances"][str(target)].begins_with("%d:" % target)
			),
			"Clip binding retains modern actor46/70 while their source remains46"
		):
			return false
	return true


func _boss_events(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in content["story"]["combatEvents"]:
		if event["unitId"] == 84:
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
	if not _expect(encoded["ok"], "Actual m5 stable boundary encodes: " + name):
		return {"ok": false}
	_draws = 0
	var restored: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == battle.snapshot(),
		(
			"Actual m5 JSON restore preserves once/phase/units/inventory without initialization RNG: "
			+ name
		)
	):
		return {"ok": false}
	return restored


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


# JSON numeric arrays use float Variants; grid coordinates have integer meaning.
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
