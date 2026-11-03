extends SceneTree

const Matrix = preload("res://tests/test_m11_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const Flow = preload("res://tests/test_m11_flow.gd")
# Oracle: temp/m11/runtime-findings.md and p11-oracle.json.
# Automatic turns wait; combat and occupancy boundaries are explicit fixtures.
var _draws: int = 0
var _draw_limits: Array[int] = []
var _owned: String = ""


func _initialize() -> void:
	_owned = "user://m11_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Fresh event directory required")
		return
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _roll)
	if not _expect(prepared["ok"], "Prepare phase context"):
		_cleanup()
		return
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m11", prepared["source"], _roll)
	if not _expect(opened["ok"], "Open phase context") or not _phases(opened):
		_cleanup()
		return
	_cleanup()
	print("PASS m11 events: round2,six finite clone waves,cold rounds3/8/9")
	quit(0)


func _opening(content: Dictionary) -> bool:
	return _expect(
		(
			_dialogues(content, "opening") == [[580, 50], [581, 88], [582, 0]]
			and content["story"]["speakers"]["50"]["name"] == ""
			and not content["story"]["speakers"]["50"].has("portraitId")
		),
		"Opening580 remains explicitly anonymous enemy,581/582 keep speakers"
	)


func _phases(opened: Dictionary) -> bool:
	var forked: Dictionary = _fork(opened)
	if not forked["ok"]:
		return false
	var battle: RefCounted = forked["battle"]
	var revealed: int = 0
	var total_births: int = 0
	var rounds: Array[int] = []
	var originals: Dictionary = {}
	for identity: int in [44, 45, 46, 56, 57, 58, 59, 47, 48, 49, 55, 61, 62, 63]:
		originals[identity] = Vector2i(battle.unit(identity)["x"], battle.unit(identity)["y"])
	while battle.round_number < 10:
		var previous: int = battle.round_number
		var before_draws: int = _draws
		var before_limits: int = _draw_limits.size()
		var phase_heal_draws: Array[int] = []
		for actor: Dictionary in battle.snapshot()["units"]:
			for held: Dictionary in actor["inventory"]:
				if int(held["templateId"]) == 81:
					phase_heal_draws.append(11)
					break
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(advanced["ok"], "Actual phase commands reach round%d" % (previous + 1)):
			return false
		# Ring81 draws once per holder at player-phase start, even at full HP.
		# Audited round1/2/3 stacks: temp/m11/phase-rng-diagnostic.log.
		if not _expect(
			(
				_draws - before_draws == phase_heal_draws.size()
				and _draw_limits.slice(before_limits) == phase_heal_draws
			),
			"Only declared81 phase-recovery draws occur; fixed clone selection adds zero RNG"
		):
			return false
		var cloned: bool = false
		for event: Dictionary in advanced["events"]:
			if event["kind"] == "reinforcements":
				revealed += 1
				if not _expect(
					previous == 2 and event["arrivals"].size() == 14,
					"Exactly14 reinforcements at round2; templates excluded"
				):
					return false
				for identity: int in originals:
					var actor: Dictionary = battle.unit(identity)
					if not _expect(
						(
							actor["visible"]
							and Vector2i(actor["x"], actor["y"]) == originals[identity]
						),
						"No-occupancy group reveal preserves original business position"
					):
						return false
			if event["kind"] != "clones":
				continue
			cloned = true
			rounds.append(previous)
			if not _expect(
				event["births"].size() == 2, "Each scheduled round constructs114 then115 once"
			):
				return false
			for index: int in range(2):
				var born: Dictionary = event["births"][index]
				var actor: Dictionary = battle.unit(born["unit"])
				var template: Dictionary = battle.unit(114 + index)
				if not _expect(
					(
						actor["sourceId"] == 114 + index
						and actor["classId"] == template["classId"]
						and actor["attributes"] == template["attributes"]
						and actor["hp"] == template["maxHp"]
						and actor["inventory"][0]["id"] != template["inventory"][0]["id"]
						and (
							actor["inventory"][0]["templateId"]
							== template["inventory"][0]["templateId"]
						)
					),
					"Every clone preserves source family and gets its own actual item"
				):
					return false
				total_births += 1
		if not _expect(
			cloned == (previous >= 3 and previous <= 8),
			"Rounds1/2/9 have no births;6 uses first match once"
		):
			return false
		if previous in [3, 8, 9]:
			var cold: Dictionary = _roundtrip(opened["content"], battle, "round%d" % previous)
			if not cold["ok"]:
				return false
			battle = cold["battle"]
	if not _expect(
		(
			revealed == 1
			and rounds == [3, 4, 5, 6, 7, 8]
			and total_births == 12
			and battle.snapshot()["units"].size() == 67
			and not battle.unit(114)["visible"]
			and not battle.unit(115)["visible"]
			and _draws == 0
		),
		"Finite six waves retain67 objects/templates; every cold restore is RNG0"
	):
		return false
	return true


func _settlement(opened: Dictionary, context: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var story: Dictionary = content["story"]
	var expected_dialogues: Array = [[585, 4], [586 if context["step"] == 5 else 587, 0]]
	var options: Array = story["routeChoices"]
	if not _expect(
		(
			_dialogues(content, "victory") == expected_dialogues
			and options.size() == 1
			and options[0]["routeIndex"] == context["route"]
			and options[0]["nodeId"] == context["next"]
		),
		"Victory keeps585 and step5-only586/otherwise587 with original fixed route"
	):
		return false
	for step: Dictionary in story["sequences"]["victory"]:
		if not _expect(step["kind"] != "routeChoice", "m11 never asks for a route change"):
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
	if not _expect(battle.win_with_assistance()["ok"], "Controlled victory reaches m11 settlement"):
		return false
	if not _expect(
		not battle.complete_victory((int(context["route"]) + 1) % 8)["ok"],
		"m11 rejects a changed route"
	):
		return false
	var settled: Dictionary = battle.complete_victory(context["route"])
	if not _expect(settled["ok"], "Actual m11 settlement succeeds"):
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
			and world["worldNode"] == 11
			and world["worldStep"] == context["step"] + 1
			and world["completedBattle"] == "m11"
			and world["gold"] == state["gold"] + 1000
			and world["warehouse"] == state["warehouse"]
			and repeated["ok"]
			and repeated["alreadyComplete"]
			and repeated["progress"] == world
		),
		"m11 commits fixed route/party/1000gold once and resides at node11"
	):
		return false
	var store := Store.new(content, _owned.path_join("world_%d.json" % context["route"]))
	if not _expect(
		store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
		"Write m11 world continue and named slot only in owned directory"
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
		"Cold m11 world records retain route,inventory and settlement"
	)


func _combat_setup(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [0, 88]:
			actor["visible"] = true
			actor["flags"] &= ~1
			if actor["id"] == 0:
				# Controlled legal sword; domain-fixture slot0 has no inherited weapon.
				actor["inventory"] = [
					{"id": "m11:controlled:sword", "templateId": 1, "durability": 30}
				]
				actor["equippedInstanceId"] = "m11:controlled:sword"
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
		"Controlled m11 hero0 uses legal sword1 against actual boss88 inventory"
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
		library.preload_pair(battle.attack_preview(0, 88))["ok"],
		"Actual m11 boss pair resolves complete ordinary clips"
	):
		return false
	_draws = 0
	var first: Dictionary = battle.attack_unit(0, 88)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == [first_event["sequence"]]
			and first["retirements"].is_empty()
			and battle.event_completed(first_event["id"])
			and (int(battle.unit(88)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
			and _dialogues(content, first_event["sequence"]) == [[583, 88]]
			and _draws > 0
		),
		"Ordinary actual boss88 first combat triggers583/native B4 once through shared combat RNG"
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
	var second: Dictionary = battle.attack_unit(0, 88)
	if not _expect(
		second["ok"] and second["storyBefore"].is_empty() and second["retirements"].is_empty(),
		"Cold JSON restore cannot repeat583"
	):
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 88:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore controlled lethal m11 boss boundary"
	):
		return false
	var killed: Dictionary = battle.attack_unit(0, 88)
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 88,
						"beforeRetirement": [death_event["beforeRetirement"]],
						"afterRetirement": []
					}
				]
			)
			and _dialogues(content, death_event["beforeRetirement"]) == [[584, 88]]
			and not death_event.has("afterRetirement")
			and battle.event_completed(death_event["id"])
			and battle.unit(88)["hp"] == 0
			and not battle.unit(88)["visible"]
			and battle.outcome.get("kind") == "victory"
			and killed["rewards"]["loot"].is_empty()
			and not killed["rewards"]["experience"].is_empty()
			and library.prepare(killed)["ok"]
		),
		"m11 schedules584 before boss88 retirement, commits XP and wins with other enemies alive"
	):
		return false
	var reward: Dictionary = killed["rewards"]["experience"]
	if not _expect(
		battle.unit(reward["unit"])["experience"] == reward["after"],
		"m11 boss XP is already committed before presentation"
	):
		return false
	# Boss retirement ends this battle. The next legal cold record is settled world,
	# not a battle snapshot with terminal outcome or unfinished presentation.
	var refused: Dictionary = Store.new(content).encode(battle)
	if not _expect(
		not refused["ok"] and refused.get("error") == "BATTLE_NOT_STABLE",
		"Terminal victory cannot be encoded as resumable battle"
	):
		return false
	var stored: Dictionary = battle.snapshot()
	var replay: Dictionary = Events.new(content).combat_events(
		killed["participants"], killed["retirements"], stored["events"]
	)
	if not _expect(
		(
			battle.event_completed(death_event["id"])
			and replay["completed"].is_empty()
			and replay["before"].is_empty()
			and replay["retirements"][0]["beforeRetirement"].is_empty()
			and replay["retirements"][0]["afterRetirement"].is_empty()
		),
		"Committed boss584 marker prevents repeated retirement dialogue"
	):
		return false
	var settled: Dictionary = battle.complete_victory(int(stored["campaign"]["route"]))
	if not _expect(settled["ok"], "Actual boss victory settles before world record"):
		return false
	var store := Store.new(content, _owned.path_join("boss_world.json"))
	var encoded: Dictionary = store.encode_progress(settled["progress"])
	if not _expect(encoded["ok"], "Completed boss world record encodes"):
		return false
	_draws = 0
	var cold: Dictionary = store.decode(JSON.parse_string(JSON.stringify(encoded["record"])), _roll)
	if not _expect(
		cold["ok"] and _draws == 0, "Completed boss world cold decode uses no initialization RNG"
	):
		return false
	var again: Dictionary = store.encode_progress(cold["progress"])
	return _expect(
		again["ok"] and again["record"] == encoded["record"],
		"Actual boss settlement world cold record preserves committed party/items/XP exactly"
	)


func _native_first_flag(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 88:
			actor["flags"] |= 4
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore m11 native B4-only boundary"):
		return false
	var event: Dictionary = _boss_events(opened["content"])["firstCombat"]
	var attacked: Dictionary = battle.attack_unit(0, 88)
	return _expect(
		(
			attacked["ok"]
			and attacked["storyBefore"].is_empty()
			and not battle.event_completed(event["id"])
		),
		"Native B4 already set suppresses583 without requiring its configured once marker"
	)


func _revival(opened: Dictionary) -> bool:
	if not _combat_setup(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 88:
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
			actor["inventory"].append(
				{"id": "m11:controlled:ring80", "templateId": 80, "durability": 1}
			)
	if not _expect(
		battle.restore_snapshot(state)["ok"],
		"Controlled80 is added to explicit boss boundary, never authored deployment"
	):
		return false
	var hit: Dictionary = battle.attack_unit(0, 88)
	return _expect(
		(
			hit["ok"]
			and hit.get("revivals", []).size() == 1
			and battle.unit(88)["visible"]
			and battle.unit(88)["hp"] == battle.unit(88)["maxHp"]
			and battle.outcome.is_empty()
			and not battle.event_completed("boss_death")
		),
		"Final-alive80 revival prevents boss death/victory/584"
	)


func _map_magic(opened: Dictionary) -> bool:
	for template: int in [49, 50, 51]:
		var ready: Dictionary = Flow.prepare_boundary(
			Matrix.CONTEXTS[0], 2, "map", {"snapshot": opened["battle"].snapshot()}
		)
		if not _expect(ready["ok"], "Prepare legal map attack boundary"):
			return false
		var battle: RefCounted = ready["battle"]
		var state: Dictionary = battle.snapshot()
		for actor: Dictionary in state["units"]:
			if actor["id"] == 8:
				for held: Dictionary in actor["inventory"]:
					if held["id"] == "m11:controlled:map":
						held["templateId"] = template
		if not _expect(
			battle.restore_snapshot(state)["ok"], "Select actual map spell%d" % template
		):
			return false
		var cast: Dictionary = battle.cast_map_attack(8, "m11:controlled:map", 88)
		if not _expect(
			(
				cast["ok"]
				and cast["kind"] == "map_attack"
				and not battle.event_completed("boss_first_combat")
				and not battle.event_completed("boss_death")
				and cast.get("storyBefore", []).is_empty()
				and cast.get("storyAfter", []).is_empty()
			),
			"Map49/50/51 exclude ordinary583/584 hooks"
		):
			return false
	return true


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	var initial: Array = opened["battle"].snapshot()["units"]
	var units: Array = initial.duplicate(true)
	for actor: Dictionary in units:
		if actor["id"] == 88:
			actor["hp"] = 0
			actor["visible"] = false
	if not _expect(
		rules.outcome(units).get("kind") == "victory",
		"Boss88 final retirement wins while ordinary enemies remain"
	):
		return false
	for actor: Dictionary in units:
		if actor["id"] == 0:
			actor["hp"] = 0
			actor["visible"] = false
	return _expect(
		rules.outcome(units).get("kind") == "defeat" and rules.outcome(units).get("unit") == 0,
		"Required0 retirement has priority over simultaneous boss retirement"
	)


func _occupied(opened: Dictionary) -> bool:
	for identity: int in [44, 56]:
		for blocked: bool in [false, true]:
			var state: Dictionary = opened["battle"].snapshot()
			var origin := Vector2i(
				opened["battle"].unit(identity)["x"], opened["battle"].unit(identity)["y"]
			)
			var cells: Array[Vector2i] = [
				origin,
				origin + Vector2i.LEFT,
				origin + Vector2i.UP,
				origin + Vector2i.DOWN,
				origin + Vector2i.RIGHT
			]
			var blockers: Array[int] = [18, 17, 19, 14, 12]
			var preserved: Dictionary = {}
			for actor: Dictionary in state["units"]:
				var index: int = blockers.find(int(actor["id"]))
				if index < 0 or (not blocked and index > 0):
					continue
				actor["x"] = cells[index].x
				actor["y"] = cells[index].y
				preserved[actor["id"]] = actor.duplicate(true)
			var ready: Dictionary = Session.new().open(
				Matrix.CHAPTER, "m11", {"snapshot": state}, _roll
			)
			if not _expect(ready["ok"], "Legal visible blockers can occupy hidden enemy cells"):
				return false
			var battle: RefCounted = ready["battle"]
			var original_hp: int = battle.unit(identity)["hp"]
			for turn: int in range(2):
				if not _expect(
					Rounds.advance(battle)["ok"],
					"Actual end phases deliver occupied reinforcement event"
				):
					return false
			var actor: Dictionary = battle.unit(identity)
			var actual := Vector2i(actor["x"], actor["y"])
			if not _expect(
				(
					actor["hp"] == original_hp
					and actor["visible"] == (not blocked)
					and actual == (origin if blocked else origin + Vector2i.LEFT)
				),
				"Occupied target uses left neighbor; full obstruction stays hidden and alive"
			):
				return false
			for blocker: int in preserved:
				var held: Dictionary = battle.unit(blocker)
				if not _expect(
					(
						held["x"] == preserved[blocker]["x"]
						and held["y"] == preserved[blocker]["y"]
						and held["hp"] == preserved[blocker]["hp"]
					),
					"Reinforcement never moves or damages occupants"
				):
					return false
			if not _roundtrip(opened["content"], battle, "occupied%d_%s" % [identity, blocked])["ok"]:
				return false
	return true


func _hero_revival(opened: Dictionary) -> bool:
	var ready: Dictionary = Flow.prepare_boundary(
		Matrix.CONTEXTS[0], 2, "required", {"snapshot": opened["battle"].snapshot()}
	)
	if not _expect(ready["ok"], "Prepare required0 lethal counter boundary"):
		return false
	var battle: RefCounted = ready["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["inventory"].append(
				{"id": "m11:controlled:hero80", "templateId": 80, "durability": 1}
			)
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Attach carried80 to controlled required member"
	):
		return false
	var attack: Dictionary = battle.attack_unit(0, 88)
	return _expect(
		(
			attack["ok"]
			and attack.get("revivals", []).size() == 1
			and battle.unit(0)["visible"]
			and battle.unit(0)["hp"] == battle.unit(0)["maxHp"]
			and battle.outcome.is_empty()
		),
		"Required0 actual80 revival precedes defeat evaluation"
	)


func _fork(opened: Dictionary) -> Dictionary:
	var before: int = _draws
	var battle := Battle.new(opened["content"], _roll, false)
	var restored: Dictionary = battle.restore_snapshot(opened["battle"].snapshot().duplicate(true))
	if not _expect(
		restored["ok"] and _draws == before,
		"Fork an independent deep m11 boundary without initialization RNG"
	):
		return {"ok": false}
	return {"ok": true, "content": opened["content"], "battle": battle}


func _boss_events(content: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for event: Dictionary in content["story"]["combatEvents"]:
		if event["unitId"] == 88:
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
	if not _expect(encoded["ok"], "Actual m11 stable boundary encodes: " + name):
		return {"ok": false}
	_draws = 0
	var restored: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == battle.snapshot(),
		(
			"m11 Store JSON cold restore keeps once/phase/units/items with zero initialization RNG: "
			+ name
		)
	):
		return {"ok": false}
	return restored


func _roll(limit: int) -> int:
	_draws += 1
	_draw_limits.append(limit)
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
