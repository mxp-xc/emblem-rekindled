extends SceneTree

const Matrix = preload("res://tests/test_m8_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
# Oracle: temp/m8/discovery.md and original-route-*/observations.json.
# Automatic turns wait; combat and occupancy boundaries are explicit fixtures.
var _draws: int = 0
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(0, 1), false)


func _run_contexts(contexts: Array, include_boundaries: bool) -> void:
	_owned = "user://m8_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim fresh owned m8 event directory")
		return
	var combat_source: Dictionary = {}
	for context: Dictionary in contexts:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare m8 event context: " + str(prepared.get("error"))):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m8", prepared["source"], _roll)
		if not _expect(opened["ok"], "Open actual m8 events: " + str(opened.get("error"))):
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
		print("PASS actual m8 events dr%d step%d" % [context["route"], context["step"]])
	if include_boundaries:
		for boundary: Callable in [_combat, _native_first_flag]:
			var forked: Dictionary = _fork(combat_source)
			if not forked["ok"] or not boundary.call(forked):
				_cleanup()
				return
	_cleanup()
	print("PASS actual m8 events: selected routes and requested combat boundaries")
	quit(0)


func _opening(content: Dictionary) -> bool:
	var sequence: Array = content["story"]["sequences"]["opening"]
	var focus: Dictionary = sequence[1]
	var commander: Dictionary = sequence[-1]
	return _expect(
		(
			_cell(focus["cell"]) == Vector2i(1, 6)
			and focus["sourceWaitTicks"] == 22
			and _dialogues(content, "opening") == [[560, 1], [561, 87]]
			and sequence[3]["sourceWaitTicksAfter"] == 15
			and sequence[4]["text"]["sourceTextIndex"] == 164
			and _ints(commander["candidates"]) == [1]
			and commander["defaultCommanderId"] == 1
		),
		"Opening keeps sourcefocus1,6/wait22,560new1/561boss87/wait15,objective164/commander1"
	)


func _phases(opened: Dictionary) -> bool:
	var fresh: Dictionary = _fork(opened)
	if not fresh["ok"]:
		return false
	var battle: RefCounted = fresh["battle"]
	var content: Dictionary = opened["content"]
	var events: Array = content["story"]["turnEvents"]
	if not _expect(
		events.size() == 1 and events[0]["afterEnemyPhaseOfRound"] == 2,
		"Only native round2 arrival exists"
	):
		return false
	var event: Dictionary = events[0]
	var party: Array[int] = []
	for slot: int in range(7):
		party.append(int(content["slots"][slot]))
	var entrance: Dictionary = content["story"]["sequences"][event["sequence"]][0]
	if not _expect(
		(
			_ints(event["unitIds"]) == party
			and 1 not in party
			and entrance["kind"] == "parallelEntrances"
			and _cell(entrance["focus"]) == Vector2i(18, 24)
			and entrance["units"].size() == 7
			and _dialogues(content, event["sequence"]) == [[562, 1], [563, 0], [564, 87]]
		),
		"Round2 selects seven old slots excluding new1, then562/563/564"
	):
		return false
	for index: int in range(7):
		var entry: Dictionary = entrance["units"][index]
		var actor: Dictionary = battle.unit(party[index])
		if not _expect(
			(
				entry["unitId"] == party[index]
				and _cell(entry["to"]) == Vector2i(actor["x"], actor["y"])
				and _cell(entry["from"]) == Vector2i(actor["x"], actor["y"] + 3)
			),
			"Southern parallel entrance preserves each fixed cell and three-row offset"
		):
			return false
	var emitted: int = 0
	while battle.round_number < 5:
		var previous: int = battle.round_number
		var restored: Dictionary = _roundtrip(content, battle, "arrival_round_%d" % previous)
		if not restored["ok"]:
			return false
		battle = restored["battle"]
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(advanced["ok"], "Advance controlled automatic waits"):
			return false
		for actual: Dictionary in advanced["events"]:
			emitted += 1
			if not _expect(
				(
					previous == 2
					and actual["sequence"] == event["sequence"]
					and actual["arrivals"].size() == 7
					and battle.unit(1)["visible"]
				),
				"Exactly old-round2 reveals seven units;new1 remains visible"
			):
				return false
		if not _expect(
			battle.event_completed(event["id"]) == (previous >= 2),
			"Arrival once marker follows original round2 boundary"
		):
			return false
	return _expect(emitted == 1, "Cold JSON before and after arrival does not replay it")


func _settlement(opened: Dictionary, context: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var story: Dictionary = content["story"]
	var expected_dialogues: Array = [[567, 1], [488 if context["step"] == 2 else 568, 0]]
	var options: Array = story["routeChoices"]
	if not _expect(
		(
			_dialogues(content, "victory") == expected_dialogues
			and options.size() == 1
			and options[0]["routeIndex"] == context["route"]
			and options[0]["nodeId"] == context["next"]
		),
		"Victory keeps567 and step2-only488/otherwise568 with original fixed route"
	):
		return false
	for step: Dictionary in story["sequences"]["victory"]:
		if not _expect(step["kind"] != "routeChoice", "m8 never asks for a route change"):
			return false
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 1
	var battle := Battle.new(content, _roll, false)
	if not _expect(battle.restore_snapshot(state)["ok"], "Non-required formal death can settle"):
		return false
	if not _expect(battle.win_with_assistance()["ok"], "Controlled victory reaches m8 settlement"):
		return false
	if not _expect(
		not battle.complete_victory((int(context["route"]) + 1) % 8)["ok"],
		"m8 rejects a changed route"
	):
		return false
	var settled: Dictionary = battle.complete_victory(context["route"])
	if not _expect(settled["ok"], "Actual m8 settlement succeeds"):
		return false
	var world: Dictionary = settled["progress"]
	var expected: Array = context["party"].duplicate()
	expected.append(1)
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
			"Settlement revives formal9 and excludes temporary troops"
		):
			return false
		for original: Dictionary in state["units"]:
			if (
				original["id"] == actor["id"]
				and not _expect(
					actor["inventory"] == original["inventory"],
					"Settlement preserves held item identities and durability"
				)
			):
				return false
	var repeated: Dictionary = battle.complete_victory(context["route"])
	if not _expect(
		(
			actual == expected
			and world["route"] == context["route"]
			and world["worldNode"] == 8
			and world["worldStep"] == context["step"] + 1
			and world["completedBattle"] == "m8"
			and world["gold"] == state["gold"] + 1000
			and world["warehouse"] == state["warehouse"]
			and repeated["ok"]
			and repeated["alreadyComplete"]
			and repeated["progress"] == world
		),
		"m8 commits fixed route/new1/1000gold once and resides at node8"
	):
		return false
	var store := Store.new(content, _owned.path_join("world_%d.json" % context["route"]))
	if not _expect(
		store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
		"Write m8 world continue and named slot only in owned directory"
	):
		return false
	var continued: Dictionary = store.read()
	var slotted: Dictionary = store.read_slot(1)
	return _expect(
		(
			continued["ok"]
			and slotted["ok"]
			and continued["progress"] == world
			and slotted["progress"] == world
		),
		"Cold m8 world records retain route,inventory and settlement"
	)


func _combat_setup(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [0, 87]:
			actor["visible"] = true
			actor["flags"] &= ~1
			if actor["id"] == 0:
				# Controlled legal sword; domain-fixture slot0 has no inherited weapon.
				actor["inventory"] = [
					{"id": "m8:controlled:sword", "templateId": 1, "durability": 30}
				]
				actor["equippedInstanceId"] = "m8:controlled:sword"
			actor["x"] = 13
			actor["y"] = 12 if actor["id"] == 0 else 13
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["attributes"]["magic"] = 0
			actor["attributes"]["strength"] = 0
			actor["attributes"]["defense"] = 30
			actor["attributes"]["skill"] = 0
			actor["attributes"]["speed"] = 0
	return _expect(
		opened["battle"].restore_snapshot(state)["ok"],
		"Controlled m8 hero0 uses legal sword1 against actual boss87 inventory"
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
		library.preload_pair(battle.attack_preview(0, 87))["ok"],
		"Actual m8 boss pair resolves complete ordinary clips"
	):
		return false
	_draws = 0
	var first: Dictionary = battle.attack_unit(0, 87)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == [first_event["sequence"]]
			and first["retirements"].is_empty()
			and battle.event_completed(first_event["id"])
			and (int(battle.unit(87)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _dialogues(content, first_event["sequence"]) == [[565, 87]]
			and _draws > 0
		),
		"Ordinary actual boss87 first combat triggers565/native B4 once through shared combat RNG"
	):
		return false
	var ready: Dictionary = battle.snapshot()
	for actor: Dictionary in ready["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
	if not _expect(
		battle.restore_snapshot(ready)["ok"], "Prepare post-first-combat stable boundary"
	):
		return false
	var restored: Dictionary = _roundtrip(content, battle, "first_combat")
	if not restored["ok"]:
		return false
	battle = restored["battle"]
	var second: Dictionary = battle.attack_unit(0, 87)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"Cold JSON restore cannot repeat565"
	):
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 87:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore controlled lethal m8 boss boundary"
	):
		return false
	var killed: Dictionary = battle.attack_unit(0, 87)
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 87,
						"beforeRetirement": [death_event["beforeRetirement"]],
						"afterRetirement": []
					}
				]
			)
			and _dialogues(content, death_event["beforeRetirement"]) == [[566, 87]]
			and not death_event.has("afterRetirement")
			and battle.event_completed(death_event["id"])
			and battle.unit(87)["hp"] == 0
			and not battle.unit(87)["visible"]
			and battle.outcome.is_empty()
			and killed["rewards"]["loot"].size() == 1
			and not killed["rewards"]["experience"].is_empty()
			and library.prepare(killed)["ok"]
		),
		"m8 commits death/drop/XP, schedules566 before retirement and waits for remaining enemies"
	):
		return false
	var reward: Dictionary = killed["rewards"]["experience"]
	if not _expect(
		battle.unit(reward["unit"])["experience"] == reward["after"],
		"m8 boss XP is already committed before presentation"
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
		"Stable m8 boss-death JSON preserves566 once and committed inventory/XP without replay"
	)


func _native_first_flag(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 87:
			actor["flags"] |= 4
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore m8 native B4-only boundary"):
		return false
	var event: Dictionary = _boss_events(opened["content"])["firstCombat"]
	var attacked: Dictionary = battle.attack_unit(0, 87)
	return _expect(
		(
			attacked["ok"]
			and attacked["storyBefore"].is_empty()
			and not battle.event_completed(event["id"])
		),
		"Native B4 already set suppresses565 without requiring its configured once marker"
	)


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	var initial: Array = opened["battle"].snapshot()["units"]
	for required: int in [0, 1]:
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
			"Required0/1 retirement loses with enemies present"
		):
			return false
		for actor: Dictionary in units:
			if actor["faction"] == 2:
				actor["hp"] = 0
				actor["visible"] = false
		var both: Dictionary = rules.outcome(units)
		if not _expect(
			both.get("kind") == "defeat" and both.get("unit") == required,
			"Required0/1 retirement takes priority over simultaneous visible-enemy clear"
		):
			return false
	var boss_only: Array = initial.duplicate(true)
	var others: int = 0
	for actor: Dictionary in boss_only:
		if actor["id"] == 87:
			actor["hp"] = 0
			actor["visible"] = false
		elif actor["faction"] == 2 and actor["visible"] and actor["hp"] > 0:
			others += 1
	if not _expect(
		others > 0 and rules.outcome(boss_only).is_empty(),
		"Boss87 retirement cannot win while another visible enemy remains"
	):
		return false
	var cleared: Array = initial.duplicate(true)
	for actor: Dictionary in cleared:
		if actor["faction"] == 2:
			actor["hp"] = 0
			actor["visible"] = false
			if actor["id"] == 87:
				actor["hp"] = actor["maxHp"]
	if not _expect(
		rules.outcome(cleared).get("kind") == "victory",
		"A living hidden boss cannot block noVisibleEnemies victory"
	):
		return false
	for actor: Dictionary in cleared:
		if actor["id"] == 87:
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
		"Fork an independent deep m8 boundary without initialization RNG"
	):
		return {"ok": false}
	return {"ok": true, "content": opened["content"], "battle": battle}


func _boss_events(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in content["story"]["combatEvents"]:
		if event["unitId"] == 87:
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
	if not _expect(encoded["ok"], "Actual m8 stable boundary encodes: " + name):
		return {"ok": false}
	_draws = 0
	var restored: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == battle.snapshot(),
		(
			"m8 Store JSON cold restore keeps once/phase/units/items with zero initialization RNG: "
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
