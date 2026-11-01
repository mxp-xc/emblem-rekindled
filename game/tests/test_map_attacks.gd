extends SceneTree

const MapAttacks = preload("res://gameplay/map_attack_rules.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const AI = preload("res://gameplay/tactical_ai.gd")

var _roll_count: int = 0
var _fixed_roll: int = 0
var _roll_values: Array[int] = []


func _initialize() -> void:
	if not _target_rules():
		return
	if (
		not _command_contract()
		or not _cost_and_rewards()
		or not _charms_and_mixed_hits()
		or not _restore_order()
		or not _ai_contract()
		or not _declared_drop_reference()
	):
		return
	print(
		"PASS map attacks: shapes, atomic commands, one cast cost/reward and stable restore order"
	)
	quit(0)


func _target_rules() -> bool:
	var actor: Dictionary = _unit(8, 0, 0, 2)
	var units: Array = [
		actor,
		_unit(90, 2, 2, 2),
		_unit(11, 2, 3, 3),
		_unit(4, 2, 2, 3),
		_unit(7, 1, 3, 2),
		_unit(5, 2, 1, 1, false),
		_unit(6, 2, 1, 2, true, 0)
	]
	var square: Dictionary = _item("square", 2)
	var cross: Dictionary = _item("cross", 1)
	var earthquake: Dictionary = _item("all_hostile", 3)
	if (
		MapAttacks.round_available(earthquake, 1)
		or MapAttacks.round_available(earthquake, 2)
		or not MapAttacks.round_available(earthquake, 3)
		or MapAttacks.round_available(square, 3)
		or not MapAttacks.round_available(square, 2)
		or not MapAttacks.round_available(cross, 1)
	):
		return _fail("Map attack periods differ from the original availability")
	if MapAttacks.primary_targets(actor, square, units, [0, 0, 1]) != [90, 4]:
		return _fail("Primary selection must apply hostile alliance, visibility and item range")
	if MapAttacks.affected_targets(actor, square, units, [0, 0, 1], 90) != [90, 11, 4]:
		return _fail("Square area must preserve original deployment order and primary alliance")
	if MapAttacks.affected_targets(actor, cross, units, [0, 0, 1], 90) != [90, 4]:
		return _fail("Cross area must exclude diagonals")
	if MapAttacks.affected_targets(actor, earthquake, units, [0, 0, 1]) != [90, 11, 4]:
		return _fail("All-hostile attack must ignore item range, allies, hidden and dead units")
	if not MapAttacks.affected_targets(actor, square, units, [0, 0, 1], 7).is_empty():
		return _fail("An allied primary is invalid even when in range")
	var cells: Dictionary = MapAttacks.affected_cells(square, {"x": 0, "y": 0}, Vector2i(4, 4))
	if cells.size() != 4 or not cells.has(Vector2i(1, 1)):
		return _fail("Area cells must clip at map boundaries")
	var invalid: Dictionary = square.duplicate(true)
	invalid["targetRule"]["shape"] = "arbitrary"
	if MapAttacks.valid_definition(invalid):
		return _fail("Unknown target shapes must be rejected")
	for period: int in [1, 2, 3]:
		var decoded: Dictionary = JSON.parse_string(JSON.stringify(_item("square", period)))
		if not MapAttacks.valid_definition(decoded):
			return _fail("JSON numeric decoding cannot invalidate an integral period or radius")
	invalid = square.duplicate(true)
	invalid["roundRule"]["period"] = 1.5
	if MapAttacks.valid_definition(invalid):
		return _fail("A fractional period must be rejected")
	for field: String in ["targetRule", "roundRule"]:
		invalid = square.duplicate(true)
		invalid[field] = "malformed"
		if MapAttacks.valid_definition(invalid):
			return _fail("Malformed map metadata must fail without runtime errors")
	return true


func _unit(id: int, faction: int, x: int, y: int, visible: bool = true, hp: int = 30) -> Dictionary:
	return {"id": id, "faction": faction, "x": x, "y": y, "visible": visible, "hp": hp}


func _item(shape: String, period: int) -> Dictionary:
	var all_hostile: bool = shape == "all_hostile"
	var rule: Dictionary = {
		"selection": "none" if all_hostile else "hostile_unit",
		"range": "map" if all_hostile else "item",
		"shape": shape
	}
	if not all_hostile:
		rule["radius"] = 1
	return {
		"actionMode": "map_attack",
		"targetRule": rule,
		"roundRule": {"period": period, "remainder": 0},
		"mapEffect": "fixture_effect",
		"minRange": 2,
		"maxRange": 3
	}


func _command_contract() -> bool:
	var fixture: Dictionary = _fixture(50)
	var battle: RefCounted = fixture["battle"]
	var before: Dictionary = battle.snapshot()
	_roll_count = 0
	var preview: Dictionary = battle.map_attack_preview(8, "cast", 35)
	if not preview["ok"] or preview["targetIds"] != [35, 33]:
		return _fail("Map preview must share area selection and original target order")
	if before != battle.snapshot() or _roll_count != 0:
		return _fail("Preview must not equip, mutate business state or draw random numbers")
	if battle.attack_unit(8, 35)["ok"] or battle.cast_map_attack(8, "cast", 8)["ok"]:
		return _fail("Wrong command mode and allied primary must be rejected")
	if battle.cast_map_attack(8, "not-owned", 35)["ok"]:
		return _fail("Cast must require the actual owned held item")
	if before != battle.snapshot() or _roll_count != 0:
		return _fail("Failed map commands must leave state and random source untouched")
	for weapon: int in [46, 49, 51]:
		fixture = _fixture(weapon)
		battle = fixture["battle"]
		before = battle.snapshot()
		_roll_count = 0
		if battle.cast_map_attack(8, "cast", -1 if weapon == 46 else 35)["ok"]:
			return _fail("An unavailable round must reject the cast")
		if battle.snapshot() != before or _roll_count != 0:
			return _fail("Round rejection must occur before any state or random change")
	fixture = _fixture(50, false)
	battle = fixture["battle"]
	before = battle.snapshot()
	_roll_count = 0
	if battle.cast_map_attack(8, "cast", 35)["ok"]:
		return _fail("A missing validated effect capability must reject the cast")
	if before != battle.snapshot() or _roll_count != 0:
		return _fail("Missing capability must fail before equipment, cost and random draws")
	for invalid_state: String in ["acted", "phase", "exhausted", "pending"]:
		fixture = _fixture(50)
		battle = fixture["battle"]
		var changed: Dictionary = battle.snapshot()
		if invalid_state == "acted":
			changed["units"][0]["action"] = 2
		elif invalid_state == "exhausted":
			changed["units"][0]["inventory"][0]["durability"] = 0
			changed["units"][0]["equippedInstanceId"] = ""
		if not battle.restore_snapshot(changed)["ok"]:
			return _fail("A stable command-rejection setup must restore")
		if invalid_state == "phase":
			battle.phase = 2
		elif invalid_state == "pending":
			if not battle.move_unit(9, Vector2i(0, 1))["ok"]:
				return _fail("A different actor must be able to create a pending move")
		before = battle.snapshot()
		_roll_count = 0
		if battle.cast_map_attack(8, "cast", 35)["ok"]:
			return _fail(
				"Invalid action, phase, exhausted item or another pending actor must reject"
			)
		if battle.snapshot() != before or _roll_count != 0:
			return _fail("All cast preconditions must reject before business changes or randomness")
	return true


func _cost_and_rewards() -> bool:
	for fixed: int in [0, 99]:
		_fixed_roll = fixed
		var fixture: Dictionary = _fixture(50)
		var battle: RefCounted = fixture["battle"]
		_roll_count = 0
		var result: Dictionary = battle.cast_map_attack(8, "cast", 35)
		if not result["ok"] or result["hits"].size() != 2 or _roll_count != 2:
			return _fail("Each area target must draw one independent hit roll without critical")
		var actor: Dictionary = battle.unit(8)
		if actor["proficiency"] != 11 or actor["inventory"][0]["durability"] != 1:
			return _fail("Even an all-miss cast must charge only one durability and proficiency")
		if result["rewards"]["experience"].get("amount") != 12:
			return _fail("An all-miss map cast still earns one normal hit experience reward")
		if not result["rewards"]["loot"].is_empty() or not result["storyBefore"].is_empty():
			return _fail("Map attacks must skip ordinary loot and first-combat dialogue")
		var settled: Dictionary = battle.snapshot()
		if battle.cast_map_attack(8, "cast", 35)["ok"] or battle.snapshot() != settled:
			return _fail("A repeated cast cannot consume costs or award rewards again")
	_fixed_roll = 0
	var fixture: Dictionary = _fixture(50)
	var battle: RefCounted = fixture["battle"]
	var state: Dictionary = battle.snapshot()
	state["units"][0]["inventory"][0]["durability"] = 1
	state["units"][0]["inventory"].append({"id": "spare", "templateId": 40, "durability": 4})
	state["units"][1]["hp"] = 1
	state["units"][1]["dropTemplateId"] = 40
	state["units"][1]["inventory"].append({"id": "drop", "templateId": 40, "durability": 5})
	state["units"][1]["inventory"].append({"id": "shield", "templateId": 67, "durability": 1})
	state["units"][3]["attributes"]["magic"] = 25
	if not battle.restore_snapshot(state)["ok"]:
		return _fail("Controlled map kill setup must restore")
	_roll_count = 0
	var result: Dictionary = battle.cast_map_attack(8, "cast", 35)
	if not result["ok"] or result["hits"][1]["weapon"] != 50:
		return _fail("Last durability and auto-equipment cannot change remaining map hits")
	if not result["rewards"]["loot"].is_empty() or battle.unit(8)["inventory"].size() != 1:
		return _fail("A map kill must never transfer an ordinary marked drop")
	var combat: RefCounted = Combat.new(
		fixture["content"]["rules"], fixture["content"]["map"]["terrain"]
	)
	var last_xp: int = combat.experience_gain(battle.unit(8), battle.unit(33), true, true, false)
	var first_xp: int = combat.experience_gain(battle.unit(8), battle.unit(35), true, true, false)
	if last_xp == first_xp or result["rewards"]["experience"].get("amount") != last_xp:
		return _fail("One kill anywhere must award XP using the cleaned-up original last target")
	if (
		not result["storyAfter"].is_empty()
		or battle.event_completed("first")
		or battle.event_completed("death")
	):
		return _fail("Map attacks must not consume ordinary first-combat or death-dialogue markers")
	if battle.unit(35)["inventory"].size() != 1:
		return _fail("A hit must consume the target's last magic-defense charm")
	return true


func _charms_and_mixed_hits() -> bool:
	for fixed: int in [0, 99]:
		_fixed_roll = fixed
		var fixture: Dictionary = _fixture(50)
		var battle: RefCounted = fixture["battle"]
		var state: Dictionary = battle.snapshot()
		state["units"][0]["attributes"]["luck"] = 30
		state["units"][0]["inventory"].append({"id": "luck", "templateId": 87, "durability": 1})
		state["units"][1]["inventory"].append({"id": "shield", "templateId": 67, "durability": 1})
		if not battle.restore_snapshot(state)["ok"]:
			return _fail("Charm and luck setup must restore")
		_roll_count = 0
		var result: Dictionary = battle.cast_map_attack(8, "cast", 35)
		if not result["ok"] or _roll_count != 3:
			return _fail("Luck protection must add exactly one roll after all target hit rolls")
		var actor: Dictionary = battle.unit(8)
		if (
			actor["proficiency"] != 11
			or actor["inventory"][0]["durability"] != (2 if fixed == 0 else 1)
		):
			return _fail("Luck protects only durability, never the once-per-cast proficiency")
		if actor["inventory"][1]["durability"] != 1:
			return _fail("The luck charm must not be consumed")
		if battle.unit(35)["inventory"].size() != (0 if fixed == 0 else 1):
			return _fail("Magic-defense charm consumption must depend on this target hitting")
	_fixed_roll = 0
	var fixture: Dictionary = _fixture(50)
	var battle: RefCounted = fixture["battle"]
	_roll_values.assign([0, 99])
	_roll_count = 0
	var result: Dictionary = battle.cast_map_attack(8, "cast", 35)
	if not result["ok"] or not result["hits"][0]["hit"] or result["hits"][1]["hit"]:
		return _fail("Targets must receive independent hit results within the same cast")
	return true


func _restore_order() -> bool:
	var fixture: Dictionary = _fixture(46)
	var battle: RefCounted = fixture["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 3
	state["units"].reverse()
	var content: Dictionary = fixture["content"].duplicate(true)
	content["units"].reverse()
	content["unitOrder"] = [8, 33, 35, 57, 9]
	battle.adopt_content(content)
	_roll_count = 0
	if not battle.restore_snapshot(state)["ok"] or _roll_count != 0:
		return _fail("Restoring a reordered snapshot must not draw random numbers")
	var preview: Dictionary = battle.map_attack_preview(8, "cast")
	if not preview["ok"] or preview["targetIds"] != [33, 35, 57]:
		return _fail(
			"Raw definitions, saved array and IDs cannot replace authoritative native unitOrder"
		)
	_roll_values.assign([0, 99, 0])
	var result: Dictionary = battle.cast_map_attack(8, "cast")
	if (
		not result["ok"]
		or result["hits"][0]["target"] != 33
		or not result["hits"][0]["hit"]
		or result["hits"][1]["target"] != 35
		or result["hits"][1]["hit"]
		or result["hits"][2]["target"] != 57
	):
		return _fail("Restore reordering cannot redistribute random rolls among targets")
	return true


func _ai_contract() -> bool:
	for weapon: int in [46, 49, 50, 51]:
		var fixture: Dictionary = _fixture(weapon)
		var units: Array = fixture["battle"].snapshot()["units"]
		var actor: Dictionary = units[0]
		actor["policy"] = 4
		var ai: RefCounted = AI.new(fixture["content"])
		var round_number: int = 3 if weapon == 46 else 2
		var plan: Dictionary = ai.plan(actor, units, {}, 0, round_number)
		var expected: int = -1 if weapon == 46 else (33 if weapon == 50 else 35)
		if (
			plan["actionMode"] != "map_attack"
			or plan["mapItem"] != "cast"
			or plan["mapPrimary"] != expected
			or plan["attackTarget"] != -1
			or plan["cell"] != Vector2i(actor["x"], actor["y"])
		):
			return _fail(
				"AI map command must preserve original primary scoring plus 150 per area target"
			)
		if weapon != 50:
			plan = ai.plan(actor, units, {}, 0, 1)
			if plan["actionMode"] == "map_attack":
				return _fail("AI and player must share the same periodic availability")
	return true


func _declared_drop_reference() -> bool:
	var fixture: Dictionary = _fixture(50)
	var content: Dictionary = fixture["content"].duplicate(true)
	var declared: Dictionary = content["rules"]["itemTemplates"][1].duplicate(true)
	declared["id"] = 300
	content["rules"]["itemTemplates"].append(declared)
	var state: Dictionary = fixture["battle"].snapshot()
	state["units"][1]["dropTemplateId"] = 300
	state = JSON.parse_string(JSON.stringify(state))
	var battle: RefCounted = Battle.new(content, _roll, false)
	_roll_count = 0
	if not battle.restore_snapshot(state)["ok"] or battle.unit(35)["dropTemplateId"] != 300:
		return _fail("A JSON drop reference above the native byte range is valid when declared")
	var before: Dictionary = battle.snapshot()
	state["units"][1]["dropTemplateId"] = 301
	if battle.restore_snapshot(state)["ok"] or battle.snapshot() != before or _roll_count != 0:
		return _fail("An undeclared drop reference must reject atomically without random draws")
	return true


func _fixture(weapon: int, effects: bool = true) -> Dictionary:
	_roll_values.clear()
	var templates: Array = []
	for id: int in [0, 40, 46, 49, 50, 51, 67, 87]:
		var definition: Dictionary = {
			"id": id,
			"damageKind": "magic" if id in [40, 46, 49, 50, 51] else "none",
			"categoryMask": 16 if id in [40, 46, 49, 50, 51] else 0,
			"power": 9,
			"hit": 55,
			"critical": 0,
			"weight": 0,
			"minRange": 2,
			"maxRange": 3,
			"defaultDurability": 12,
			"doubleStrike": false,
			"drainsHp": false,
			"ignoresDefense": false,
			"effectiveGroups": []
		}
		if id in [46, 49, 50, 51]:
			definition.merge(
				_item(
					"all_hostile" if id == 46 else ("cross" if id == 50 else "square"),
					3 if id == 46 else (1 if id == 50 else 2)
				),
				true
			)
		elif id == 40:
			definition["actionMode"] = "battle_clip"
		if id == 0:
			definition["minRange"] = 0
			definition["maxRange"] = 0
		templates.append(definition)
	var caps: Dictionary = {"maxHp": 100, "move": 10}
	var growth: Dictionary = {"id": 0, "maxHp": 0, "move": 0}
	for stat: String in ["strength", "skill", "speed", "defense", "magic", "luck"]:
		caps[stat] = 30
		growth[stat] = 0
	var terrain: Array = []
	var costs: Array = []
	for y: int in range(5):
		terrain.append([0, 0, 0, 0, 0])
		costs.append([1, 1, 1, 1, 1])
	var units: Array = []
	for data: Array in [[8, 0, 0, 2], [35, 2, 2, 2], [57, 2, 3, 3], [33, 2, 2, 3], [9, 0, 0, 0]]:
		var current: Dictionary = _unit(data[0], data[1], data[2], data[3], true, 80)
		current.merge(
			{
				"sourceId": data[0],
				"classId": 1,
				"classGroup": 0,
				"flags": 0,
				"equipMask": 16,
				"dropTemplateId": 0,
				"policy": 0,
				"growthTemplateId": 0,
				"formal": data[1] == 0,
				"level": 1,
				"maxHp": 80,
				"move": 2,
				"experience": 0,
				"proficiency": 10,
				"action": 0,
				"inventory": [],
				"equippedInstanceId": "",
				"attributes":
				{"strength": 3, "skill": 0, "speed": 5, "defense": 3, "magic": 10, "luck": 0}
			}
		)
		units.append(current)
	units[0]["inventory"] = [{"id": "cast", "templateId": weapon, "durability": 2}]
	units[0]["equippedInstanceId"] = "cast"
	var content: Dictionary = {
		"entry": {"id": "fixture", "battleId": "m0", "initialParty": [8, 9], "recruitByNode": {}},
		"unitOrder": [8, 35, 57, 33, 9],
		"units": units,
		"spawns": [],
		"map": {"width": 5, "height": 5, "terrain": terrain, "movementCosts": {"0": costs}},
		"rules":
		{
			"itemTemplates": templates,
			"initialGold": 0,
			"alliances": [0, 0, 1],
			"terrainDefense": [0],
			"terrainEvasion": [0],
			"aiClassOrder": [0],
			"baseMovementCosts": [1],
			"statCaps": caps,
			"growthRates": [growth],
			"jobTemplates": [{"id": 1, "classGroup": 0, "equipMask": 16}]
		},
		"story":
		{
			"sequences": {"opening": [], "victory": [{"goldReward": 0}]},
			"worldNode": 0,
			"world": {"routes": [[0, 1]]},
			"routeChoices": [],
			"outcomeRules": {"checks": []},
			"turnEvents": [],
			"aiChanges": [],
			"combatEvents":
			[
				{"id": "first", "unitId": 35, "trigger": "firstCombat", "sequence": "first"},
				{"id": "death", "unitId": 35, "trigger": "unitDeath", "beforeRetirement": "death"}
			]
		},
		"mapEffects": {"fixture_effect": {"kind": "fixture"}} if effects else {}
	}
	var battle: RefCounted = Battle.new(content, _roll, false)
	var state: Dictionary = battle.snapshot()
	state["units"] = units.duplicate(true)
	if not battle.restore_snapshot(state)["ok"]:
		_fail("Independent map-attack fixture must restore")
	return {"content": content, "battle": battle}


func _roll(limit: int) -> int:
	_roll_count += 1
	if not _roll_values.is_empty():
		return int(_roll_values.pop_front()) % limit
	return _fixed_roll % limit


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
