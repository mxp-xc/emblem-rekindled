extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
var _draws: Array[int] = []


func _initialize() -> void:
	var content: Dictionary = fixture()
	var original: Dictionary = content.duplicate(true)
	var battle: RefCounted = Battle.new(content, draw)
	if content != original:
		fail("Initializing a deployment must not mutate its supplied definition")
		return
	if _draws != [3, 3, 4, 4, 3, 3, 3, 3, 6, 3, 1]:
		fail(
			"Draws must follow equipment, deduplicated free positions, then growth: " + str(_draws)
		)
		return
	if not battle.unit(96).is_empty() or battle.unit(95).get("sourceId") != 4:
		fail("A full region must skip its record without consuming a temporary identity")
		return
	if battle.deployment_bindings() != {0: 0, 1: -1, 2: 95, 3: 30}:
		fail("Successful identities must remain traceable to the original deployment order")
		return
	var enemy: Dictionary = battle.unit(30)
	if enemy["x"] != 1 or enemy["y"] != 1:
		fail("Overlapping inclusive rectangles must count a free cell once in x/y scan order")
		return
	if enemy["inventory"].size() != 1 or enemy["inventory"][0]["templateId"] != 1:
		fail("The chosen equipment must survive deployment and growth")
		return
	var state: Dictionary = battle.snapshot()
	state["units"][0]["visible"] = true
	state["units"][0]["policy"] = 32
	var resolved: Dictionary = content.duplicate(true)
	resolved["units"] = state["units"].duplicate(true)
	resolved["unitOrder"] = state["units"].map(
		func(unit: Dictionary) -> int: return int(unit["id"])
	)
	resolved["spawns"] = [content["spawns"][0], content["spawns"][2], content["spawns"][3]]
	resolved["optionalIds"] = [30]
	_draws.clear()
	var restored: RefCounted = Battle.new(resolved, draw, false)
	if not _draws.is_empty() or not restored.restore_snapshot(state)["ok"] or not _draws.is_empty():
		fail("Restoring saved results must perform no initial equipment/position/growth draw")
		return
	if restored.unit(0)["policy"] != 0:
		fail("An old player slot policy must not become an autonomous AI policy after restore")
		return
	var before: Dictionary = restored.snapshot()
	restored.adopt_content(resolved)
	if restored.snapshot() != before or not _draws.is_empty():
		fail("Refreshing content bindings must preserve battle results and random state")
		return
	state["units"] = state["units"].filter(func(unit: Dictionary) -> bool: return unit["id"] != 30)
	if not Battle.new(resolved, draw, false).restore_snapshot(state)["ok"]:
		fail("An optional regional record may be absent from a saved deployment")
		return
	state["units"] = state["units"].filter(func(unit: Dictionary) -> bool: return unit["id"] != 95)
	if Battle.new(resolved, draw, false).restore_snapshot(state)["ok"]:
		fail("A fixed deployment cannot disappear from a saved battle")
		return
	var combat_content: Dictionary = fixture()
	combat_content["story"]["combatEvents"] = [
		{"id": "first_boss", "trigger": "firstCombat", "unitId": 30, "sequence": "boss_first"},
		{
			"id": "boss_death",
			"trigger": "unitDeath",
			"unitId": 30,
			"beforeRetirement": "boss_death",
			"afterRetirement": "response"
		}
	]
	_draws.clear()
	var combat: RefCounted = Battle.new(combat_content, draw)
	var attack: Dictionary = combat.attack_unit(95, 30)
	if (
		not attack["ok"]
		or attack["storyBefore"] != ["boss_first"]
		or attack.has("storyAfter")
		or (
			attack["retirements"]
			!= [{"unitId": 30, "beforeRetirement": ["boss_death"], "afterRetirement": ["response"]}]
		)
		or not combat.event_completed("first_boss")
		or not combat.event_completed("boss_death")
		or (int(combat.unit(30)["flags"]) & 4) == 0
	):
		fail("A committed fight must publish first-combat/death stories and saved one-time state")
		return
	if combat.unit(30)["hp"] != 0 or combat.unit(30)["visible"]:
		fail("Death presentation must preserve the immediately committed HP and retirement state")
		return
	if attack["participants"][1]["hp"] <= 0 or not attack["participants"][1]["visible"]:
		fail("Death presentation must retain the live participant captured before combat")
		return
	before = combat.snapshot()
	if combat.attack_unit(95, 30)["ok"] or combat.snapshot() != before:
		fail("A rejected repeated attack must not replay or change committed combat events")
		return
	_draws.clear()
	var combat_resolved: Dictionary = combat_content.duplicate(true)
	combat_resolved["units"] = before["units"].duplicate(true)
	combat_resolved["unitOrder"] = before["units"].map(
		func(unit: Dictionary) -> int: return int(unit["id"])
	)
	combat_resolved["spawns"] = [
		combat_content["spawns"][0], combat_content["spawns"][2], combat_content["spawns"][3]
	]
	combat_resolved["optionalIds"] = [30]
	var continued: RefCounted = Battle.new(combat_resolved, draw, false)
	if (
		not continued.restore_snapshot(before)["ok"]
		or continued.snapshot() != before
		or not continued.event_completed("first_boss")
		or not continued.event_completed("boss_death")
		or (int(continued.unit(30)["flags"]) & 4) == 0
		or not _draws.is_empty()
	):
		fail(
			"Restoring committed death must retain B4 and once markers without another random draw"
		)
		return
	var inherited_content: Dictionary = fixture()
	var member: Dictionary = battle.unit(0)
	member["level"] = 6
	member["attributes"]["strength"] = 23
	member["inventory"][0]["durability"] = 7
	member["x"] = 2
	member["y"] = 1
	inherited_content["inheritedParty"] = [member]
	inherited_content["spawns"][0]["deploymentSlot"] = 0
	inherited_content["spawns"][0]["randomEquipment"] = true
	var member_before: Dictionary = member.duplicate(true)
	var inherited: Dictionary = Battle.new(inherited_content, draw).unit(0)
	if (
		member != member_before
		or inherited["level"] != 6
		or inherited["attributes"]["strength"] != 23
		or inherited["inventory"][0]["durability"] != 7
		or inherited["x"] != 0
		or inherited["y"] != 0
		or inherited["visible"]
	):
		fail("Inherited cultivation and equipment must survive while this map supplies deployment")
		return
	print(
		"PASS deployment initialization: source draw order, regions, skipped IDs and direct restore"
	)
	quit(0)


func draw(limit: int) -> int:
	_draws.append(limit)
	return 2 if _draws.size() == 3 else 0


func fixture() -> Dictionary:
	var stats: Dictionary = {
		"strength": 5,
		"skill": 5,
		"speed": 5,
		"defense": 5,
		"magic": 5,
		"luck": 5,
		"maxHp": 20,
		"move": 3
	}
	var growth: Dictionary = stats.duplicate()
	for key: String in growth:
		growth[key] = 0
	var base: Dictionary = stats.duplicate()
	base["id"] = 0
	growth["id"] = 0
	var temporary_growth: Dictionary = growth.duplicate()
	temporary_growth["id"] = 10
	var items: Array = []
	for id: int in range(4):
		items.append(
			{
				"id": id,
				"damageKind": "none" if id == 0 else "physical",
				"categoryMask": 1,
				"defaultDurability": 10,
				"power": 99,
				"hit": 100,
				"critical": 0,
				"weight": 0,
				"minRange": 1,
				"maxRange": 1,
				"ignoresDefense": false,
				"effectiveGroups": [],
				"doubleStrike": false,
				"drainsHp": false
			}
		)
		if id > 0:
			items[-1]["actionMode"] = "battle_clip"
	var records: Array = []
	var units: Array = []
	for id: int in [0, 95, 96, 30]:
		var index: int = units.size()
		var source_id: int = 3 if id == 95 else (4 if id == 96 else id)
		units.append(
			{
				"id": id,
				"sourceId": source_id,
				"faction": 2 if id == 30 else 0,
				"classId": 0,
				"classGroup": 0,
				"equipMask": 1,
				"name": "fixture",
				"formal": id == 0,
				"flags": 1 if id == 0 else 0,
				"policy": 0,
				"visible": id != 0,
				"x": 0,
				"y": 0,
				"level": 1,
				"hp": 1,
				"maxHp": 1,
				"move": 0,
				"experience": 0,
				"proficiency": 0,
				"dropTemplateId": 0,
				"action": 0,
				"inventory": [],
				"equippedInstanceId": "",
				"deploymentIndex": index,
				"temporary": id in [95, 96]
			}
		)
		records.append(
			{
				"id": id,
				"sourceId": source_id,
				"faction": 2 if id == 30 else 0,
				"classId": 0,
				"formal": id == 0,
				"flags": 1 if id == 0 else 0,
				"visible": id != 0,
				"policy": 0,
				"level": 1,
				"growthTemplateId": 0,
				"baseTemplateId": 0,
				"initialGrowthTemplateId": 0,
				"position": [2, 1] if id == 96 else [0, 0],
				"randomEquipment": id in [95, 30],
				"itemChoices": [1, 2, 3],
				"dropTemplateId": 0,
				"deploymentIndex": index,
				"temporary": id in [95, 96]
			}
		)
	records[1]["deploymentRegions"] = [[0, 0, 0, 0]]
	records[3]["deploymentRegions"] = [[0, 0, 1, 1], [1, 0, 2, 0]]
	return {
		"entry": {"id": "fixture", "battleId": "m0", "initialParty": [0], "recruitByNode": {}},
		"map": {"width": 3, "height": 2, "terrain": [[0, 0, 0], [0, 0, 0]], "movementCosts": {}},
		"units": units,
		"unitOrder": units.map(func(unit: Dictionary) -> int: return int(unit["id"])),
		"spawns": records,
		"optionalIds": [95, 30],
		"rules":
		{
			"initialGold": 0,
			"alliances": [0, 0, 1],
			"aiClassOrder": [0],
			"itemTemplates": items,
			"terrainDefense": [0],
			"terrainEvasion": [0],
			"baseStats": [base],
			"growthRates": [growth, temporary_growth],
			"statCaps":
			{
				"strength": 99,
				"skill": 99,
				"speed": 99,
				"defense": 99,
				"magic": 99,
				"luck": 99,
				"maxHp": 99,
				"move": 20
			},
			"jobTemplates": [{"id": 0, "classGroup": 0, "equipMask": 1}]
		},
		"story":
		{
			"sequences":
			{
				"opening": [{"kind": "commanderSetup", "candidates": [0], "defaultCommanderId": 0}],
				"victory": [{"goldReward": 0}]
			},
			"routeChoices": [{"routeIndex": 0}],
			"worldNode": 0,
			"world": {"routes": [[0, 1]]},
			"turnEvents": [],
			"aiChanges": [],
			"outcomeRules":
			{"checks": [{"condition": "requiredUnitFallen", "kind": "defeat", "unitIds": [0]}]}
		}
	}


func fail(message: String) -> void:
	push_error(message)
	quit(1)
