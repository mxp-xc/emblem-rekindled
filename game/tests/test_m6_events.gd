extends SceneTree

const Matrix = preload("res://tests/test_m6_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
const M4Events = preload("res://tests/test_m4_events.gd")
# Oracle: temp/m3-m7 p6/route samples, temp/m6/content-plan.md and the
# source i.m ordinary phase boundary. Combat and phase waits are controlled.
var _draws: int = 0
var _limits: Array[int] = []
var _observed_battle: RefCounted
var _observations: Array[Dictionary] = []
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(0, 2), true)


func _run_contexts(contexts: Array, include_boundaries: bool) -> void:
	_owned = "user://m6_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim a fresh owned m6 events directory")
		return
	var combat_source: Dictionary = {}
	for context: Dictionary in contexts:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare m6 event context: " + str(prepared.get("error"))):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m6", prepared["source"], _roll)
		if not _expect(opened["ok"], "Open actual m6 events: " + str(opened.get("error"))):
			_cleanup()
			return
		if combat_source.is_empty():
			combat_source = opened
		if (
			not _opening(opened["content"])
			or not _phases(opened, context)
			or not _settlement(opened, context)
			or not _priority(opened)
		):
			_cleanup()
			return
		print("PASS actual m6 events dr%d step%d" % [context["route"], context["step"]])
	if include_boundaries:
		for boundary: Callable in [_combat, _native_first_flag, _map_magic]:
			var forked: Dictionary = _fork(combat_source)
			if not forked["ok"] or not boundary.call(forked):
				_cleanup()
				return
	_cleanup()
	print("PASS actual m6 events: selected routes and requested combat boundaries")
	quit(0)


func _opening(content: Dictionary) -> bool:
	var sequence: Array = content["story"]["sequences"]["opening"]
	var kinds: Array = []
	for step: Dictionary in sequence:
		kinds.append(step["kind"])
	return _expect(
		(
			(
				kinds
				== [
					"battleTitle",
					"focus",
					"focus",
					"dialogue",
					"dialogue",
					"objective",
					"commanderSetup"
				]
			)
			and _cell(sequence[1]["cell"]) == Vector2i(5, 9)
			and sequence[1].get("instant") == true
			and sequence[1].get("sourceWaitTicks") == 22
			and _cell(sequence[2]["cell"]) == Vector2i(19, 17)
			and sequence[2].get("instant", false) == false
			and sequence[2].get("sourceWaitTicks") == 10
			and _dialogues(content, "opening") == [[542, 85], [543, 4]]
			and sequence[4].get("sourceWaitTicksAfter") == 10
			and sequence[5]["text"]["sourceTextIndex"] == 162
			and _ints(sequence[6]["candidates"]) == [4]
			and sequence[6]["defaultCommanderId"] == 4
		),
		"m6 opening snaps5,9/waits22, pans19,17/waits10, then542/543/waits10/objective/commander4"
	)


func _phases(opened: Dictionary, context: Dictionary) -> bool:
	var forked: Dictionary = _fork(opened)
	if not forked["ok"]:
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = forked["battle"]
	var story: Dictionary = content["story"]
	if not _expect(
		(
			story["turnEvents"].size() == 1
			and story["aiChanges"].is_empty()
			and not story.has("periodicClones")
		),
		"m6 has only its source round2 arrival, with no story-specific ring/clone/AI events"
	):
		return false
	var event: Dictionary = story["turnEvents"][0]
	var party: Array[int] = []
	for slot: int in range(7):
		party.append(int(content["slots"][slot]))
	var arrival: Array = story["sequences"][event["sequence"]]
	if not _expect(
		(
			event["afterEnemyPhaseOfRound"] == 2
			and _ints(event["unitIds"]) == party
			and not event.has("arrivalMode")
			and arrival.size() == 3
			and arrival[0]["kind"] == "parallelEntrances"
			and _cell(arrival[0]["focus"]) == Vector2i(6, 18)
			and _dialogues(content, event["sequence"]) == [[544, 4], [545, 0]]
			and arrival[0]["units"].size() == 7
		),
		"Round2 selects all seven current slots for one parallel southern entrance, then544/545"
	):
		return false
	for index: int in range(7):
		var entrance: Dictionary = arrival[0]["units"][index]
		var actor: Dictionary = battle.unit(party[index])
		if not _expect(
			(
				entrance["unitId"] == party[index]
				and _cell(entrance["to"]) == Vector2i(actor["x"], actor["y"])
				and _cell(entrance["from"]) == Vector2i(actor["x"], actor["y"] + 3)
				and not actor["visible"]
			),
			"Each actual slot keeps its cell and enters visually from three rows south"
		):
			return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 85:
			actor["hp"] = 1
			actor["maxHp"] = 60
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Prepare injured actual boss85 ring boundary"
	):
		return false
	var inventory: Array = battle.unit(85)["inventory"].duplicate(true)
	var templates: Array[int] = []
	for held: Dictionary in inventory:
		templates.append(int(held["templateId"]))
	if not _expect(
		templates == [19, 65, 81, 76] and inventory[2]["durability"] == 0,
		"Actual boss85 holds lance19, shield65, zero-durability ring81 and appended drop76"
	):
		return false
	var initial: Dictionary = battle.snapshot()
	var restored: Dictionary = _roundtrip(content, battle, "dr%d_before_arrival" % context["route"])
	if not restored["ok"]:
		return false
	battle = restored["battle"]
	var emitted: int = 0
	while battle.round_number < 4:
		var previous: int = battle.round_number
		_draws = 0
		_limits.clear()
		_observations.clear()
		_observed_battle = battle
		var advanced: Dictionary = M4Events.advance(battle)
		_observed_battle = null
		if not _expect(advanced["ok"], "Advance actual m6 phases with controlled automatic waits"):
			return false
		for emitted_event: Dictionary in advanced["events"]:
			emitted += 1
			if not _expect(
				(
					previous == 2
					and emitted_event["kind"] == "reinforcements"
					and emitted_event["sequence"] == event["sequence"]
					and emitted_event["arrivals"].size() == 7
					and not emitted_event.has("arrivalMode")
				),
				"Only the completed enemy phase of old round2 emits all seven arrivals"
			):
				return false
		if not _expect(
			(
				_draws == 1
				and _limits == [11]
				and _observations == [{"phase": 0, "round": previous + 1, "arrived": previous >= 2}]
				and battle.event_completed(event["id"]) == (previous >= 2)
				and battle.unit(85)["hp"] == 1 + previous * 6
				and battle.unit(85)["inventory"] == inventory
			),
			"Old-round arrival precedes new-round phase0 ring RNG/recovery; zero durability is retained"
		):
			return false
		for identity: int in party:
			if not _expect(
				battle.unit(identity)["visible"] == (previous >= 2),
				"Seven slots become visible only after the real round2 enemy phase"
			):
				return false
		restored = _roundtrip(
			content, battle, "dr%d_round%d" % [context["route"], battle.round_number]
		)
		if not restored["ok"]:
			return false
		battle = restored["battle"]
	if not _expect(emitted == 1, "Cold JSON restore before/after arrival cannot replay round2"):
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
			"Arrivals/recovery retain source, class, properties, inventory and deployment cells"
		):
			return false
	return true


func _settlement(opened: Dictionary, context: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var story: Dictionary = content["story"]
	var options: Array = []
	for option: Dictionary in story["routeChoices"]:
		options.append([int(option["nodeId"]), int(option["routeIndex"])])
	var sequence: Array = story["sequences"]["victory"]
	if not _expect(
		(
			options == [[context["next"], context["route"]]]
			and (
				_dialogues(content, "victory")
				== [[548, 4], [488 if context["step"] == 2 else 549, 0]]
			)
			and sequence.size() == 3
			and sequence[1].get("sourceWaitTicksAfter") == 15
			and sequence[2]["kind"] == "missionComplete"
			and sequence[2]["goldReward"] == 1000
		),
		"m6 victory uses548 then step2-only488/otherwise549 with wait15 and fixed-route1000 reward"
	):
		return false
	var forked: Dictionary = _fork(opened)
	if not forked["ok"]:
		return false
	var battle: RefCounted = forked["battle"]
	var state: Dictionary = battle.snapshot()
	# A non-required formal member is dead at this controlled settlement boundary.
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 1
	if not _expect(
		battle.restore_snapshot(state)["ok"] and battle.win_with_assistance()["ok"],
		"Controlled formal9 death reaches real m6 victory settlement"
	):
		return false
	if not _expect(
		not battle.complete_victory((int(context["route"]) + 1) % 8)["ok"],
		"Fixed-route m6 rejects a different route"
	):
		return false
	var completed: Dictionary = battle.complete_victory(context["route"])
	if not _expect(completed["ok"], "Actual m6 complete_victory succeeds on every route"):
		return false
	var world: Dictionary = completed["progress"]
	var expected: Array = context["party"].duplicate()
	expected.append(4)
	var actual: Array[int] = []
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
			"m6 settlement revives formal9, heals formal members and excludes temporary troops"
		):
			return false
		for original: Dictionary in state["units"]:
			if original["id"] == actor["id"]:
				if not _expect(
					actor["inventory"] == original["inventory"],
					"m6 settlement preserves held identities and current durability"
				):
					return false
	var repeated: Dictionary = battle.complete_victory(context["route"])
	if not _expect(
		(
			actual == _ints(expected)
			and world["route"] == context["route"]
			and world["worldNode"] == 6
			and world["worldStep"] == context["step"] + 1
			and world["completedBattle"] == "m6"
			and world["gold"] == state["gold"] + 1000
			and world["warehouse"] == state["warehouse"]
			and repeated["ok"]
			and repeated["alreadyComplete"]
			and repeated["progress"] == world
			and battle.gold == world["gold"]
		),
		"m6 recruits formal4 and commits route, roster, warehouse and1000 gold exactly once"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("world_%d.json" % context["route"]))
	if not _expect(
		store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
		"Every m6 route writes real completed-world continue and slot records in the owned directory"
	):
		return false
	_draws = 0
	var continued: Dictionary = store.read()
	var slotted: Dictionary = store.read_slot(1)
	return _expect(
		(
			continued["ok"]
			and slotted["ok"]
			and _draws == 0
			and continued["progress"] == world
			and slotted["progress"] == world
			and continued["content"]["story"]["battleNumber"] == context["step"] + 1
		),
		"Completed m6 JSON restores both records and completed-step projection without initialization RNG"
	)


func _combat_setup(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [4, 85]:
			actor["x"] = 20
			actor["y"] = 18 if actor["id"] == 4 else 19
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["attributes"]["magic"] = 0
			actor["attributes"]["strength"] = 0
			actor["attributes"]["defense"] = 30
			actor["attributes"]["skill"] = 0
			actor["attributes"]["speed"] = 0
	return _expect(
		opened["battle"].restore_snapshot(state)["ok"],
		"Legal controlled m6 boss duel retains actual hero4/boss85 equipment"
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
		library.preload_pair(battle.attack_preview(4, 85))["ok"],
		"Actual m6 boss pair resolves complete ordinary clips"
	):
		return false
	_draws = 0
	_limits.clear()
	var first: Dictionary = battle.attack_unit(4, 85)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == [first_event["sequence"]]
			and first["retirements"].is_empty()
			and battle.event_completed(first_event["id"])
			and (int(battle.unit(85)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _dialogues(content, first_event["sequence"]) == [[546, 85]]
			and _draws > 0
		),
		"Ordinary actual boss85 first combat triggers546/native B4 once through shared combat RNG"
	):
		return false
	var combat_draws: int = _draws
	var advanced: Dictionary = M4Events.advance(battle)
	if not _expect(
		advanced["ok"] and _draws == combat_draws + 1 and _limits.back() == 11,
		"Actual boss ring uses the same RNG stream once after ordinary combat and the new-round boundary"
	):
		return false
	var restored: Dictionary = _roundtrip(content, battle, "first_combat")
	if not restored["ok"]:
		return false
	battle = restored["battle"]
	var second: Dictionary = battle.attack_unit(4, 85)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"Cold JSON restore cannot repeat546"
	):
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 4:
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 85:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore controlled lethal m6 boss boundary"
	):
		return false
	var killed: Dictionary = battle.attack_unit(4, 85)
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 85,
						"beforeRetirement": [death_event["beforeRetirement"]],
						"afterRetirement": []
					}
				]
			)
			and _dialogues(content, death_event["beforeRetirement"]) == [[547, 85]]
			and not death_event.has("afterRetirement")
			and battle.event_completed(death_event["id"])
			and battle.unit(85)["hp"] == 0
			and not battle.unit(85)["visible"]
			and battle.outcome.is_empty()
			and killed["rewards"]["loot"].size() == 1
			and not killed["rewards"]["experience"].is_empty()
			and library.prepare(killed)["ok"]
		),
		"m6 commits death/drop/XP, schedules547 before retirement and waits for remaining enemies"
	):
		return false
	var reward: Dictionary = killed["rewards"]["experience"]
	if not _expect(
		battle.unit(reward["unit"])["experience"] == reward["after"],
		"m6 boss XP is already committed before presentation"
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
		"Stable m6 boss-death JSON preserves547 once and committed inventory/XP without replay"
	)


func _native_first_flag(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 85:
			actor["flags"] |= 4
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore m6 native B4-only boundary"):
		return false
	var event: Dictionary = _boss_events(opened["content"])["firstCombat"]
	var attacked: Dictionary = battle.attack_unit(4, 85)
	return _expect(
		(
			attacked["ok"]
			and attacked["storyBefore"].is_empty()
			and not battle.event_completed(event["id"])
		),
		"Native B4 already set suppresses546 without requiring its configured once marker"
	)


func _map_magic(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 3
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["inventory"] = [{"id": "m6:controlled:map", "templateId": 46, "durability": 3}]
			actor["equippedInstanceId"] = "m6:controlled:map"
			actor["attributes"]["magic"] = 30
		if actor["id"] == 85:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore legal actual m6 map-attack boundary"
	):
		return false
	var cast: Dictionary = battle.cast_map_attack(7, "m6:controlled:map")
	var config: Dictionary = _boss_events(opened["content"])
	return _expect(
		(
			cast["ok"]
			and battle.unit(85)["hp"] == 0
			and cast["storyBefore"].is_empty()
			and cast["storyAfter"].is_empty()
			and not battle.event_completed(config["firstCombat"]["id"])
			and not battle.event_completed(config["unitDeath"]["id"])
			and (int(battle.unit(85)["flags"]) & 4) == 0
		),
		"m6 map_attack excludes ordinary546/547 and preserves native/configured once markers"
	)


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	var initial: Array = opened["battle"].snapshot()["units"]
	for required: int in [0, 4]:
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
			"Required0/4 retirement loses with enemies present"
		):
			return false
		for actor: Dictionary in units:
			if actor["faction"] == 2:
				actor["hp"] = 0
				actor["visible"] = false
		var both: Dictionary = rules.outcome(units)
		if not _expect(
			both.get("kind") == "defeat" and both.get("unit") == required,
			"Required0/4 retirement takes priority over simultaneous visible-enemy clear"
		):
			return false
	var boss_only: Array = initial.duplicate(true)
	var others: int = 0
	for actor: Dictionary in boss_only:
		if actor["id"] == 85:
			actor["hp"] = 0
			actor["visible"] = false
		elif actor["faction"] == 2 and actor["visible"] and actor["hp"] > 0:
			others += 1
	if not _expect(
		others > 0 and rules.outcome(boss_only).is_empty(),
		"Boss85 retirement cannot win while another visible enemy remains"
	):
		return false
	var cleared: Array = initial.duplicate(true)
	for actor: Dictionary in cleared:
		if actor["faction"] == 2:
			actor["hp"] = 0
			actor["visible"] = false
			if actor["id"] == 85:
				actor["hp"] = actor["maxHp"]
	if not _expect(
		rules.outcome(cleared).get("kind") == "victory",
		"A living hidden boss cannot block noVisibleEnemies victory"
	):
		return false
	for actor: Dictionary in cleared:
		if actor["id"] == 85:
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
		"Fork an independent deep m6 boundary without initialization RNG"
	):
		return {"ok": false}
	return {"ok": true, "content": opened["content"], "battle": battle}


func _boss_events(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in content["story"]["combatEvents"]:
		if event["unitId"] == 85:
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
	if not _expect(encoded["ok"], "Actual m6 stable boundary encodes: " + name):
		return {"ok": false}
	_draws = 0
	var restored: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == battle.snapshot(),
		(
			"m6 Store JSON cold restore keeps once/phase/units/items/ring HP with zero initialization RNG: "
			+ name
		)
	):
		return {"ok": false}
	return restored


func _roll(limit: int) -> int:
	_draws += 1
	_limits.append(limit)
	if _observed_battle != null:
		_observations.append(
			{
				"phase": _observed_battle.phase,
				"round": _observed_battle.round_number,
				"arrived": _observed_battle.event_completed("party_arrival")
			}
		)
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
