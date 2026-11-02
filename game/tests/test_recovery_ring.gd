extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
var _draws: Array[int] = []
var _observations: Array[Dictionary] = []
var _observed_battle: RefCounted


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not _initialization_and_absence(content):
		return
	if not _ring_round(content):
		return
	if not _canonical_json(content):
		return
	if not _outcome_priority(content):
		return
	print(
		"PASS recovery ring: reverse order, inclusive RNG, inventory presence, phases, JSON restore"
	)
	quit(0)


func _initialization_and_absence(content: Dictionary) -> bool:
	_draws.clear()
	var battle := Battle.new(content, _roll)
	var initial_draws: Array[int] = _draws.duplicate()
	var with_ring: Dictionary = content.duplicate(true)
	for spawn: Dictionary in with_ring["spawns"]:
		if not spawn["randomEquipment"]:
			spawn["itemChoices"] = [81]
			break
	_draws.clear()
	var initialized := Battle.new(with_ring, _roll)
	if not _expect(
		_draws == initial_draws and not initialized.snapshot()["units"].is_empty(),
		"Initializing a held recovery ring must not add a passive recovery draw"
	):
		return false
	_draws.clear()
	if not _advance_round(battle):
		return false
	return _expect(_draws.is_empty(), "A normal round without template81 must add no RNG draws")


func _ring_round(source: Dictionary) -> bool:
	var content: Dictionary = source.duplicate(true)
	content["story"]["outcomeRules"]["checks"] = []
	content["story"]["turnEvents"] = []
	# A different authored order must remain authoritative after restoring shuffled JSON units.
	content["unitOrder"].reverse()
	var battle := Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	var expected_order: Array[int] = []
	var before: Dictionary = {}
	var factions: Dictionary = {}
	var hidden_dead: int = -1
	for index: int in range(state["units"].size()):
		var actor: Dictionary = state["units"][index]
		var identity: int = int(actor["id"])
		actor["inventory"] = []
		actor["equippedInstanceId"] = ""
		actor["maxHp"] = 39
		actor["hp"] = 1
		if index == state["units"].size() - 1:
			before[identity] = actor.duplicate(true)
			continue
		match index % 7:
			2:
				actor["hp"] = 38
			3:
				actor["hp"] = 0
				actor["visible"] = false
				hidden_dead = identity
			4:
				actor["visible"] = false
			5:
				actor["hp"] = 39
			6:
				actor["maxHp"] = 1
				actor["hp"] = 0
				actor["visible"] = false
		if index >= state["units"].size() - 3:
			actor["maxHp"] = 39
			actor["hp"] = 1
		actor["inventory"] = [
			{"id": "ring_%d_a" % identity, "templateId": 81, "durability": 0},
			{"id": "ring_%d_b" % identity, "templateId": 81, "durability": 0}
		]
		expected_order.push_front(identity)
		factions[actor["faction"]] = true
		before[identity] = actor.duplicate(true)
	if not _expect(
		factions.has(0) and factions.has(1) and factions.has(2) and hidden_dead >= 0,
		"The fixture must include player, ally, enemy and hidden zero-HP ring holders"
	):
		return false
	content["story"]["turnEvents"] = [
		{"id": "ring_boundary", "afterEnemyPhaseOfRound": 1, "unitIds": [hidden_dead]}
	]
	battle.adopt_content(content)
	state["units"].reverse()
	_draws.clear()
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore the controlled ring fixture"):
		return false
	if not _expect(_draws.is_empty(), "Restoring held rings must not draw RNG"):
		return false
	_observed_battle = battle
	_observations.clear()
	if not _advance_round(battle):
		return false
	_observed_battle = null
	if not _expect(
		(
			_draws.size() == expected_order.size()
			and battle.unit(expected_order[0])["hp"] == 4
			and battle.unit(expected_order[1])["hp"] == 8
		),
		"Every holder draws once, including full HP, hidden, zero HP and zero integer recovery"
	):
		return false
	for index: int in range(expected_order.size()):
		var identity: int = expected_order[index]
		var previous: Dictionary = before[identity]
		var actor: Dictionary = battle.unit(identity)
		var percent: int = 10 + _value(index)
		var recovered: int = floori(float(previous["maxHp"] * percent) / 100.0)
		if not _expect(
			(
				_draws[index] == 11
				and actor["hp"] == mini(previous["maxHp"], previous["hp"] + recovered)
				and actor["visible"] == previous["visible"]
				and actor["inventory"] == previous["inventory"]
				and _observations[index] == {"phase": 0, "round": 2, "eventCompleted": true}
			),
			"Reverse unitOrder controls inclusive10..20 draws, truncation, cap and unchanged held items"
		):
			return false
	var no_ring: int = int(state["units"][0]["id"])
	if not _expect(
		(
			battle.unit(no_ring)["hp"] == before[no_ring]["hp"]
			and not battle.unit(hidden_dead)["visible"]
			and battle.unit(hidden_dead)["hp"] > 0
		),
		"Absence gives no recovery; the old-round arrival runs before hidden zero-HP recovery"
	):
		return false
	var saved: Dictionary = battle.snapshot()
	var requests: Array[int] = _draws.duplicate()
	var restored := Battle.new(content, _roll, false)
	var decoded: Dictionary = restored.restore_snapshot(JSON.parse_string(JSON.stringify(saved)))
	if not _expect(
		decoded["ok"] and restored.snapshot() == saved and _draws == requests,
		"JSON decode must preserve recovery exactly without initialization or passive redraws"
	):
		return false
	var advanced: Dictionary = battle.end_phase()
	if not _expect(
		advanced["ok"] and battle.phase != 0 and _draws == requests,
		"The recovered player phase cannot apply the ring again when advancing to another faction"
	):
		return false
	_draws.clear()
	if not _advance_round(restored):
		return false
	return _expect(
		_draws.size() == expected_order.size() and restored.round_number == 3,
		"A restored ring holder draws once again on the next new round"
	)


func _canonical_json(content: Dictionary) -> bool:
	var battle := Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["hp"] = 1
			actor["inventory"] = [{"id": "saved_ring", "templateId": 81, "durability": 0}]
			actor["equippedInstanceId"] = ""
	if not _expect(battle.restore_snapshot(state)["ok"], "Prepare a canonical held-ring record"):
		return false
	_draws.clear()
	if not _advance_round(battle):
		return false
	var store: RefCounted = load("res://persistence/battle_store.gd").new(content)
	var encoded: Dictionary = store.encode(battle)
	if not _expect(encoded["ok"] and _draws == [11], "Encode a recovered canonical ring holder"):
		return false
	var decoded: Dictionary = store.decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	return _expect(
		decoded["ok"] and decoded["battle"].snapshot() == battle.snapshot() and _draws == [11],
		"BattleStore JSON decode restores a real ring record without reinitialization or redrawing"
	)


func _outcome_priority(source: Dictionary) -> bool:
	var content: Dictionary = source.duplicate(true)
	content["story"]["outcomeRules"]["checks"] = []
	var battle := Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	var actor: Dictionary = state["units"][0]
	actor["inventory"] = [{"id": "fallen_ring", "templateId": 81, "durability": 0}]
	actor["equippedInstanceId"] = ""
	actor["hp"] = 0
	actor["visible"] = false
	if not _expect(battle.restore_snapshot(state)["ok"], "Prepare a fallen holder"):
		return false
	content["story"]["outcomeRules"]["checks"] = [
		{"condition": "requiredUnitFallen", "unitIds": [actor["id"]], "kind": "defeat"}
	]
	battle.adopt_content(content)
	_draws.clear()
	var ended: Dictionary = battle.end_phase()
	return _expect(
		not ended["ok"] and battle.outcome.get("kind") == "defeat" and _draws.is_empty(),
		"A terminal outcome must stop phase recovery before drawing or reviving a required holder"
	)


func _advance_round(battle: RefCounted) -> bool:
	var next_round: int = battle.round_number + 1
	for phase: int in range(3):
		while battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"], "Complete automatic wait"
			):
				return false
		var result: Dictionary = battle.end_phase()
		if not _expect(result["ok"], "Advance a completed phase: " + str(result)):
			return false
		if battle.phase == 0:
			return _expect(
				battle.round_number == next_round, "Recovery belongs to the newly incremented round"
			)
	return _expect(false, "Three faction phases must return to player control")


func _roll(limit: int) -> int:
	var index: int = _draws.size()
	_draws.append(limit)
	if _observed_battle != null:
		_observations.append(
			{
				"phase": _observed_battle.phase,
				"round": _observed_battle.round_number,
				"eventCompleted": _observed_battle.event_completed("ring_boundary")
			}
		)
	return mini(_value(index), limit - 1)


func _value(index: int) -> int:
	return 0 if index == 0 else (10 if index == 1 else (index * 3) % 11)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
