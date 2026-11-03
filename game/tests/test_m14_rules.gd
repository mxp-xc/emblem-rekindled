extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var draws: int = 0


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
	content["map"]["locations"] = [
		{
			"id": "wait_0",
			"sourceIndex": 0,
			"kind": "waitPickup",
			"position": [actor["x"], actor["y"]],
			"tileId": 39,
			"reward": {"kind": "item", "templateId": 26}
		}
	]
	for sizes: Array in [[5, 0], [6, 39], [6, 40]]:
		var battle: RefCounted = _fixture(content, sizes[0], sizes[1])
		var before: Dictionary = battle.snapshot()
		if not _expect(
			"visit_location" not in battle.actions_for(0),
			"Fixed wait pickup offers no visit action"
		):
			return
		if not _expect(
			(
				battle.move_unit(0, Vector2i(actor["x"], actor["y"]))["ok"]
				and battle.cancel_move()["ok"]
				and battle.snapshot() == before
			),
			"Cancelling movement does not claim"
		):
			return
		if not _expect(
			battle.move_unit(0, Vector2i(actor["x"], actor["y"]))["ok"],
			"Wait can commit a pending movement"
		):
			return
		var result: Dictionary = battle.wait_unit(0)
		var claimed: bool = sizes != [6, 40]
		if not _expect(
			(
				result["ok"]
				and result["kind"] == "wait"
				and result["location"]["claimed"] == claimed
				and battle.unit(0)["action"] == 2
				and battle.snapshot()["pending_move"].is_empty()
				and draws == 0
			),
			"Wait ends action; capacity determines claim without a draw"
		):
			return
		if not _expect(
			(
				battle.event_completed("location:wait_0") == claimed
				and battle.map_state()["map"]["tiles"] == content["map"]["tiles"]
			),
			"Only claimed fixed locations are consumed and tiles remain unchanged"
		):
			return
		if not _expect(
			not battle.wait_unit(0)["ok"] and draws == 0, "Repeated input cannot claim twice"
		):
			return
		if claimed:
			var item: Dictionary = result["location"]["rewards"]["loot"][0]["item"]
			var expected_durability: int = 0
			for template: Dictionary in content["rules"]["itemTemplates"]:
				if template["id"] == 26:
					expected_durability = template["defaultDurability"]
			if not _expect(
				(
					item["id"].ends_with(":location:wait_0")
					and item["templateId"] == 26
					and item["durability"] == expected_durability
				),
				"Pickup has stable location identity and default durability"
			):
				return
		if not claimed:
			var retry: Dictionary = battle.snapshot()
			retry["warehouse"].pop_back()
			for unit: Dictionary in retry["units"]:
				if unit["id"] == 0:
					unit["action"] = 0
			if not _expect(
				battle.restore_snapshot(retry)["ok"] and battle.wait_unit(0)["location"]["claimed"],
				"After capacity is freed a later legal action can retry"
			):
				return
	var moving_content: Dictionary = content.duplicate(true)
	var scout: RefCounted = _fixture(moving_content, 5, 0)
	var destination := Vector2i(actor["x"], actor["y"])
	for cell: Vector2i in scout.movement_field(0):
		if cell != destination and scout.preview_move(0, cell)["ok"]:
			destination = cell
			break
	if not _expect(
		destination != Vector2i(actor["x"], actor["y"]), "Fixture has a reachable different cell"
	):
		return
	moving_content["map"]["locations"][0]["position"] = [destination.x, destination.y]
	var moved: RefCounted = _fixture(moving_content, 5, 0)
	if not _expect(
		(
			moved.move_unit(0, destination)["ok"]
			and not moved.event_completed("location:wait_0")
			and moved.wait_unit(0)["location"]["claimed"]
		),
		"Moving to a different cell claims only on wait"
	):
		return
	var phase_wait: RefCounted = _fixture(content, 5, 0)
	if not _expect(
		(
			phase_wait.end_phase()["ok"]
			and not phase_wait.event_completed("location:wait_0")
			and draws == 0
		),
		"Ending the phase does not claim an unattended pickup"
	):
		return
	if (
		not _elements()
		or not _map_elements()
		or not _reordered_elements()
		or not _single_map_element()
	):
		return
	print("PASS m14 rules: wait pickup, ordinary and map element retirement and experience")
	quit(0)


func _fixture(content: Dictionary, bag: int, warehouse: int) -> RefCounted:
	var battle: RefCounted = Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	for unit: Dictionary in state["units"]:
		if unit["id"] == 0:
			unit["inventory"] = []
			unit["equippedInstanceId"] = ""
			for index: int in range(bag):
				unit["inventory"].append({"id": "bag_%d" % index, "templateId": 2, "durability": 1})
	state["warehouse"] = []
	for index: int in range(warehouse):
		state["warehouse"].append({"id": "warehouse_%d" % index, "templateId": 2, "durability": 1})
	if not battle.restore_snapshot(state)["ok"]:
		push_error("Wait pickup capacity fixture must restore")
		quit(1)
	draws = 0
	return battle


func _roll(_limit: int) -> int:
	draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition


func _map_unit(
	id: int, faction: int, x: int, y: int, visible: bool = true, hp: int = 30
) -> Dictionary:
	return {"id": id, "faction": faction, "x": x, "y": y, "visible": visible, "hp": hp}


func _map_item(shape: String, period: int) -> Dictionary:
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


func _element_fixture(weapon: int, effects: bool = true) -> Dictionary:
	var templates: Array = []
	for id: int in [0, 40, 46, 49, 50, 51, 67, 81, 87]:
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
				_map_item(
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
		var current: Dictionary = _map_unit(data[0], data[1], data[2], data[3], true, 80)
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
		"map":
		{
			"width": 5,
			"height": 5,
			"tiles": terrain.duplicate(true),
			"terrain": terrain,
			"movementCosts": {"0": costs}
		},
		"rules":
		{
			"itemTemplates": templates,
			"initialGold": 0,
			"alliances": [0, 0, 1],
			"terrainDefense": [0],
			"terrainEvasion": [0],
			"aiClassOrder": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
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
		_expect(false, "Independent map-attack fixture must restore")
	return {"content": content, "battle": battle}


func _elements() -> bool:
	# Three distinct hostile units share the trusted class group, regardless of ID order.
	var fixture: Dictionary = _element_fixture(40)
	var content: Dictionary = fixture["content"]
	for unit: Dictionary in content["units"]:
		if unit["id"] in [35, 57, 33]:
			unit["classId"] = 10
			unit["classGroup"] = 10
			unit["hp"] = 1
			if unit["id"] == 35:
				unit["inventory"] = [{"id": "element81", "templateId": 81, "durability": 1}]
			if unit["id"] == 57:
				unit["x"] = 2
				unit["y"] = 1
	content["rules"]["jobTemplates"].append({"id": 10, "classGroup": 10, "equipMask": 16})
	content["map"]["locations"] = [
		{
			"id": "wait_attack",
			"sourceIndex": 0,
			"kind": "waitPickup",
			"position": [0, 2],
			"tileId": 39,
			"reward": {"kind": "item", "templateId": 40}
		}
	]
	var battle: RefCounted = Battle.new(content, _roll, false)
	var state: Dictionary = battle.snapshot()
	state["units"] = content["units"].duplicate(true)
	for unit: Dictionary in state["units"]:
		if unit["id"] == 8:
			unit["inventory"][0]["durability"] = 12
		elif unit["id"] in [35, 57, 33]:
			unit["hp"] = 1
	var restored: Dictionary = battle.restore_snapshot(state)
	if not _expect(restored["ok"], "Element fixture restores: " + str(restored)):
		return false
	var first: bool = true
	var initial_stats: Dictionary = battle.chapter_stats.duplicate(true)
	for target: int in [35, 35, 57, 33]:
		state = battle.snapshot()
		for unit: Dictionary in state["units"]:
			if unit["id"] == 8:
				unit["action"] = 0
		if not _expect(battle.restore_snapshot(state)["ok"], "Renew attack eligibility"):
			return false
		var combat: RefCounted = Combat.new(content["rules"], content["map"]["terrain"])
		var expected_xp: int = combat.experience_gain(
			battle.unit(8), battle.unit(target), target == 33, true, false
		)
		var result: Dictionary = battle.attack_unit(8, target)
		if not _expect(
			result["ok"] and not battle.event_completed("location:wait_attack"),
			"Attack succeeds without claiming the pickup"
		):
			return false
		if not _expect(
			result["rewards"]["experience"].get("amount") == expected_xp,
			"Group kill experience requires every other element flagged"
		):
			return false
		if first:
			first = false
			var phase_battle: RefCounted = Battle.new(content, _roll, false)
			if not _expect(
				phase_battle.restore_snapshot(battle.snapshot())["ok"],
				"Partial group snapshot restores"
			):
				return false
			if not _expect(
				phase_battle.end_phase()["ok"] and (phase_battle.unit(35)["flags"] & 64) == 0,
				"Phase transition clears partial group flags"
			):
				return false
			phase_battle.phase = 0
			var after_phase: Dictionary = phase_battle.snapshot()
			for current: Dictionary in after_phase["units"]:
				if current["id"] == 8:
					current["action"] = 0
			if not _expect(
				phase_battle.restore_snapshot(after_phase)["ok"], "Later player phase restores"
			):
				return false
			var after_hit: Dictionary = phase_battle.attack_unit(8, 33)
			if not _expect(
				(
					after_hit["ok"]
					and after_hit["rewards"]["experience"].get("amount") == 12
					and phase_battle.unit(33)["visible"]
				),
				"A later phase cannot use the old defeat for kill experience"
			):
				return false
		if not _expect(
			(
				battle.unit(35)["inventory"].size() == 1
				and battle.unit(35)["inventory"][0]["id"] == "element81"
				and battle.chapter_stats == initial_stats
			),
			"Elements retain 81 and do not change retirement statistics"
		):
			return false
		if not _expect(
			battle.event_completed("death") == (target == 33),
			"Death event occurs only on final group retirement"
		):
			return false
		if target != 33:
			if not _expect(
				(
					battle.unit(target)["visible"]
					and battle.unit(target)["hp"] == 1
					and result["retirements"].is_empty()
				),
				"Incomplete group remains visible at HP1, including repeated defeat"
			):
				return false
		else:
			var ids: Array = []
			for retirement: Dictionary in result["retirements"]:
				ids.append(retirement["unitId"])
			if not _expect(
				ids == [33, 57, 35], "Final defeat retires the group in reverse unitOrder"
			):
				return false
			if not _expect(
				(
					not battle.unit(35)["visible"]
					and battle.unit(35)["hp"] == 1
					and not battle.unit(57)["visible"]
					and battle.unit(57)["hp"] == 1
					and not battle.unit(33)["visible"]
					and battle.unit(33)["hp"] == 0
				),
				"Group retirement preserves previous HP1 and final HP0"
			):
				return false
	return true


func _map_elements() -> bool:
	for prior_flag: bool in [false, true]:
		var fixture: Dictionary = _element_fixture(50)
		var content: Dictionary = fixture["content"]
		content["rules"]["jobTemplates"].append({"id": 10, "classGroup": 10, "equipMask": 16})
		for unit: Dictionary in content["units"]:
			if unit["id"] in [35, 57, 33]:
				unit["classId"] = 10
				unit["classGroup"] = 10
				unit["hp"] = 1
				if unit["id"] == 57:
					unit["faction"] = 1
				if unit["id"] == 57 and prior_flag:
					unit["flags"] |= 64
		var battle: RefCounted = Battle.new(content, _roll, false)
		var state: Dictionary = battle.snapshot()
		state["units"] = content["units"].duplicate(true)
		if not _expect(battle.restore_snapshot(state)["ok"], "Map element fixture restores"):
			return false
		var combat: RefCounted = Combat.new(content["rules"], content["map"]["terrain"])
		var expected: int = combat.experience_gain(
			battle.unit(8), battle.unit(33), prior_flag, true, false
		)
		var result: Dictionary = battle.cast_map_attack(8, "cast", 35)
		if not _expect(
			result["ok"] and result["targetIds"] == [35, 33], "Map attack hits in unitOrder"
		):
			return false
		if not _expect(
			result["rewards"]["experience"].get("amount") == expected,
			"Map experience applies prior defeats only to the last target"
		):
			return false
		if not _expect(
			result["updates"].size() == 2 and result["updates"][0]["units"][0]["hp"] == 1,
			"First map hit restores HP1 at its cleanup point"
		):
			return false
		if not _expect(
			(
				battle.unit(35)["visible"] != prior_flag
				and battle.unit(33)["visible"] != prior_flag
				and battle.unit(57)["visible"] != prior_flag
			),
			"Final map hit hides the whole group only when all flags are present"
		):
			return false
		if prior_flag:
			var ids: Array = []
			for retirement: Dictionary in result["retirements"]:
				ids.append(retirement["unitId"])
			if not _expect(
				ids == [33, 57, 35], "Map retirement includes the indirect member in reverse order"
			):
				return false
	return true


func _reordered_elements() -> bool:
	var fixture: Dictionary = _element_fixture(40)
	var content: Dictionary = fixture["content"]
	content["unitOrder"] = [8, 33, 35, 57, 9]
	content["rules"]["jobTemplates"].append({"id": 10, "classGroup": 10, "equipMask": 16})
	for unit: Dictionary in content["units"]:
		if unit["id"] == 8:
			unit["inventory"][0]["durability"] = 12
		if unit["id"] in [35, 57, 33]:
			unit["classId"] = 10
			unit["classGroup"] = 10
			unit["hp"] = 1
			if unit["id"] == 57:
				unit["x"] = 2
				unit["y"] = 1
	var battle: RefCounted = Battle.new(content, _roll, false)
	var state: Dictionary = battle.snapshot()
	state["units"] = content["units"].duplicate(true)
	if not _expect(battle.restore_snapshot(state)["ok"], "Reordered element fixture restores"):
		return false
	for target: int in [57, 33, 35]:
		state = battle.snapshot()
		for unit: Dictionary in state["units"]:
			if unit["id"] == 8:
				unit["action"] = 0
		if not _expect(battle.restore_snapshot(state)["ok"], "Reordered attack is ready"):
			return false
		var result: Dictionary = battle.attack_unit(8, target)
		if not _expect(result["ok"], "Reordered element attack succeeds: " + str(result)):
			return false
		if target == 35:
			var ids: Array = []
			for retirement: Dictionary in result["retirements"]:
				ids.append(retirement["unitId"])
			if not _expect(
				ids == [57, 35, 33], "Different final target retires in reversed current unitOrder"
			):
				return false
	return true


func _single_map_element() -> bool:
	for complete: bool in [false, true]:
		var fixture: Dictionary = _element_fixture(50)
		var content: Dictionary = fixture["content"]
		content["rules"]["jobTemplates"].append({"id": 10, "classGroup": 10, "equipMask": 16})
		for unit: Dictionary in content["units"]:
			if unit["id"] in [35, 57, 33]:
				unit["classId"] = 10
				unit["classGroup"] = 10
				unit["hp"] = 1
				if unit["id"] == 33:
					unit["x"] = 4
					unit["y"] = 4
				if complete and unit["id"] != 35:
					unit["flags"] |= 64
		var battle: RefCounted = Battle.new(content, _roll, false)
		var state: Dictionary = battle.snapshot()
		state["units"] = content["units"].duplicate(true)
		if not _expect(battle.restore_snapshot(state)["ok"], "Single map target fixture restores"):
			return false
		var combat: RefCounted = Combat.new(content["rules"], content["map"]["terrain"])
		var expected: int = combat.experience_gain(
			battle.unit(8), battle.unit(35), complete, true, false
		)
		var result: Dictionary = battle.cast_map_attack(8, "cast", 35)
		if not _expect(
			(
				result["ok"]
				and result["targetIds"] == [35]
				and result["rewards"]["experience"].get("amount") == expected
			),
			"Single map target awards experience according to group qualification"
		):
			return false
	return true
