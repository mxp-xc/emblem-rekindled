extends RefCounted

const Inventory = preload("res://gameplay/unit_inventory.gd")
const Deployment = preload("res://app/chapter_deployment.gd")
const Statistics = preload("res://gameplay/chapter_statistics.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
var _chapter_id: String
var _battle_id: String
var _gold_reward: int
var _inherited_ids: Array[int] = []
var _world_node: int
var _world_routes: Array
var _recruit_by_node: Dictionary
var _initial_party: Array
var _records: RefCounted
var _gold_limit: int
var _chapter_end: Dictionary
var _commander_mode: String
var _combat: RefCounted
var _encounter: bool


func _init(
	content: Dictionary, records: RefCounted, gold_limit: int, combat: RefCounted = null
) -> void:
	_chapter_id = content["entry"]["id"]
	_battle_id = content["entry"]["battleId"]
	_encounter = content["story"].get("encounter", false) == true
	_gold_reward = int(content["story"]["sequences"]["victory"][-1]["goldReward"])
	_world_node = int(content["story"]["worldNode"])
	_world_routes = content["story"]["world"]["routes"]
	_recruit_by_node = content["entry"]["recruitByNode"]
	_initial_party = content["entry"]["initialParty"]
	_records = records
	_gold_limit = gold_limit
	_chapter_end = content["story"].get("chapterEnd", {}).duplicate(true)
	_commander_mode = content["story"].get("commanderMode", "selection")
	_combat = combat if combat != null else Combat.new(content["rules"], content["map"]["terrain"])
	var inherited: Dictionary = {}
	for member: Dictionary in content.get("inheritedParty", []):
		inherited[int(member["id"])] = true
	for spawn: Dictionary in content["spawns"]:
		if spawn["formal"] and (spawn.has("deploymentSlot") or inherited.has(int(spawn["id"]))):
			_inherited_ids.append(int(spawn["id"]))


func prepare(progress: Dictionary, definitions: Dictionary) -> Dictionary:
	if progress.get("chapterCompleted", false) and not _encounter:
		return _failure("CHAPTER_ALREADY_COMPLETED")
	if progress.has("chapterStats") and not progress["chapterStats"] is Dictionary:
		return _failure("INVALID_CHAPTER_STATS")
	var statistics: Dictionary = Statistics.decode(progress.get("chapterStats"))
	if not statistics["ok"]:
		return statistics
	var units: Dictionary = definitions.duplicate(true)
	var campaign: Dictionary = {
		"route": progress.get("route"), "worldStep": progress.get("worldStep", 1)
	}
	if _encounter:
		campaign["encounterLocation"] = progress.get("worldLocation", progress.get("worldNode"))
		if not progress.get("party") is Array:
			return _failure("INVALID_CAMPAIGN_ENTRY")
		var positions: Array = []
		for member: Variant in progress["party"]:
			if not member is Dictionary:
				return _failure("INVALID_CAMPAIGN_ENTRY")
			positions.append({"id": member.get("id"), "x": member.get("x"), "y": member.get("y")})
		campaign["encounterPositions"] = positions
		if progress.has("chapterCompleted") and not progress["chapterCompleted"] is bool:
			return _failure("INVALID_CAMPAIGN_ENTRY")
		if progress.get("chapterCompleted", false):
			if (
				progress.has("chapterResultHistorical")
				and not progress["chapterResultHistorical"] is bool
			):
				return _failure("INVALID_CHAPTER_RESULT")
			campaign["chapterResult"] = progress.get("chapterResult")
	if (
		_inherited_ids.is_empty()
		or progress.get("chapterId") != _chapter_id
		or not progress.get("party") is Array
		or progress["party"].size() != _inherited_ids.size()
		or not progress.get("warehouse") is Array
		or progress["warehouse"].size() > Inventory.WAREHOUSE_CAPACITY
		or not _integer_in(progress.get("gold"), 0, _gold_limit)
		or not _integer_in(progress.get("route"), 0, 7)
		or not _integer_in(progress.get("worldStep", 1), 1, 17)
		or not valid_context(campaign)
		or (progress.has("levelTutorialSeen") and not progress["levelTutorialSeen"] is bool)
	):
		return _failure("INVALID_CAMPAIGN_ENTRY")
	var previous_node: int = int(
		_world_routes[int(campaign["route"])][int(campaign["worldStep"]) - 1]
	)
	if (
		progress.get("worldNode") != previous_node
		or progress.get("completedBattle") != "m%d" % previous_node
	):
		return _failure("INVALID_CAMPAIGN_ENTRY")
	var inherited: Dictionary = {}
	var held_ids: Dictionary = {}
	for saved: Variant in progress["party"]:
		if not saved is Dictionary or not _integer_in(saved.get("id"), 0, 2147483647):
			return _failure("INVALID_CAMPAIGN_PARTY")
		var id: int = int(saved["id"])
		if id not in _inherited_ids or inherited.has(id):
			return _failure("INVALID_CAMPAIGN_PARTY")
		var current: Dictionary = units[id].duplicate(true)
		for key: String in [
			"classId",
			"classGroup",
			"equipMask",
			"level",
			"hp",
			"maxHp",
			"move",
			"growthTemplateId",
			"experience",
			"proficiency",
			"attributes",
			"inventory",
			"equippedInstanceId"
		]:
			if not saved.has(key):
				return _failure("INVALID_CAMPAIGN_PARTY")
			current[key] = (
				saved[key].duplicate(true)
				if saved[key] is Array or saved[key] is Dictionary
				else saved[key]
			)
		var decoded: Dictionary = _records.decode(current, held_ids)
		if not decoded["ok"]:
			return decoded
		inherited[id] = decoded["unit"]
	for id: int in units:
		if (
			not inherited.has(id)
			and not _records.validate_inventory(units[id]["inventory"], held_ids)
		):
			return _failure("INVALID_CAMPAIGN_INVENTORY")
	var warehouse: Array = progress["warehouse"].duplicate(true)
	if not _records.validate_inventory(warehouse, held_ids):
		return _failure("INVALID_CAMPAIGN_INVENTORY")
	for id: int in inherited:
		units[id] = inherited[id]
	if _encounter and progress.get("chapterCompleted", false):
		var checked: Dictionary = Statistics.validate_result(
			progress.get("chapterResult"),
			progress["party"],
			statistics["stats"],
			progress.get("chapterResultHistorical", false)
		)
		if not checked["ok"]:
			return checked
	if _commander_mode == "none":
		if (
			not _integer_in(progress.get("commander"), -1, 2147483647)
			or not _integer_in(progress.get("commandPolicy", 0), 0, 5)
			or int(progress.get("commandPolicy", 0)) not in [0, 1, 4, 5]
			or (int(progress["commander"]) >= 0 and not inherited.has(int(progress["commander"])))
		):
			return _failure("INVALID_CAMPAIGN_COMMANDER")
	campaign["route"] = int(campaign["route"])
	campaign["worldStep"] = int(campaign["worldStep"])
	if _encounter:
		campaign["encounterLocation"] = int(campaign["encounterLocation"])
	var prepared: Dictionary = {
		"ok": true,
		"units": units,
		"warehouse": warehouse,
		"gold": int(progress["gold"]),
		"events": {"level_tutorial": true} if progress.get("levelTutorialSeen", false) else {},
		"campaign": campaign,
		"chapterStats": statistics["stats"]
	}
	if _commander_mode == "none":
		prepared["commander"] = int(progress["commander"]) if _encounter else -1
		prepared["commandPolicy"] = int(progress.get("commandPolicy", 0))
	return prepared


func valid_context(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if _inherited_ids.is_empty():
		return value.is_empty()
	if not _integer_in(value.get("route"), 0, _world_routes.size() - 1):
		return false
	var route: Array = _world_routes[int(value["route"])]
	if _encounter:
		if (
			not _integer_in(value.get("worldStep"), 6, route.size())
			or route[int(value["worldStep"]) - 1] != _world_node
			or not _integer_in(value.get("encounterLocation"), 0, 16)
			or not route.slice(0, int(value["worldStep"])).any(
				func(node: Variant) -> bool: return node == value["encounterLocation"]
			)
		):
			return false
		if value.has("chapterResult") != (int(value["worldStep"]) == route.size()):
			return false
		if value.has("chapterResult") and not value["chapterResult"] is Dictionary:
			return false
		var positions: Variant = value.get("encounterPositions")
		if not positions is Array or positions.size() != _inherited_ids.size():
			return false
		var seen: Dictionary = {}
		for point: Variant in positions:
			if (
				not point is Dictionary
				or not _integer_in(point.get("id"), 0, 2147483647)
				or int(point["id"]) not in _inherited_ids
				or seen.has(int(point["id"]))
				or not _integer_in(point.get("x"), 0, 32767)
				or not _integer_in(point.get("y"), 0, 32767)
			):
				return false
			seen[int(point["id"])] = true
		return true
	return (
		_integer_in(value.get("worldStep"), 1, route.size() - 1)
		and route[int(value["worldStep"])] == _world_node
	)


func complete(state: Dictionary, route: int) -> Dictionary:
	if state.has("chapterStats") and not state["chapterStats"] is Dictionary:
		return _failure("INVALID_CHAPTER_STATS")
	var statistics: Dictionary = Statistics.decode(state.get("chapterStats"))
	if not statistics["ok"]:
		return statistics
	var campaign: Dictionary = state.get("campaign", {})
	var world_step: int = int(campaign.get("worldStep", 0)) + (0 if _encounter else 1)
	if not valid_context(campaign) or route < 0 or route >= _world_routes.size():
		return _failure("INVALID_COMPLETION_ROUTE")
	if _encounter and route != int(campaign["route"]):
		return _failure("INVALID_COMPLETION_ROUTE")
	var terminal: bool = not _chapter_end.is_empty()
	if (
		terminal
		and (
			world_step != _world_routes[route].size()
			or int(_world_routes[route][-1]) != _world_node
			or _chapter_end.get("id") != _chapter_id
		)
	):
		return _failure("INVALID_COMPLETION_ROUTE")
	if not campaign.is_empty():
		var chosen: Array = _world_routes[route]
		var previous: Array = _world_routes[int(campaign["route"])]
		for index: int in range(world_step):
			if index >= chosen.size() or chosen[index] != previous[index]:
				return _failure("INVALID_COMPLETION_ROUTE")
	var party: Dictionary = {}
	for unit: Dictionary in state["units"]:
		if not unit["formal"]:
			continue
		var actor: Dictionary = unit.duplicate(true)
		actor["hp"] = actor["maxHp"]
		actor["flags"] = 0
		actor["action"] = 0
		actor["visible"] = true
		party[int(actor["id"])] = actor
	var ordered_party: Dictionary = {}
	for id: int in Deployment.recruit_order(
		_world_routes[route], _recruit_by_node, world_step, _initial_party
	):
		if not party.has(id):
			return _failure("INVALID_COMPLETION_PARTY")
		ordered_party[id] = party[id]
	if ordered_party.size() != party.size():
		return _failure("INVALID_COMPLETION_PARTY")
	party = ordered_party
	if _encounter:
		for position: Dictionary in campaign["encounterPositions"]:
			var actor: Dictionary = party[int(position["id"])]
			actor["x"] = int(position["x"])
			actor["y"] = int(position["y"])
	if terminal and _chapter_end.has("itemReward"):
		var reward: Dictionary = _chapter_end["itemReward"]
		var recipient: int = int(reward.get("unitId", -1))
		var template_id: int = int(reward.get("templateId", -1))
		var template: Dictionary = _combat.item_definition(template_id)
		if not party.has(recipient) or template_id <= 0 or template.is_empty():
			return _failure("INVALID_COMPLETION_REWARD")
		if party[recipient]["inventory"].size() < Inventory.BAG_CAPACITY:
			party[recipient]["inventory"].append(
				{
					"id": "%s:chapter_end:%s:unit_%d" % [_chapter_id, _battle_id, recipient],
					"templateId": template_id,
					"durability": int(template["defaultDurability"])
				}
			)
	var progress: Dictionary = {
		"chapterId": _chapter_id,
		"completedBattle": "m%d" % _world_node if _encounter else _battle_id,
		"worldNode": _world_node,
		"worldStep": world_step,
		"route": route,
		"gold": mini(_gold_limit, int(state["gold"]) + _gold_reward),
		"commander": state["commander"],
		"commandPolicy": state["commandPolicy"],
		"party": party.values().duplicate(true),
		"warehouse": state["warehouse"].duplicate(true),
		"chapterStats": statistics["stats"]
	}
	if _encounter:
		progress["worldLocation"] = int(campaign["encounterLocation"])
		if campaign.has("chapterResult"):
			progress["chapterCompleted"] = true
			progress["chapterResult"] = campaign["chapterResult"].duplicate(true)
			progress["chapterResultHistorical"] = true
	if terminal:
		var commander: Dictionary = {}
		for actor: Dictionary in state["units"]:
			if actor["id"] == state["commander"] and actor["visible"] and actor["hp"] > 0:
				commander = party.get(int(actor["id"]), {})
				break
		var results: Array = []
		var total_power: int = 0
		var ids: Array = party.keys()
		ids.sort()
		for id: int in ids:
			var power: int = _combat.power(party[id], commander)
			results.append({"id": id, "level": int(party[id]["level"]), "power": power})
			total_power += power
		var result: Dictionary = {
			"party": results,
			"gold": progress["gold"],
			"totalPower": total_power,
			"chapterStats": statistics["stats"].duplicate(true)
		}
		var checked: Dictionary = Statistics.validate_result(
			result, progress["party"], statistics["stats"]
		)
		if not checked["ok"]:
			return checked
		progress["chapterCompleted"] = true
		progress["chapterResult"] = checked["result"]
	if state["events"].get("level_tutorial", false):
		progress["levelTutorialSeen"] = true
	return {"ok": true, "party": party, "progress": progress}


func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
