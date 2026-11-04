extends SceneTree

const Matrix = preload("res://tests/test_m10_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
# Oracle: temp/m10/discovery.md,items.md and original-route-*/observations.json.
# Automatic turns wait; combat and occupancy boundaries are explicit fixtures.
var _draws: int = 0
var _owned: String = ""


func _initialize() -> void:
	_owned = "user://m10_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim fresh owned m10 event directory")
		return
	var combat_source: Dictionary = {}
	for context: Dictionary in Matrix.CONTEXTS:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare m10 event context: " + str(prepared.get("error"))):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m10", prepared["source"], _roll
		)
		if not _expect(opened["ok"], "Open actual m10 events: " + str(opened.get("error"))):
			_cleanup()
			return
		if context["route"] == 6:
			combat_source = opened
		if (
			not _opening(opened["content"])
			or not _phases(opened)
			or not _settlement(opened, context)
			or not _priority(opened)
		):
			_cleanup()
			return
		print("PASS actual m10 events dr%d step%d" % [context["route"], context["step"]])
	for boundary: Callable in [_combat, _native_first_flag, _revival, _map_magic]:
		var forked: Dictionary = _fork(combat_source)
		if not forked["ok"] or not boundary.call(forked):
			_cleanup()
			return
	_cleanup()
	print("PASS actual m10 events: quiet rounds,boss90/80/map51 and settlement")
	quit(0)


func _opening(content: Dictionary) -> bool:
	var sequence: Array = content["story"]["sequences"]["opening"]
	var commander: Dictionary = sequence[-1]
	return _expect(
		(
			_cell(sequence[1]["cell"]) == Vector2i(22, 3)
			and sequence[1]["sourceWaitTicks"] == 22
			and _dialogues(content, "opening") == [[572, 90], [573, 0], [574, 90]]
			and sequence[4]["sourceWaitTicksAfter"] == 15
			and sequence[5]["text"]["sourceTextIndex"] == 166
			and commander["defaultCommanderId"] == 9
		),
		"m10 keeps focus22,3/wait22,572/573/574,objective166/formal commander9"
	)


func _phases(opened: Dictionary) -> bool:
	var forked: Dictionary = _fork(opened)
	if not forked["ok"]:
		return false
	var battle: RefCounted = forked["battle"]
	var original: Dictionary = {}
	for actor: Dictionary in battle.snapshot()["units"]:
		original[actor["id"]] = actor["policy"]
	if not _expect(
		(
			opened["content"]["story"]["turnEvents"].is_empty()
			and opened["content"]["story"]["aiChanges"].is_empty()
		),
		"m10 declares no map-specific rounds/AI changes"
	):
		return false
	while battle.round_number < 11:
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(
			advanced["ok"] and advanced["events"].is_empty(),
			"Controlled wait rounds stay quiet through10"
		):
			return false
	for actor: Dictionary in battle.snapshot()["units"]:
		if not _expect(
			actor["policy"] == original[actor["id"]], "No unreachable round10 AI branch is invented"
		):
			return false
	return true


func _settlement(opened: Dictionary, context: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var story: Dictionary = content["story"]
	var expected_dialogues: Array = [[577, 8], [578 if context["step"] == 5 else 579, 0]]
	var options: Array = story["routeChoices"]
	if not _expect(
		(
			_dialogues(content, "victory") == expected_dialogues
			and options.size() == 1
			and options[0]["routeIndex"] == context["route"]
			and options[0]["nodeId"] == context["next"]
		),
		"Victory keeps577 and step5-only578/otherwise579 with original fixed route"
	):
		return false
	for step: Dictionary in story["sequences"]["victory"]:
		if not _expect(step["kind"] != "routeChoice", "m10 never asks for a route change"):
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
	if not _expect(battle.win_with_assistance()["ok"], "Controlled victory reaches m10 settlement"):
		return false
	if not _expect(
		not battle.complete_victory((int(context["route"]) + 1) % 8)["ok"],
		"m10 rejects a changed route"
	):
		return false
	var settled: Dictionary = battle.complete_victory(context["route"])
	if not _expect(settled["ok"], "Actual m10 settlement succeeds"):
		return false
	var world: Dictionary = settled["progress"]
	var expected: Array = context["party"].duplicate()

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
			and world["worldNode"] == 10
			and world["worldStep"] == context["step"] + 1
			and world["completedBattle"] == "m10"
			and world["gold"] == state["gold"] + 1000
			and world["warehouse"] == state["warehouse"]
			and repeated["ok"]
			and repeated["alreadyComplete"]
			and repeated["progress"] == world
		),
		"m10 commits fixed route/party/1000gold once and resides at node8"
	):
		return false
	var store := Store.new(content, _owned.path_join("world_%d.json" % context["route"]))
	if not _expect(
		store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
		"Write m10 world continue and named slot only in owned directory"
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
		"Cold m10 world records retain route,inventory and settlement"
	)


func _combat_setup(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [0, 90]:
			actor["visible"] = true
			actor["flags"] &= ~1
			if actor["id"] == 0:
				# Controlled legal sword; domain-fixture slot0 has no inherited weapon.
				actor["inventory"] = [
					{"id": "m10:controlled:sword", "templateId": 1, "durability": 30}
				]
				actor["equippedInstanceId"] = "m10:controlled:sword"
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
		"Controlled m10 hero0 uses legal sword1 against actual boss90 inventory"
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
		library.preload_pair(battle.attack_preview(0, 90))["ok"],
		"Actual m10 boss pair resolves complete ordinary clips"
	):
		return false
	_draws = 0
	var first: Dictionary = battle.attack_unit(0, 90)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == [first_event["sequence"]]
			and first["retirements"].is_empty()
			and battle.event_completed(first_event["id"])
			and (int(battle.unit(90)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _dialogues(content, first_event["sequence"]) == [[575, 90]]
			and _draws > 0
		),
		"Ordinary actual boss90 first combat triggers575/native B4 once through shared combat RNG"
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
	var second: Dictionary = battle.attack_unit(0, 90)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"Cold JSON restore cannot repeat575"
	):
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 90:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore controlled lethal m10 boss boundary"
	):
		return false
	var killed: Dictionary = battle.attack_unit(0, 90)
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 90,
						"beforeRetirement": [death_event["beforeRetirement"]],
						"afterRetirement": []
					}
				]
			)
			and _dialogues(content, death_event["beforeRetirement"]) == [[576, 90]]
			and not death_event.has("afterRetirement")
			and battle.event_completed(death_event["id"])
			and battle.unit(90)["hp"] == 0
			and not battle.unit(90)["visible"]
			and battle.outcome.is_empty()
			and killed["rewards"]["loot"].size() == 1
			and not killed["rewards"]["experience"].is_empty()
			and library.prepare(killed)["ok"]
		),
		"m10 commits death/drop/XP, schedules576 before retirement and waits for remaining enemies"
	):
		return false
	var reward: Dictionary = killed["rewards"]["experience"]
	if not _expect(
		battle.unit(reward["unit"])["experience"] == reward["after"],
		"m10 boss XP is already committed before presentation"
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
		"Stable m10 boss-death JSON preserves576 once and committed inventory/XP without replay"
	)


func _native_first_flag(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 90:
			actor["flags"] |= 4
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore m10 native B4-only boundary"):
		return false
	var event: Dictionary = _boss_events(opened["content"])["firstCombat"]
	var attacked: Dictionary = battle.attack_unit(0, 90)
	return _expect(
		(
			attacked["ok"]
			and attacked["storyBefore"].is_empty()
			and not battle.event_completed(event["id"])
		),
		"Native B4 already set suppresses575 without requiring its configured once marker"
	)


func _revival(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 2 and actor["id"] != 39:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 1
		if actor["id"] in [0, 39]:
			actor["x"] = 13
			actor["y"] = 12 if actor["id"] == 0 else 13
			actor["hp"] = actor["maxHp"] if actor["id"] == 0 else 1
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["action"] = 0
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 30 if actor["id"] == 0 else 0
			if actor["id"] == 0:
				actor["inventory"] = [{"id": "m10:revive:sword", "templateId": 1, "durability": 30}]
				actor["equippedInstanceId"] = "m10:revive:sword"
	var restored: Dictionary = Session.new().open(Matrix.CHAPTER, "m10", {"snapshot": state}, _roll)
	if not _expect(restored["ok"], "Prepare last80 holder using actual m10 source39"):
		return false
	var battle: RefCounted = restored["battle"]
	var hit: Dictionary = battle.attack_unit(0, 39)
	if not _expect(
		(
			hit["ok"]
			and hit.get("revivals", []).size() == 1
			and battle.unit(39)["visible"]
			and battle.unit(39)["hp"] == battle.unit(39)["maxHp"]
			and battle.outcome.is_empty()
		),
		"Actual80 restores final enemy before noVisibleEnemies can win"
	):
		return false
	for held: Dictionary in battle.unit(39)["inventory"]:
		if not _expect(held["templateId"] != 80, "Revival consumes actual80 once"):
			return false
	var cold: Dictionary = _roundtrip(content, battle, "revival")
	if not cold["ok"]:
		return false
	battle = cold["battle"]
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
		if actor["id"] == 39:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Prepare second knockdown after cold restore"
	):
		return false
	var second: Dictionary = battle.attack_unit(0, 39)
	return _expect(
		(
			second["ok"]
			and second.get("revivals", []).is_empty()
			and not battle.unit(39)["visible"]
			and battle.outcome.get("kind") == "victory"
		),
		"Without80 the next real knockdown retires and permits victory"
	)


func _map_magic(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	state["round"] = 2
	var lightning: Dictionary = {}
	var vacated: Vector2i
	for actor: Dictionary in state["units"]:
		if actor["id"] == 8:
			vacated = Vector2i(actor["x"], actor["y"])
	for actor: Dictionary in state["units"]:
		if actor["id"] == 90:
			for held: Dictionary in actor["inventory"]:
				if held["templateId"] == 51:
					lightning = held
					actor["inventory"].erase(held)
					actor["equippedInstanceId"] = ""
					break
	for actor: Dictionary in state["units"]:
		if actor["id"] == 37:
			# The audited low initialization occupies10,10. Move this real
			# sorcerer to8's vacated cell; preserve its family,80 and visibility.
			actor["x"] = vacated.x
			actor["y"] = vacated.y
		if actor["id"] == 8:
			actor["x"] = 10
			actor["y"] = 10
			actor["inventory"].append(lightning)
			actor["equippedInstanceId"] = lightning["id"]
			actor["attributes"]["magic"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] in [90, 39]:
			actor["x"] = 12
			actor["y"] = 10 if actor["id"] == 90 else 11
			actor["hp"] = 1
			actor["attributes"]["magic"] = 0
			actor["attributes"]["speed"] = 0
			actor["attributes"]["luck"] = 0
	var fresh: Dictionary = Session.new().open(Matrix.CHAPTER, "m10", {"snapshot": state}, _roll)
	if not _expect(
		not lightning.is_empty() and fresh["ok"], "Transfer actual Boss51 into legal formal8 bag"
	):
		return false
	var battle: RefCounted = fresh["battle"]
	var cast: Dictionary = battle.cast_map_attack(8, lightning["id"], 90)
	return _expect(
		(
			cast["ok"]
			and cast["kind"] == "map_attack"
			and cast.get("revivals", []).size() == 1
			and battle.unit(39)["visible"]
			and battle.unit(39)["hp"] == battle.unit(39)["maxHp"]
			and not battle.unit(90)["visible"]
			and cast["rewards"]["loot"].is_empty()
			and not battle.event_completed("boss_first_combat")
			and not battle.event_completed("boss_death")
			and cast.get("storyBefore", []).is_empty()
			and cast.get("storyAfter", []).is_empty()
		),
		"Actual51 keeps anyKill/80 revival and excludes ordinary575/576 and drops"
	)


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	var initial: Array = opened["battle"].snapshot()["units"]
	for required: int in [0]:
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
			"Required0 retirement loses with enemies present"
		):
			return false
		for actor: Dictionary in units:
			if actor["faction"] == 2:
				actor["hp"] = 0
				actor["visible"] = false
		var both: Dictionary = rules.outcome(units)
		if not _expect(
			both.get("kind") == "defeat" and both.get("unit") == required,
			"Required0 retirement takes priority over simultaneous visible-enemy clear"
		):
			return false
	var boss_only: Array = initial.duplicate(true)
	var others: int = 0
	for actor: Dictionary in boss_only:
		if actor["id"] == 90:
			actor["hp"] = 0
			actor["visible"] = false
		elif actor["faction"] == 2 and actor["visible"] and actor["hp"] > 0:
			others += 1
	if not _expect(
		others > 0 and rules.outcome(boss_only).is_empty(),
		"Boss90 retirement cannot win while another visible enemy remains"
	):
		return false
	var cleared: Array = initial.duplicate(true)
	for actor: Dictionary in cleared:
		if actor["faction"] == 2:
			actor["hp"] = 0
			actor["visible"] = false
			if actor["id"] == 90:
				actor["hp"] = actor["maxHp"]
	if not _expect(
		rules.outcome(cleared).get("kind") == "victory",
		"A living hidden boss cannot block noVisibleEnemies victory"
	):
		return false
	for actor: Dictionary in cleared:
		if actor["id"] == 90:
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
		"Fork an independent deep m10 boundary without initialization RNG"
	):
		return {"ok": false}
	return {"ok": true, "content": opened["content"], "battle": battle}


func _boss_events(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in content["story"]["combatEvents"]:
		if event["unitId"] == 90:
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
	if not _expect(encoded["ok"], "Actual m10 stable boundary encodes: " + name):
		return {"ok": false}
	_draws = 0
	var restored: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == battle.snapshot(),
		(
			"m10 Store JSON cold restore keeps once/phase/units/items with zero initialization RNG: "
			+ name
		)
	):
		return {"ok": false}
	return restored


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


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
