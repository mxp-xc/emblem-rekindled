extends RefCounted

const Inventory = preload("res://gameplay/unit_inventory.gd")
const Deployment = preload("res://app/chapter_deployment.gd")
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


func _init(content: Dictionary, records: RefCounted, gold_limit: int) -> void:
	_chapter_id = content["entry"]["id"]
	_battle_id = content["entry"]["battleId"]
	_gold_reward = int(content["story"]["sequences"]["victory"][-1]["goldReward"])
	_world_node = int(content["story"]["worldNode"])
	_world_routes = content["story"]["world"]["routes"]
	_recruit_by_node = content["entry"]["recruitByNode"]
	_initial_party = content["entry"]["initialParty"]
	_records = records
	_gold_limit = gold_limit
	for spawn: Dictionary in content["spawns"]:
		if spawn["formal"] and spawn.has("deploymentSlot"):
			_inherited_ids.append(int(spawn["id"]))


func prepare(progress: Dictionary, definitions: Dictionary) -> Dictionary:
	var units: Dictionary = definitions.duplicate(true)
	var campaign: Dictionary = {
		"route": progress.get("route"), "worldStep": progress.get("worldStep", 1)
	}
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
	campaign = {"route": int(campaign["route"]), "worldStep": int(campaign["worldStep"])}
	return {
		"ok": true,
		"units": units,
		"warehouse": warehouse,
		"gold": int(progress["gold"]),
		"events": {"level_tutorial": true} if progress.get("levelTutorialSeen", false) else {},
		"campaign": campaign
	}


func valid_context(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if _inherited_ids.is_empty():
		return value.is_empty()
	if not _integer_in(value.get("route"), 0, _world_routes.size() - 1):
		return false
	var route: Array = _world_routes[int(value["route"])]
	return (
		_integer_in(value.get("worldStep"), 1, route.size() - 1)
		and route[int(value["worldStep"])] == _world_node
	)


func complete(state: Dictionary, route: int) -> Dictionary:
	var campaign: Dictionary = state.get("campaign", {})
	var world_step: int = int(campaign.get("worldStep", 0)) + 1
	if not valid_context(campaign) or route < 0 or route >= _world_routes.size():
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
	var progress: Dictionary = {
		"chapterId": _chapter_id,
		"completedBattle": _battle_id,
		"worldNode": _world_node,
		"worldStep": world_step,
		"route": route,
		"gold": mini(_gold_limit, int(state["gold"]) + _gold_reward),
		"commander": state["commander"],
		"commandPolicy": state["commandPolicy"],
		"party": party.values().duplicate(true),
		"warehouse": state["warehouse"].duplicate(true)
	}
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
