extends SceneTree

const Matrix = preload("res://tests/test_m3_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
# Oracle: temp/m3-m7/events/{summary.json,m3/observations.json}, and
# temp/m3/death-story-order/README.md. All battle boundaries below are controlled.
const GROUPS: Array = [[63, 64, 65, 66], [38, 48, 49], [44, 30, 47, 107, 108, 109, 110]]
const FOCI: Array = [[11, 5], [7, 16], [15, 16]]
var _draws: int = 0
var _owned: String = ""


func _initialize() -> void:
	_owned = "user://m3_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim a fresh owned m3 events directory")
		return
	for context: Dictionary in Matrix.CONTEXTS:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare m3 event context: " + str(prepared.get("error"))):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m3", {"progress": prepared["progress"]}, _roll
		)
		if not _expect(opened["ok"], "Open actual m3 events: " + str(opened.get("error"))):
			_cleanup()
			return
		if not _phases(opened) or not _settlement(opened, context) or not _priority(opened):
			_cleanup()
			return
		print("PASS actual m3 events dr%d step%d" % [context["route"], context["step"]])
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _roll)
	for boundary: Callable in [_combat, _native_first_flag, _map_magic]:
		var opened: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m3", {"progress": prepared["progress"]}, _roll
		)
		if (
			not _expect(opened["ok"], "Independent m3 combat boundary must open")
			or not boundary.call(opened)
		):
			_cleanup()
			return
	_cleanup()
	print(
		"PASS actual m3 events: round2 once, route settlement, required-first and boss dialogue phases"
	)
	quit(0)


func _phases(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var initial: Dictionary = battle.snapshot()
	var turn_events: Array = content["story"]["turnEvents"]
	if not _expect(
		(
			turn_events.size() == 1
			and turn_events[0]["afterEnemyPhaseOfRound"] == 2
			and content["story"]["aiChanges"].is_empty()
			and _dialogues(content, "opening") == [[509, 3], [510, 83]]
		),
		"m3 has one round2 event and no unreachable source AI10 policy change"
	):
		return false
	var event: Dictionary = turn_events[0]
	var sequence: Array = content["story"]["sequences"][event["sequence"]]
	var expected_party: Array = []
	for slot: int in range(6):
		expected_party.append(content["slots"][slot])
	var group_index: int = 0
	var entrance_index: int = -1
	for index: int in range(sequence.size()):
		var step: Dictionary = sequence[index]
		if step["kind"] == "revealUnits":
			var reveal_ids: Array[int] = []
			for id: Variant in step["unitIds"]:
				reveal_ids.append(int(id))
			if not _expect(
				(
					group_index < 3
					and reveal_ids == GROUPS[group_index]
					and index > 0
					and sequence[index - 1]["kind"] == "focus"
					and _cell(sequence[index - 1]["cell"]) == _cell(FOCI[group_index])
				),
				"m3 round2 focuses each captured group before instant revealUnits"
			):
				return false
			group_index += 1
		if step["kind"] == "parallelEntrances":
			entrance_index = index
			var ids: Array = []
			for entrance: Dictionary in step["units"]:
				var id: int = entrance["unitId"]
				ids.append(id)
				var actor: Dictionary = battle.unit(id)
				if not _expect(
					(
						_cell(entrance["to"]) == Vector2i(actor["x"], actor["y"])
						and _cell(entrance["from"]) == Vector2i(actor["x"], actor["y"] - 3)
					),
					"m3 party entrance starts north and ends at its actual deployment cell"
				):
					return false
			if not _expect(
				ids == expected_party and _cell(step["focus"]) == Vector2i(16, 3),
				"All six old slots enter, excluding current recruit3"
			):
				return false
	if not _expect(
		(
			group_index == 3
			and entrance_index > 0
			and sequence[entrance_index - 1]["text"]["sourceTextIndex"] == 511
			and _dialogues(content, event["sequence"]) == [[511, 3], [512, 3], [513, 0]]
			and sequence[entrance_index + 1]["text"]["sourceTextIndex"] == 512
			and sequence[entrance_index + 2]["text"]["sourceTextIndex"] == 513
		),
		"m3 round2 preserves three reveals,511,parallel party entrance,512,513 ordering"
	):
		return false
	var expected_ids: Array = []
	for group: Array in GROUPS:
		expected_ids.append_array(group)
	expected_ids.append_array(expected_party)
	var declared: Array = event["unitIds"].duplicate()
	expected_ids.sort()
	declared.sort()
	if not _expect(
		declared == expected_ids,
		"Domain round2 covers exactly the revealed enemy groups and six slots"
	):
		return false
	var emitted: int = 0
	while battle.round_number < 4:
		var previous_round: int = battle.round_number
		if battle.phase != 0:
			var id: int = battle.automatic_actor()
			while id >= 0:
				if not _expect(
					battle.wait_unit(id)["ok"],
					"Controlled automatic waiting finishes a real m3 phase"
				):
					return false
				id = battle.automatic_actor()
		var changed: Dictionary = battle.end_phase()
		if not _expect(changed["ok"], "Real m3 phase transition: " + str(changed.get("error"))):
			return false
		for emitted_event: Dictionary in changed["events"]:
			emitted += 1
			if not _expect(
				previous_round == 2 and emitted_event["sequence"] == event["sequence"],
				"Only enemy-phase completion of round2 emits m3 reinforcements"
			):
				return false
		if battle.phase == 0 and battle.round_number in [2, 3]:
			var after: bool = battle.round_number == 3
			if not _expect(
				battle.event_completed(event["id"]) == after,
				"m3 round2 once marker changes only after its enemy phase"
			):
				return false
			for id: int in expected_ids:
				if not _expect(
					battle.unit(id)["visible"] == after,
					"m3 domain reveal visibility follows the original round2 boundary"
				):
					return false
			var restored: Dictionary = _roundtrip(content, battle, "round%d" % battle.round_number)
			if not restored["ok"]:
				return false
			battle = restored["battle"]
	if not _expect(
		emitted == 1, "Reloading before and after round2 cannot duplicate its single event"
	):
		return false
	for actor: Dictionary in initial["units"]:
		var current: Dictionary = battle.unit(actor["id"])
		if not _expect(
			current["visible"] and [current["x"], current["y"]] == [actor["x"], actor["y"]],
			"m3 revealing and entrance animation preserve every real final coordinate"
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
		if step["kind"] == "dialogue" and step["text"]["sourceTextIndex"] == 517:
			if not _expect(
				step.get("sourceWaitTicksAfter") == 15, "step1 text517 keeps its fifteen-tick wait"
			):
				return false
	if not _expect(
		(
			options == ([[2, 3], [4, 2]] if early else [[context["next"], context["route"]]])
			and selection_count == (1 if early else 0)
			and _dialogues(content, "victory") == ([[517, 3]] if early else [])
		),
		"Only step1 asks next2/4 -> route3/2; later m3 retains its route and actual next node"
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
		var fresh: Dictionary = Session.new().open(Matrix.CHAPTER, "m3", {"snapshot": state}, _roll)
		if not _expect(fresh["ok"], "Controlled formal-death m3 settlement snapshot remains valid"):
			return false
		var battle: RefCounted = fresh["battle"]
		if not _expect(
			battle.win_with_assistance()["ok"], "Controlled m3 victory can reach real settlement"
		):
			return false
		if not early:
			var wrong: int = (int(context["route"]) + 1) % 8
			if not _expect(
				not battle.complete_victory(wrong)["ok"], "Fixed-route m3 rejects a different route"
			):
				return false
		var settled: Dictionary = battle.complete_victory(option[1])
		if not _expect(settled["ok"], "Actual m3 route settlement succeeds"):
			return false
		var world: Dictionary = settled["progress"]
		var expected: Array = context["party"].duplicate()
		expected.append(3)
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
				"m3 settlement revives formal9, restores formal state and omits temporary troops"
			):
				return false
			for original: Dictionary in state["units"]:
				if original["id"] == actor["id"]:
					if not _expect(
						actor["inventory"] == original["inventory"],
						"m3 settlement preserves held item identity/durability"
					):
						return false
		var repeated: Dictionary = battle.complete_victory(option[1])
		if not _expect(
			(
				actual == expected
				and world["route"] == option[1]
				and world["worldNode"] == 3
				and world["worldStep"] == context["step"] + 1
				and world["completedBattle"] == "m3"
				and world["gold"] == state["gold"] + 1000
				and world["warehouse"] == state["warehouse"]
				and repeated["ok"]
				and repeated["alreadyComplete"]
				and repeated["progress"] == world
				and battle.gold == world["gold"]
			),
			"m3 commits route,1000 gold,formal roster and warehouse exactly once while residing at node3"
		):
			return false
		var store: RefCounted = Store.new(
			content, _owned.path_join("world_%d_%d.json" % [context["route"], option[1]])
		)
		if not _expect(
			store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
			"m3 world writes owned continue and slot"
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
			"m3 world JSON restores chosen route, inventory and completed step-1 projection"
		):
			return false
	return true


func _combat_setup(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 3:
			actor["x"] = 19
			actor["y"] = 19
			actor["attributes"]["strength"] = 0
			actor["attributes"]["defense"] = 30
		if actor["id"] == 83:
			actor["x"] = 19
			actor["y"] = 20
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["attributes"]["defense"] = 30
			actor["attributes"]["strength"] = 0
	return _expect(
		opened["battle"].restore_snapshot(state)["ok"],
		"Legal controlled m3 boss duel with actual equipment"
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
		library.preload_pair(battle.attack_preview(3, 83))["ok"],
		"Actual m3 boss pair resolves real complete clips"
	):
		return false
	var first: Dictionary = battle.attack_unit(3, 83)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == [first_event["sequence"]]
			and first["retirements"].is_empty()
			and battle.event_completed(first_event["id"])
			and (int(battle.unit(83)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _dialogues(content, first_event["sequence"]) == [[514, 83]]
		),
		"Ordinary actual boss83 combat triggers514 and native B4 once"
	):
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 3:
			actor["action"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Reset actor for post-first-combat JSON boundary"
	):
		return false
	var restored: Dictionary = _roundtrip(content, battle, "first_combat")
	if not restored["ok"]:
		return false
	battle = restored["battle"]
	var second: Dictionary = battle.attack_unit(3, 83)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"JSON restore cannot repeat514"
	):
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 3:
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 83:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Controlled lethal m3 boss boundary restores"
	):
		return false
	var killed: Dictionary = battle.attack_unit(3, 83)
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 83,
						"beforeRetirement": [death_event["beforeRetirement"]],
						"afterRetirement": [death_event["afterRetirement"]]
					}
				]
			)
			and _dialogues(content, death_event["beforeRetirement"]) == [[515, 83]]
			and _dialogues(content, death_event["afterRetirement"]) == [[516, 0]]
			and battle.event_completed(death_event["id"])
			and battle.unit(83)["hp"] == 0
			and not battle.unit(83)["visible"]
			and killed["rewards"]["loot"].size() == 1
			and not killed["rewards"]["experience"].is_empty()
			and library.prepare(killed)["ok"]
		),
		"m3 immediately settles death/drop/XP, scheduling515 before retirement and516 after it"
	):
		return false
	var reward: Dictionary = killed["rewards"]["experience"]
	if not _expect(
		battle.unit(reward["unit"])["experience"] == reward["after"],
		"m3 XP is already committed before presentation"
	):
		return false
	restored = _roundtrip(content, battle, "boss_death")
	if not restored["ok"]:
		return false
	var stored: Dictionary = restored["battle"].snapshot()
	var replay: Dictionary = Events.new(content).combat_events(
		killed["participants"], stored["units"], stored["events"]
	)
	return _expect(
		(
			restored["battle"].event_completed(death_event["id"])
			and replay["completed"].is_empty()
			and replay["before"].is_empty()
			and replay["retirements"][0]["beforeRetirement"].is_empty()
			and replay["retirements"][0]["afterRetirement"].is_empty()
		),
		"JSON preserves boss death once without replaying515/516 or redoing inventory/XP"
	)


func _native_first_flag(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 83:
			actor["flags"] |= 4
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Source B4-only first-combat boundary restores"
	):
		return false
	var event: Dictionary = _boss_events(opened["content"])["firstCombat"]
	var attacked: Dictionary = battle.attack_unit(3, 83)
	return _expect(
		(
			attacked["ok"]
			and attacked["storyBefore"].is_empty()
			and not battle.event_completed(event["id"])
		),
		"Native B4 already set suppresses514 even without its configured event marker"
	)


func _map_magic(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 3  # Actual earthquake contract: every third round.
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["inventory"] = [{"id": "m3:controlled:map", "templateId": 46, "durability": 3}]
			actor["equippedInstanceId"] = "m3:controlled:map"
			actor["attributes"]["magic"] = 30
		if actor["id"] == 83:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Legal real m3 map-magic controlled boundary"
	):
		return false
	var cast: Dictionary = battle.cast_map_attack(7, "m3:controlled:map")
	var config: Dictionary = _boss_events(opened["content"])
	return _expect(
		(
			cast["ok"]
			and battle.unit(83)["hp"] == 0
			and cast["storyBefore"].is_empty()
			and cast["storyAfter"].is_empty()
			and not battle.event_completed(config["firstCombat"]["id"])
			and not battle.event_completed(config["unitDeath"]["id"])
			and (int(battle.unit(83)["flags"]) & 4) == 0
		),
		"Actual m3 map magic skips ordinary514/515/516 and preserves all ordinary once markers"
	)


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	for required: int in [0, 3]:
		var units: Array = opened["battle"].snapshot()["units"]
		for actor: Dictionary in units:
			if actor["id"] == required:
				actor["hp"] = 0
				actor["visible"] = true
		if not _expect(
			rules.outcome(units).is_empty(),
			"Visible HP0 required actor is a death transition, not yet defeat"
		):
			return false
		for actor: Dictionary in units:
			if actor["id"] == required:
				actor["visible"] = false
		if not _expect(
			rules.outcome(units).get("kind") == "defeat",
			"Required0/3 retired with enemies present loses"
		):
			return false
		for actor: Dictionary in units:
			if actor["faction"] == 2 and actor["visible"]:
				actor["hp"] = 0
				actor["visible"] = false
		var both: Dictionary = rules.outcome(units)
		if not _expect(
			both.get("kind") == "defeat" and both.get("unit") == required,
			"Required0/3 death wins priority over simultaneous enemy clear"
		):
			return false
	var early: Array = opened["battle"].snapshot()["units"]
	var future: int = 0
	for actor: Dictionary in early:
		if actor["faction"] == 2:
			if actor["visible"]:
				actor["hp"] = 0
				actor["visible"] = false
			else:
				future += 1
	if not _expect(
		future == 14 and rules.outcome(early).get("kind") == "victory",
		"Fourteen living hidden future enemies do not prevent early m3 victory"
	):
		return false
	for actor: Dictionary in early:
		if actor["id"] == 83:
			actor["visible"] = true
	return _expect(
		rules.outcome(early).is_empty(),
		"Visible HP0 enemy still blocks noVisibleEnemies until retirement"
	)


func _boss_events(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in content["story"]["combatEvents"]:
		if event["unitId"] == 83:
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
	if not _expect(encoded["ok"], "Actual m3 stable boundary encodes: " + name):
		return {"ok": false}
	_draws = 0
	var restored: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == battle.snapshot(),
		(
			"Actual m3 JSON restore preserves once/phase/units/inventory without initialization RNG: "
			+ name
		)
	):
		return {"ok": false}
	return restored


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


# JSON numeric arrays use float Variants; grid coordinates have integer meaning.
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
