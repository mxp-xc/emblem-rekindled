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
	var inherited_context: Dictionary = {
		"attributes":
		{"strength": 90, "skill": 90, "speed": 90, "defense": 90, "magic": 90, "luck": 90},
		"maxHp": 90,
		"maxInternalLevel": 9,
		"averageInternalLevel": 9,
		"maxProficiency": 90
	}
	var inherited: Dictionary = Battle.new(inherited_content, draw, true, inherited_context).unit(0)
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
	var boss_content: Dictionary = fixture()
	boss_content["units"][3]["id"] = 80
	boss_content["units"][3]["sourceId"] = 80
	boss_content["spawns"][3]["id"] = 80
	boss_content["spawns"][3]["sourceId"] = 80
	boss_content["unitOrder"][3] = 80
	_draws.clear()
	var boss: Dictionary = Battle.new(boss_content, draw).unit(80)
	if boss["hp"] != 40 or boss["maxHp"] != 40:
		fail("A newly deployed enemy with runtime identity 80 must receive 20 base HP")
		return
	var context: Dictionary = {
		"attributes": {"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
		"maxHp": 90,
		"maxInternalLevel": 0,
		"averageInternalLevel": 0,
		"maxProficiency": 0
	}
	var original_context: Dictionary = context.duplicate(true)
	_draws.clear()
	var adapted: Dictionary = Battle.new(boss_content, draw, true, context).unit(80)
	if adapted["hp"] != 40 or adapted["maxHp"] != 65 or context != original_context:
		fail("Boss adaptive HP must leave current HP at its pre-adaptation value")
		return
	if _draws.size() != 11:
		fail("Boss adaptive HP must not draw randomness or change the supplied context")
		return
	var odd_context: Dictionary = context.duplicate(true)
	odd_context["maxHp"] = 91
	odd_context["attributes"]["strength"] = 10
	odd_context["attributes"]["skill"] = 3
	odd_context["attributes"]["speed"] = 5
	_draws.clear()
	adapted = Battle.new(boss_content, draw, true, odd_context).unit(80)
	if (
		adapted["hp"] != 40
		or adapted["maxHp"] != 65
		or adapted["attributes"]["strength"] != 7
		or adapted["attributes"]["skill"] != 5
		or adapted["attributes"]["speed"] != 5
		or adapted["move"] != 3
	):
		fail("Adaptive increments use only positive half differences and leave move unchanged")
		return
	var cap_content: Dictionary = boss_content.duplicate(true)
	cap_content["rules"]["baseStats"][0]["maxHp"] = 79
	cap_content["rules"]["baseStats"][0]["strength"] = 90
	var cap_context: Dictionary = context.duplicate(true)
	cap_context["maxHp"] = 127
	cap_context["attributes"]["strength"] = 127
	cap_context["maxProficiency"] = 200
	_draws.clear()
	adapted = Battle.new(cap_content, draw, true, cap_context).unit(80)
	if (
		adapted["hp"] != 99
		or adapted["maxHp"] != 99
		or adapted["attributes"]["strength"] != 99
		or adapted["proficiency"] != 800
	):
		fail("Adaptive attributes and proficiency must stop at their respective caps")
		return
	var explicit_content: Dictionary = boss_content.duplicate(true)
	explicit_content["spawns"][3]["explicitStats"] = (
		explicit_content["rules"]["baseStats"][0].duplicate()
	)
	_draws.clear()
	adapted = Battle.new(explicit_content, draw, true, context).unit(80)
	if adapted["hp"] != 20 or adapted["maxHp"] != 55 or _draws.size() != 3:
		fail("An explicit-stat boss skips base HP growth but still receives adaptive HP")
		return
	var null_content: Dictionary = boss_content.duplicate(true)
	var explicit: Dictionary = null_content["rules"]["baseStats"][0].duplicate()
	explicit["strength"] = 110
	explicit["maxHp"] = 90
	null_content["spawns"][3]["explicitStats"] = explicit
	_draws.clear()
	adapted = Battle.new(null_content, draw).unit(80)
	if adapted["attributes"]["strength"] != 99 or adapted["hp"] != 90 or adapted["maxHp"] != 90:
		fail("A boss with no adaptive context must still apply the public attribute cap")
		return
	for sample: Dictionary in [
		{"id": 79, "faction": 2, "base": 20, "expected": 20},
		{"id": 80, "faction": 2, "base": 20, "expected": 40},
		{"id": 94, "faction": 2, "base": 20, "expected": 40},
		{"id": 95, "faction": 2, "base": 20, "expected": 20},
		{"id": 80, "faction": 0, "base": 20, "expected": 20},
		{"id": 80, "faction": 1, "base": 20, "expected": 20},
		{"id": 80, "faction": 2, "base": 55, "expected": 60},
		{"id": 80, "faction": 2, "base": 20, "expected": 20, "explicit": true},
		{"id": 80, "faction": 2, "base": 20, "expected": 40, "magicWeapon": true}
	]:
		var example: Dictionary = fixture()
		var definition: Dictionary = example["units"][3]
		var spawn: Dictionary = example["spawns"][3]
		for unit: Dictionary in [definition, spawn]:
			unit["id"] = sample["id"]
			unit["sourceId"] = sample["id"]
			unit["faction"] = sample["faction"]
		spawn.erase("deploymentRegions")
		spawn["randomEquipment"] = false
		spawn["itemChoices"] = [1]
		if sample.get("magicWeapon", false):
			example["rules"]["itemTemplates"][1]["categoryMask"] = 16
			definition["equipMask"] = 16
		example["units"] = [definition]
		example["spawns"] = [spawn]
		example["unitOrder"] = [sample["id"]]
		example["rules"]["baseStats"][0]["maxHp"] = sample["base"]
		example["rules"]["statCaps"]["maxHp"] = 60
		if sample.get("explicit", false):
			spawn["explicitStats"] = example["rules"]["baseStats"][0].duplicate()
		_draws.clear()
		var deployed: Dictionary = Battle.new(example, draw).unit(sample["id"])
		if deployed["hp"] != sample["expected"] or deployed["maxHp"] != sample["expected"]:
			fail(
				(
					"Base HP must follow runtime identity, faction, cap and explicit stats: "
					+ str(sample)
				)
			)
			return
		if sample["faction"] != 0 and not sample.get("explicit", false) and _draws.size() != 8:
			fail("Base HP bonus must not consume an additional random draw")
			return
		if sample.get("explicit", false) and not _draws.is_empty():
			fail("Explicit stats must not consume growth noise")
			return
		if (
			sample.get("magicWeapon", false)
			and (_draws[0] != 4 or deployed["equippedInstanceId"] == "")
		):
			fail("A static deployment equips after growth, even when its weapon has category 16")
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
		"map":
		{
			"width": 3,
			"height": 2,
			"tiles": [[0, 0, 0], [0, 0, 0]],
			"terrain": [[0, 0, 0], [0, 0, 0]],
			"movementCosts": {"0": [[1, 1, 1], [1, 1, 1]]}
		},
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
			"baseMovementCosts": [1],
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
