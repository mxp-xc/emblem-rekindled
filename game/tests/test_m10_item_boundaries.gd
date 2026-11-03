extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
const Session = preload("res://app/chapter_session.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _content: Dictionary
var _m1_progress: Dictionary
var _m1_content: Dictionary
var _draws: Array[int] = []
var _high: bool = false


func _initialize() -> void:
	_content = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	_content["story"]["outcomeRules"]["checks"] = []
	if not _prepare_m1():
		return
	if not _gold_and_fruit_caps() or not _automatic_and_soft_caps() or not _missing_presentation():
		return
	if (
		not _map_revival_and_second_death()
		or not _staff_boundaries()
		or not _required_commander_revival()
		or not _revival_phase_matrix()
		or not _repair_kinds()
	):
		return
	print("PASS m10 boundaries: caps, auto promotion, map revival and staff preservation")
	quit(0)


func _fresh(source: Dictionary = {}) -> RefCounted:
	return Battle.new(_content if source.is_empty() else source, _roll)


func _prepare_m1() -> bool:
	var first: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, _roll)
	if not _expect(first["ok"], "Open real m0 source for m1 promotion tests"):
		return false
	first["battle"].win_with_assistance()
	var completed: Dictionary = first["battle"].complete_victory(0)
	if not _expect(completed["ok"], "Complete real m0 route0 for legal m1 world entry"):
		return false
	_m1_progress = completed["progress"]
	return true


func _fresh_m1() -> RefCounted:
	var opened: Dictionary = Session.new().open(CHAPTER, "m1", {"progress": _m1_progress}, _roll)
	if not _expect(opened["ok"], "Open m1 with real completed m0 progress"):
		return null
	_m1_content = opened["content"]
	# This controlled ability boundary suppresses map victory, retaining all real
	# deployment identities, inherited units and verified promotion profiles.
	_m1_content["story"]["outcomeRules"]["checks"] = []
	opened["battle"].adopt_content(_m1_content)
	var advanced: Dictionary = Rounds.advance(opened["battle"])
	if not _expect(
		(
			advanced["ok"]
			and opened["battle"].round_number == 2
			and opened["battle"].phase == 0
			and opened["battle"].event_completed("allied_arrival")
			and opened["battle"].unit(0)["visible"]
			and opened["battle"].unit(9)["visible"]
		),
		"Real first enemy phase commits allied arrival before m1 ability fixtures"
	):
		return null
	return opened["battle"]


func _restore(battle: RefCounted, state: Dictionary) -> bool:
	var result: Dictionary = battle.restore_snapshot(state)
	_draws.clear()
	return _expect(result["ok"], "Controlled valid state: " + str(result))


func _add(actor: Dictionary, template: int, id: String, durability: int = 1) -> void:
	actor["inventory"].append({"id": id, "templateId": template, "durability": durability})


func _gold_and_fruit_caps() -> bool:
	var battle: RefCounted = _fresh()
	var state: Dictionary = battle.snapshot()
	state["gold"] = Battle.MAX_GOLD - 9
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			_add(actor, 63, "gold")
	if not _restore(battle, state):
		return false
	var result: Dictionary = battle.use_item(0, "gold")
	if not _expect(
		(
			result["ok"]
			and result["rolledGold"] == 1000
			and result["creditedGold"] == 9
			and battle.gold == Battle.MAX_GOLD
			and _draws == [2001]
		),
		"Gold respects modern global limit after its one roll"
	):
		return false
	battle = _fresh_m1()
	if battle == null:
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["classId"] = 1
			actor["equipMask"] = 5
			actor["level"] = 10
			actor["maxHp"] = 64
			actor["hp"] = 64
			actor["attributes"]["strength"] = 32
			_add(actor, 74, "body")
	if not _restore(battle, state):
		return false
	var original_before: Dictionary = battle.unit(0)
	result = battle.use_item(0, "body")
	if not _expect(
		(
			result["ok"]
			and battle.unit(0)["maxHp"] == 60
			and battle.unit(0)["hp"] == 60
			and _draws.is_empty()
		),
		"Body fruit lowers over-cap maxHP and clamps current HP to modern invariant"
	):
		print(
			"M10_BODY_FRUIT_DIAGNOSTIC ",
			{
				"result": result,
				"unit0": battle.unit(0),
				"draws": _draws,
				"originalBefore": original_before,
				"phase": battle.phase,
				"outcome": battle.outcome
			}
		)
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
			_add(actor, 68, "strength")
	if not _restore(battle, state):
		return false
	result = battle.use_item(0, "strength")
	return _expect(
		(
			result["ok"]
			and battle.unit(0)["attributes"]["strength"] == 30
			and result["consumed"]
			and _draws.is_empty()
		),
		"Over-cap fruit clamps back to its fixed cap and still consumes"
	)


func _automatic_and_soft_caps() -> bool:
	var battle: RefCounted = _fresh_m1()
	if battle == null:
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		actor["visible"] = actor["id"] in [0, 9]
		if actor["id"] == 0:
			actor["level"] = 9
			actor["experience"] = 99
			actor["maxHp"] = 60
			actor["hp"] = 55
			actor["attributes"]["strength"] = 30
			_add(actor, 76, "emblem")
	if not _restore(battle, state):
		return false
	battle.share_experience = true
	var caster: Dictionary = battle.unit(9)
	var result: Dictionary = battle.heal_unit(9, 0, caster["inventory"][0]["id"])
	if not _expect(
		(
			result["ok"]
			and battle.unit(0)["classId"] == 1
			and battle.unit(0)["level"] == 10
			and battle.unit(0)["experience"] == 7
			and battle.unit(0)["maxHp"] == 64
			and battle.unit(0)["attributes"]["strength"] == 32
			and result["rewards"]["experience"]["shared"][0].has("promotion")
			and _draws.size() == 9
		),
		"Shared staff XP performs ordinary eight-roll growth then automatic zero-roll promotion"
	):
		print(
			"M10_SHARED_PROMOTION_DIAGNOSTIC ",
			{
				"result": result,
				"casterBefore": caster,
				"unit0": battle.unit(0),
				"unit9": battle.unit(9),
				"draws": _draws,
				"promotionError": _m1_content.get("promotionErrors", {}).get(0, "")
			}
		)
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [0, 9]:
			actor["action"] = 0
		if actor["id"] == 0:
			actor["experience"] = 99
	for high: bool in [false, true]:
		if not _restore(battle, state):
			return false
		_high = high
		caster = battle.unit(9)
		result = battle.heal_unit(9, 0, caster["inventory"][0]["id"])
		var growth: Dictionary = result["rewards"]["experience"]["shared"][0]["growth"]
		var expected: Dictionary = {
			"strength": 0,
			"skill": 0 if high else 1,
			"speed": 0 if high else 1,
			"defense": 0 if high else 1,
			"magic": 0 if high else 1,
			"luck": 0 if high else 1,
			"maxHp": 0,
			"move": 0
		}
		if not _expect(
			(
				result["ok"]
				and battle.unit(0)["level"] == 11
				and battle.unit(0)["maxHp"] == 64
				and battle.unit(0)["hp"] == 64
				and battle.unit(0)["attributes"]["strength"] == 32
				and growth == expected
				and _draws.size() == 9
				and _draws.all(func(limit: int) -> bool: return limit == 100)
			),
			"Raw0/99 ordinary growth retains32/64/64 with healing1 plus exactly8 growth draws"
		):
			return false
	_high = false
	return true


func _missing_presentation() -> bool:
	var content: Dictionary = _content.duplicate(true)
	content["promotionTargets"] = {}
	content["promotionErrors"] = {0: "controlled missing profile"}
	var battle: RefCounted = _fresh(content)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["level"] = 10
			_add(actor, 76, "emblem")
	if not _restore(battle, state):
		return false
	var before: Dictionary = battle.snapshot()
	var result: Dictionary = battle.use_item(0, "emblem")
	if not _expect(
		not result["ok"] and battle.snapshot() == before and _draws.is_empty(),
		"Missing manual promotion family rejects before consuming"
	):
		return false
	var caster: Dictionary = battle.unit(9)
	result = battle.heal_unit(9, 0, caster["inventory"][0]["id"])
	return _expect(
		not result["ok"] and battle.snapshot() == before and _draws.is_empty(),
		"Potential shared promotion family rejects before healing, staff charge, growth or RNG"
	)


func _map_revival_and_second_death() -> bool:
	var battle: RefCounted = _fresh_m1()
	if battle == null:
		return false
	var state: Dictionary = battle.snapshot()
	var caster: Dictionary = battle.unit(9)
	for actor: Dictionary in state["units"]:
		actor["visible"] = actor["id"] in [9, 65]
		if actor["id"] == 9:
			actor["classId"] = 5
			actor["classGroup"] = 1
			actor["equipMask"] = 48
			actor["level"] = 10
			actor["inventory"] = [{"id": "wind", "templateId": 50, "durability": 10}]
			actor["equippedInstanceId"] = "wind"
			actor["attributes"]["magic"] = 30
		if actor["id"] == 65:
			actor["hp"] = 1
			actor["x"] = caster["x"]
			actor["y"] = int(caster["y"]) + 2
			actor["dropTemplateId"] = 63
			_add(actor, 63, "drop")
			_add(actor, 80, "ring")
	if not _restore(battle, state):
		return false
	var result: Dictionary = battle.cast_map_attack(9, "wind", 65)
	if not _expect(
		(
			result["ok"]
			and result["revivals"].size() == 1
			and result["anyKill"]
			and result["rewards"]["loot"].is_empty()
			and not result["rewards"]["experience"].is_empty()
			and battle.unit(65)["inventory"].any(
				func(held: Dictionary) -> bool: return held["id"] == "drop"
			)
			and battle.unit(65)["hp"] > 0
		),
		"Map knockdown retains anyKill XP and original no-drop rule before revival"
	):
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["action"] = 0
		if actor["id"] == 65:
			actor["hp"] = 1
	if not _restore(battle, state):
		return false
	result = battle.cast_map_attack(9, "wind", 65)
	return _expect(
		(
			result["ok"]
			and result["revivals"].is_empty()
			and not battle.unit(65)["visible"]
			and battle.unit(65)["hp"] == 0
		),
		"Second map knockdown without ring performs ordinary retirement"
	)


func _staff_boundaries() -> bool:
	var battle: RefCounted = _fresh()
	var state: Dictionary = battle.snapshot()
	var caster: Dictionary = battle.unit(9)
	var target: Dictionary = battle.unit(0)
	var occupied: Array[Vector2i] = [
		Vector2i(caster["x"], caster["y"]), Vector2i(target["x"], target["y"])
	]
	var land := Vector2i(-1, -1)
	var blocked := Vector2i(-1, -1)
	for y: int in range(int(_content["map"]["height"])):
		for x: int in range(int(_content["map"]["width"])):
			var cell := Vector2i(x, y)
			var cost: int = int(
				_content["rules"]["baseMovementCosts"][int(_content["map"]["terrain"][y][x])]
			)
			if cost == 100 and blocked.x < 0:
				blocked = cell
			if cost < 100 and land.x < 0 and cell not in occupied:
				land = cell
	if not _expect(
		land.x >= 0 and blocked.x >= 0, "Original map supplies passable and baseCost100 terrain"
	):
		return false
	for actor: Dictionary in state["units"]:
		actor["visible"] = actor["id"] in [0, 9]
		if actor["id"] == 9:
			_add(actor, 58, "teleport", 15)
		if actor["id"] == 0:
			actor["action"] = 2
		if actor["id"] == 59:
			actor["x"] = land.x
			actor["y"] = land.y
	if not _restore(battle, state):
		return false
	var field: Dictionary = battle.teleport_field(9, 0, "teleport")
	if not _expect(
		field.has(land) and not field.has(blocked),
		"Hidden actor does not block landing; original baseCost100 terrain does"
	):
		return false
	# This is a transient resolution seam, not a legal persisted HP0-visible record.
	# It verifies original occupancy while a casualty has not yet retired.
	battle._units[59]["visible"] = true
	battle._units[59]["hp"] = 0
	field = battle.teleport_field(9, 0, "teleport")
	if not _expect(not field.has(land), "Visible HP0 casualty still blocks teleport destination"):
		return false
	battle._units[59]["visible"] = false
	var before: Dictionary = battle.unit(0)
	var result: Dictionary = battle.teleport_unit(9, 0, "teleport", land)
	return _expect(
		(
			result["ok"]
			and battle.unit(0)["action"] == 2
			and battle.unit(0)["hp"] == before["hp"]
			and battle.unit(0)["inventory"] == before["inventory"]
			and _draws.is_empty()
		),
		"Teleport never refreshes an already acted target"
	)


func _required_commander_revival() -> bool:
	var content: Dictionary = _content.duplicate(true)
	content["story"]["outcomeRules"]["checks"] = [
		{"condition": "requiredUnitFallen", "unitIds": [0], "kind": "defeat"},
		{"condition": "allEnemiesDefeated", "faction": 2, "kind": "victory"}
	]
	var battle: RefCounted = _fresh(content)
	var state: Dictionary = battle.snapshot()
	var attacker: Dictionary = battle.unit(0)
	state["commander"] = 0
	for actor: Dictionary in state["units"]:
		actor["visible"] = actor["id"] in [0, 59]
		if actor["id"] == 0:
			actor["hp"] = 1
			actor["attributes"]["strength"] = 0
			actor["attributes"]["defense"] = 0
			actor["attributes"]["speed"] = 0
			_add(actor, 80, "playerRing")
		if actor["id"] == 59:
			actor["hp"] = actor["maxHp"]
			actor["x"] = attacker["x"]
			actor["y"] = int(attacker["y"]) + 1
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
			actor["attributes"]["defense"] = 30
			actor["attributes"]["speed"] = 30
	if not _restore(battle, state):
		return false
	var result: Dictionary = battle.attack_unit(0, 59)
	var revival: Dictionary = (
		result["revivals"][0] if result.get("revivals", []).size() == 1 else {}
	)
	return _expect(
		(
			result["ok"]
			and revival.get("unit") == 0
			and revival["expiredItem"]["templateId"] == 80
			and revival["expiredItem"]["id"] == "playerRing"
			and battle.unit(0)["hp"] == battle.unit(0)["maxHp"]
			and battle.unit(0)["visible"]
			and battle.unit(0)["action"] == 2
			and battle.commander_id == 0
			and battle.outcome.is_empty()
			and result["retirements"].is_empty()
		),
		"Real counterattack revives required commander0, preserves command and emits player ring expiry"
	)


func _revival_phase_matrix() -> bool:
	# Finite internal post-resolution contract matrix, not six full combat runs.
	# All inputs first restore as ordinary valid living records; only then HP0
	# represents the same raw post-strike boundary consumed by _finish_defeats.
	for sample: Array in [[0, 0], [10, 1], [59, 2]]:
		for own_phase: bool in [false, true]:
			var battle: RefCounted = _fresh()
			var state: Dictionary = battle.snapshot()
			for actor: Dictionary in state["units"]:
				actor["visible"] = actor["id"] == sample[0]
				if actor["id"] == sample[0]:
					actor["action"] = 0
					actor["hp"] = 1
					_add(actor, 80, "phaseRing")
			if not _restore(battle, state):
				return false
			battle.phase = sample[1] if own_phase else (int(sample[1]) + 1) % 3
			battle._units[int(sample[0])]["hp"] = 0
			var resolution: Dictionary = battle._finish_defeats([int(sample[0])])
			var revivals: Array[Dictionary] = resolution["revivals"]
			var actor: Dictionary = battle.unit(int(sample[0]))
			if not _expect(
				(
					revivals.size() == 1
					and actor["visible"]
					and actor["hp"] == actor["maxHp"]
					and actor["action"] == (2 if own_phase else 0)
					and (int(actor["flags"]) & 64) != 0
					and revivals[0]["expiredItem"].is_empty() == (sample[1] != 0)
					and not actor["inventory"].any(
						func(held: Dictionary) -> bool: return held["id"] == "phaseRing"
					)
					and _draws.is_empty()
				),
				"Player/ally/enemy same-phase ends action; other phase retains it, with player-only expiry"
			):
				return false
	return true


func _repair_kinds() -> bool:
	for sample: Array in [[65, 1, 4], [65, 4, 4], [58, 5, 15]]:
		var battle: RefCounted = _fresh()
		var state: Dictionary = battle.snapshot()
		for actor: Dictionary in state["units"]:
			actor["visible"] = actor["id"] in [0, 9]
			if actor["id"] == 9:
				_add(actor, 57, "repair", 4)
			if actor["id"] == 0:
				_add(actor, sample[0], "repaired", sample[1])
		if not _restore(battle, state):
			return false
		var before: Dictionary = battle.unit(0)
		var options: Array[Dictionary] = battle.repair_options(9, 0, "repair")
		if not _expect(
			options.any(func(held: Dictionary) -> bool: return held["id"] == "repaired"),
			"Repair list includes passive shield and target-ineligible staff, including full durability"
		):
			return false
		var result: Dictionary = battle.repair_unit(9, 0, "repair", "repaired")
		var expected: Dictionary = before.duplicate(true)
		for held: Dictionary in expected["inventory"]:
			if held["id"] == "repaired":
				held["durability"] = sample[2]
		if not _expect(
			(
				result["ok"]
				and battle.unit(0) == expected
				and result["repairedItem"]["id"] == "repaired"
				and result["durabilityAfter"] == sample[2]
				and battle.unit(9)["action"] == 2
				and _draws.is_empty()
			),
			"Repair retains item identity/order, equipment and target state except chosen durability"
		):
			return false
	return true


func _roll(limit: int) -> int:
	_draws.append(limit)
	return limit - 1 if _high else 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
