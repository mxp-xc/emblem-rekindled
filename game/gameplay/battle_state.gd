# gdlint: disable=max-public-methods,max-file-lines
# Named commands and queries share the single authoritative battle state.
# Clone rules live in BattleClones; this file keeps their state/commit boundary together.
extends RefCounted

const MAX_GOLD: int = 9999999

const NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const AI = preload("res://gameplay/tactical_ai.gd")
const Deployment = preload("res://gameplay/battle_deployment.gd")
const Campaign = preload("res://gameplay/campaign_rules.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Resolution = preload("res://gameplay/combat_resolution.gd")
const UnitRecord = preload("res://gameplay/unit_record.gd")
const Progression = preload("res://gameplay/unit_progression.gd")
const MapRules = preload("res://gameplay/map_rules.gd")
const Inventory = preload("res://gameplay/unit_inventory.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const MapAttack = preload("res://gameplay/map_attack.gd")
const Clones = preload("res://gameplay/battle_clones.gd")
const Summons = preload("res://gameplay/battle_summons.gd")
const Statistics = preload("res://gameplay/chapter_statistics.gd")
const STAT_ORDER: Array[String] = [
	"strength", "skill", "speed", "defense", "magic", "luck", "maxHp", "move"
]

var phase: int = 0
var round_number: int = 1
var commander_id: int = -1
var command_policy: int = 0
var chapter_stats: Dictionary = Statistics.fresh()
var gold: int = 0
var outcome: Dictionary = {}
var battle_id: String
var share_experience: bool = false
var full_growth: bool = false
var _commander_candidates: Array[int] = []
var _initial_gold: int
var _completion: Dictionary = {}
var _routes: Dictionary = {}
var _chapter_id: String
var _campaign: Dictionary = {}
var _campaign_rules: RefCounted
var _chapter_events: RefCounted
var _ai: RefCounted
var _resolution: RefCounted
var _automatic_queue: Array[int] = []
var _assignments: Dictionary = {}
var _map: Dictionary
var _initial_map: Dictionary
var _location_events: Array = []
var _alliances: Array
var _combat: RefCounted
var _inventory: RefCounted
var _movement: RefCounted
var _random_source: Callable
var _rng := RandomNumberGenerator.new()
var _next_action_id: int = 1
var _growth_rates: Dictionary = {}
var _stat_caps: Dictionary
var _progression: RefCounted
var _promotion_targets: Dictionary = {}
var _promotion_errors: Dictionary = {}
var _base_movement_costs: Array
var _unit_records: RefCounted
var _warehouse: Array = []
var _events: Dictionary = {}
var _units: Dictionary = {}
var _pending_move: Dictionary = {}
var _definitions: Dictionary = {}
var _required_ids: Array[int] = []
var _deployment_bindings: Dictionary = {}
var _deployment_order: Array[int] = []
var _map_attack: RefCounted
var _clones: RefCounted
var _clone_policy: Variant
var _clone_records: Array
var _clone_state: Dictionary = {}
var _summon_state: Dictionary = {}
var _summons: RefCounted
var _record_content: Dictionary


func _init(
	content: Dictionary,
	random_source: Callable = Callable(),
	initialize: bool = true,
	initialization_context: Variant = null
) -> void:
	_chapter_id = content["entry"]["id"]
	battle_id = content["entry"]["battleId"]
	for step: Dictionary in content["story"]["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			commander_id = int(step["defaultCommanderId"])
			break
	_initial_gold = int(content["rules"]["initialGold"])
	gold = _initial_gold
	_map = content["map"].duplicate(true)
	_initial_map = _map.duplicate(true)
	_alliances = content["rules"]["alliances"].duplicate()
	_movement = MapRules.new(_map, _alliances)
	_combat = Combat.new(content["rules"], _map["terrain"])
	_random_source = random_source
	_progression = Progression.new(content["rules"])
	_inventory = Inventory.new(_combat, _roll, _progression)
	_base_movement_costs = content["rules"]["baseMovementCosts"]
	_resolution = Resolution.new(_combat, _inventory, _roll)
	_clone_policy = content["story"].get("periodicClones")
	_clone_records = content.get("_deployments", [])
	_summon_state = content.get("_context", {}).get("summonState", {}).duplicate(true)
	if _clone_policy != null:
		_clone_state = (
			content
			. get("_context", {})
			. get("cloneState", {"nextGeneration": 1, "bindings": []})
			. duplicate(true)
		)
	_rng.randomize()
	_stat_caps = content["rules"]["statCaps"].duplicate(true)
	for row: Dictionary in content["rules"]["growthRates"]:
		_growth_rates[int(row["id"])] = row.duplicate(true)
	_bind_content(content)
	if initialize:
		var initial: Dictionary = (
			Deployment.new(content, _combat, _inventory, _roll, initialization_context).create()
		)
		_units = initial["units"]
		_definitions = initial["definitions"]
		_required_ids = initial["requiredIds"]
		_deployment_bindings = initial["bindings"]
	_reorder_units()
	_refresh_unit_records()


func deployment_bindings() -> Dictionary:
	return _deployment_bindings.duplicate()


# Rebind presentation identities after optional deployments have been resolved.
# This replaces no battle result and performs no initialization or random draw.
func adopt_content(content: Dictionary) -> void:
	_bind_content(content)
	_refresh_unit_records()


# Derived content only. Initialization owns deployment, commander, gold and RNG.
func _bind_content(content: Dictionary) -> void:
	_promotion_targets = content.get("promotionTargets", {})
	_promotion_errors = content.get("promotionErrors", {})
	_definitions.clear()
	_required_ids.clear()
	_map_attack = MapAttack.new(
		_combat, _inventory, _resolution, _map, _alliances, content.get("mapEffects")
	)
	for definition: Dictionary in content["units"]:
		var identity: int = int(definition["id"])
		_definitions[identity] = definition.duplicate(true)
		if identity not in content.get("optionalIds", []):
			_required_ids.append(identity)
	_adopt_unit_order(content)
	_commander_candidates.clear()
	for step: Dictionary in content["story"]["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			for identity: Variant in step["candidates"]:
				_commander_candidates.append(int(identity))
			break
	_routes.clear()
	for route: Dictionary in content["story"]["routeChoices"]:
		_routes[int(route["routeIndex"])] = route
	_record_content = content.duplicate()
	_location_events = content["story"].get("locationEvents", []).duplicate(true)
	var event_content: Dictionary = content.duplicate()
	event_content["map"] = _map
	_chapter_events = Events.new(event_content)
	_ai = AI.new(content)
	_clones = Clones.new(content, _combat, _inventory, _roll)
	_summons = Summons.new(content, _combat, _inventory, _roll)


func _refresh_unit_records() -> void:
	_record_content["units"] = _definitions.values()
	_unit_records = UnitRecord.new(_record_content, _combat)
	_campaign_rules = Campaign.new(_record_content, _unit_records, MAX_GOLD, _combat)


# Content supplies native as order independently from initialization's raw p order.
func _adopt_unit_order(content: Dictionary) -> void:
	_deployment_order.clear()
	for identity: Variant in content["unitOrder"]:
		_deployment_order.append(int(identity))
	_reorder_units()


func _reorder_units() -> void:
	var ordered: Dictionary = {}
	for identity: int in _deployment_order:
		if _units.has(identity):
			ordered[identity] = _units[identity]
	_units = ordered


func unit(id: int) -> Dictionary:
	return _units.get(id, {}).duplicate(true)


func unit_information(id: int, instance_id: String = "") -> Dictionary:
	var actor: Dictionary = _units.get(id, {}).duplicate(true)
	if actor.is_empty():
		return {}
	if not instance_id.is_empty() and not _inventory.equip(actor, instance_id)["ok"]:
		return {}
	return _combat.information(actor, _commander())


func snapshot() -> Dictionary:
	var state: Dictionary = {
		"phase": phase,
		"round": round_number,
		"commander": commander_id,
		"commandPolicy": command_policy,
		"chapterStats": chapter_stats.duplicate(true),
		"gold": gold,
		"outcome": outcome.duplicate(true),
		"nextActionId": _next_action_id,
		"warehouse": _warehouse.duplicate(true),
		"events": _events.duplicate(true),
		"units": _units.values().duplicate(true),
		"pending_move": _pending_move.duplicate(true)
	}
	if not _campaign.is_empty():
		state["campaign"] = _campaign.duplicate(true)
	if _clone_policy != null:
		state["cloneState"] = _clone_state.duplicate(true)
	if not _summon_state.is_empty():
		state["summonState"] = _summon_state.duplicate(true)
	return state


func begin_from_progress(progress: Dictionary) -> Dictionary:
	if not _campaign.is_empty():
		return {"ok": false, "error": "CAMPAIGN_ALREADY_ENTERED"}
	var prepared: Dictionary = _campaign_rules.prepare(progress, _units)
	if not prepared["ok"]:
		return prepared
	_units = prepared["units"]
	_warehouse = prepared["warehouse"]
	gold = prepared["gold"]
	_campaign = prepared["campaign"]
	_events = prepared["events"]
	chapter_stats = prepared["chapterStats"]
	commander_id = int(prepared.get("commander", commander_id))
	command_policy = int(prepared.get("commandPolicy", command_policy))
	return {"ok": true}


func can_save() -> bool:
	return (
		phase == 0
		and _pending_move.is_empty()
		and outcome.is_empty()
		and _campaign_rules.valid_context(_campaign)
	)


func event_completed(event_id: String) -> bool:
	return _events.get(event_id, false)


func complete_event(event_id: String) -> void:
	_events[event_id] = true


func restore_snapshot(state: Dictionary) -> Dictionary:
	if state.has("chapterStats") and not state["chapterStats"] is Dictionary:
		return _failure("INVALID_CHAPTER_STATS")
	var statistics: Dictionary = Statistics.decode(state.get("chapterStats"))
	if not statistics["ok"]:
		return statistics
	if not _campaign_rules.valid_context(state.get("campaign", {})):
		return _failure("INVALID_SAVE_CAMPAIGN")
	var summons: Dictionary = Summons.saved_bindings(
		_record_content.get("_library", {}).get("summons", {}), _clone_records, state
	)
	if not summons["ok"]:
		return summons
	var clones: Dictionary = {}
	if _clone_policy != null or state.has("cloneState"):
		clones = Clones.saved_bindings(_clone_policy, _clone_records, state)
		if not clones["ok"]:
			return clones
	if not state.get("events") is Dictionary:
		return _failure("INVALID_SAVE_EVENTS")
	for event_id: Variant in state["events"]:
		if not event_id is String or not state["events"][event_id] is bool:
			return _failure("INVALID_SAVE_EVENTS")
		if event_id.begins_with("location:"):
			var known: bool = false
			for location: Dictionary in _map.get("locations", []):
				if event_id == "location:" + location["id"]:
					known = true
					break
			if not known:
				return _failure("INVALID_SAVE_EVENTS")
	if (
		not _integer_in(state.get("phase"), 0, 0)
		or not _integer_in(state.get("round"), 1, 2147483647)
		or not (
			_integer_in(state.get("commander"), -1, -1) or _declared_unit_id(state.get("commander"))
		)
		or not _integer_in(state.get("nextActionId"), 1, 2147483647)
	):
		return _failure("INVALID_SAVE_FLOW")
	if (
		not state.get("pending_move") is Dictionary
		or not state["pending_move"].is_empty()
		or not state.get("units") is Array
		or state["units"].size() > _definitions.size()
		or not state.get("warehouse") is Array
		or state["warehouse"].size() > Inventory.WAREHOUSE_CAPACITY
	):
		return _failure("INVALID_SAVE_STATE")
	if not state.get("outcome", {}) is Dictionary or not state.get("outcome", {}).is_empty():
		return _failure("INVALID_SAVE_OUTCOME")
	if not _integer_in(state.get("gold", _initial_gold), 0, MAX_GOLD):
		return _failure("INVALID_SAVE_GOLD")
	var candidate: Dictionary = {}
	var occupied: Dictionary = {}
	var held_ids: Dictionary = {}
	for value: Variant in state["units"]:
		if not value is Dictionary or not _declared_unit_id(value.get("id")):
			return _failure("INVALID_SAVE_UNIT")
		var id: int = int(value["id"])
		if not _definitions.has(id) or candidate.has(id):
			return _failure("INVALID_SAVE_IDENTITY")
		var decoded: Dictionary = _unit_records.decode(value, held_ids)
		if not decoded["ok"]:
			return decoded
		var current: Dictionary = decoded["unit"]
		var cell := Vector2i(current["x"], current["y"])
		if _alive(current):
			if occupied.has(cell):
				return _failure("INVALID_SAVE_OCCUPANCY")
			occupied[cell] = id
		candidate[id] = current
	for identity: int in _required_ids:
		if not candidate.has(identity):
			return _failure("INVALID_SAVE_IDENTITY")
	var campaign: Dictionary = state.get("campaign", {})
	if campaign.has("chapterResult"):
		var party: Array = []
		for actor: Dictionary in candidate.values():
			if actor["formal"]:
				party.append(actor)
		var result: Dictionary = Statistics.validate_result(
			campaign["chapterResult"], party, statistics["stats"], true
		)
		if not result["ok"]:
			return result
	var warehouse: Array = state["warehouse"].duplicate(true)
	if not _unit_records.validate_inventory(warehouse, held_ids):
		return _failure("INVALID_SAVE_WAREHOUSE")
	if (
		not _integer_in(state.get("commandPolicy", 0), 0, 5)
		or int(state.get("commandPolicy", 0)) not in [0, 1, 4, 5]
	):
		return _failure("INVALID_SAVE_COMMAND")
	# A saved selection remains historical after death; new selections require _alive.
	var commander: int = int(state["commander"])
	if (
		commander >= 0
		and (
			not candidate.has(commander)
			or not candidate[commander]["formal"]
			or candidate[commander]["faction"] != 0
		)
	):
		return _failure("INVALID_SAVE_COMMANDER")
	if not _chapter_events.outcome(candidate.values(), int(state["round"])).is_empty():
		return _failure("SAVE_NOT_STABLE")
	outcome.clear()
	_completion.clear()
	_automatic_queue.clear()
	_assignments.clear()
	_units = candidate
	_reorder_units()
	if _clone_policy != null:
		_clone_state = {"nextGeneration": clones["nextGeneration"], "bindings": clones["bindings"]}
	_summon_state = (
		{"nextGeneration": summons["nextGeneration"], "bindings": summons["bindings"]}
		if state.has("summonState")
		else {}
	)
	_campaign = state.get("campaign", {}).duplicate(true)
	for field: String in ["route", "worldStep"]:
		if _campaign.has(field):
			_campaign[field] = int(_campaign[field])
	_events = state["events"].duplicate(true)
	# Rules retain the map and terrain arrays: reset their contents in place.
	for field: String in ["tiles", "terrain"]:
		_map[field].assign(_initial_map[field].duplicate(true))
	for group: String in _map["movementCosts"]:
		_map["movementCosts"][group].assign(_initial_map["movementCosts"][group].duplicate(true))
	for location: Dictionary in _map.get("locations", []):
		if location["kind"] == "chest" and event_completed("location:" + location["id"]):
			_project_opened_location(location)
	_warehouse = warehouse
	phase = int(state["phase"])
	round_number = int(state["round"])
	commander_id = commander
	gold = int(state.get("gold", _initial_gold))
	command_policy = int(state.get("commandPolicy", 0))
	chapter_stats = statistics["stats"]
	_next_action_id = int(state["nextActionId"])
	_pending_move.clear()
	return {"ok": true}


func _declared_unit_id(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= 0
		and _definitions.has(int(value))
	)


func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and float(value) >= minimum
		and float(value) <= maximum
	)


# Shared unit-operation gate; moving and automatic actions have stricter contracts.
func _action_error(id: int) -> String:
	if not _can_act(id):
		return "UNIT_NOT_READY"
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return "ACTION_PENDING"
	return ""


func actions_for(id: int) -> Array[String]:
	if not _action_error(id).is_empty():
		return []
	var actions: Array[String] = ["wait"]
	if phase == 0 and not _chest_at(id).is_empty():
		actions.push_front("open_chest")
	if phase == 0 and not _visit_at(id).is_empty():
		actions.push_front("visit_location")
	if _pending_move.is_empty():
		actions.push_front("move")
	elif not movement_committed(id):
		actions.append("cancel_move")
	for held: Dictionary in _units[id]["inventory"]:
		if not staff_targets(id, held["id"]).is_empty() or can_summon(id, held["id"]):
			actions.append("heal")
			break
	if not trade_targets(id).is_empty():
		actions.append("trade")
	if not attack_weapons(id).is_empty():
		actions.append("attack")
	if not item_options(id).is_empty():
		actions.append("inventory")
	return actions


func movement_field(id: int) -> Dictionary:
	if not _units.has(id) or not _alive(_units[id]):
		return {}
	return _movement.field(_units[id], _units.values())


func preview_move(id: int, destination: Vector2i) -> Dictionary:
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	var occupant: Dictionary = _movement.unit_at(_units.values(), destination)
	if not occupant.is_empty() and occupant["id"] != id:
		return _failure("DESTINATION_OCCUPIED")
	var field: Dictionary = movement_field(id)
	if not field.has(destination):
		return _failure("OUT_OF_RANGE")
	var actor: Dictionary = _units[id]
	var origin := Vector2i(actor["x"], actor["y"])
	var path: Array[Vector2i] = [destination]
	var cell := destination
	while cell != origin:
		var best := cell
		var best_value: int = field[cell]
		for direction: Vector2i in NEIGHBORS:
			var neighbor := cell + direction
			if int(field.get(neighbor, 0)) > best_value:
				best = neighbor
				best_value = field[neighbor]
		if best == cell:
			return _failure("NO_PATH")
		cell = best
		path.insert(0, cell)
	return {"ok": true, "path": path, "cost": actor["move"] + 1 - int(field[destination])}


func move_unit(id: int, destination: Vector2i) -> Dictionary:
	if not _pending_move.is_empty():
		return _failure("ACTION_PENDING")
	var preview: Dictionary = preview_move(id, destination)
	if not preview["ok"]:
		return preview
	var actor: Dictionary = _units[id]
	_pending_move = {"id": id, "origin": Vector2i(actor["x"], actor["y"])}
	actor["x"] = destination.x
	actor["y"] = destination.y
	return {"ok": true, "kind": "move", "unit": id, "path": preview["path"]}


func cancel_move() -> Dictionary:
	if _pending_move.is_empty():
		return _failure("NO_ACTION_PENDING")
	if movement_committed(int(_pending_move["id"])):
		return _failure("MOVEMENT_COMMITTED")
	var actor: Dictionary = _units[_pending_move["id"]]
	var origin: Vector2i = _pending_move["origin"]
	actor["x"] = origin.x
	actor["y"] = origin.y
	_pending_move.clear()
	return {"ok": true, "kind": "cancel", "unit": actor["id"]}


func wait_unit(id: int) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	var result: Dictionary = {"ok": true, "kind": "wait", "unit": id}
	if phase == 0:
		var location: Dictionary = _location_at(id, "waitPickup")
		if not location.is_empty():
			var selected: Dictionary = _visit_reward(location.get("reward"))
			if not selected["ok"]:
				return selected
			var reward: Dictionary = selected["reward"]
			if reward["kind"] == "empty":
				_events["location:" + location["id"]] = true
				result["location"] = {
					"ok": true,
					"actor": id,
					"locationId": location["id"],
					"claimed": true,
					"reward": reward
				}
			else:
				result["location"] = _claim_location_item(id, location, reward)
	_units[id]["action"] = 2
	_pending_move.clear()
	_check_outcome()
	return result


func _chest_at(id: int) -> Dictionary:
	if not _units.has(id):
		return {}
	var actor: Dictionary = _units[id]
	for location: Dictionary in _map.get("locations", []):
		if (
			location["kind"] == "chest"
			and int(location["position"][0]) == actor["x"]
			and int(location["position"][1]) == actor["y"]
			and not event_completed("location:" + location["id"])
		):
			return location
	return {}


func _visit_at(id: int) -> Dictionary:
	return _location_at(id, "visit")


func _location_at(id: int, kind: String) -> Dictionary:
	if not _units.has(id):
		return {}
	var actor: Dictionary = _units[id]
	for location: Dictionary in _map.get("locations", []):
		if (
			location["kind"] == kind
			and int(location["position"][0]) == actor["x"]
			and int(location["position"][1]) == actor["y"]
			and not event_completed("location:" + location["id"])
		):
			return location
	return {}


func visit_location(id: int) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	var location: Dictionary = _visit_at(id)
	if phase != 0 or location.is_empty():
		return _failure("NO_VISIT_LOCATION")
	var selected: Dictionary = _visit_reward(location.get("reward"))
	if not selected["ok"]:
		return selected
	var actor: Dictionary = _units[id]
	var reward: Dictionary = selected["reward"]
	var result: Dictionary = {"ok": true, "kind": "visit", "actor": id, "claimed": true}
	match reward["kind"]:
		"item":
			result = _claim_location_item(id, location, reward)
			result["kind"] = "visit"
		"gold":
			var previous: int = gold
			gold = mini(MAX_GOLD, gold + int(reward["amount"]))
			result["reward"] = {"kind": "gold", "amount": gold - previous}
		"empty":
			result["reward"] = {"kind": "empty"}
	if result["claimed"]:
		_events["location:" + location["id"]] = true
	actor["action"] = 2
	_pending_move.clear()
	_check_outcome()
	return result


func _claim_location_item(id: int, location: Dictionary, reward: Dictionary) -> Dictionary:
	var actor: Dictionary = _units[id]
	var result: Dictionary = {
		"ok": true, "actor": id, "locationId": location["id"], "claimed": true
	}
	var destination: String = (
		"inventory" if actor["inventory"].size() < Inventory.BAG_CAPACITY else "warehouse"
	)
	if destination == "warehouse" and _warehouse.size() >= Inventory.WAREHOUSE_CAPACITY:
		result["claimed"] = false
		result["reason"] = "WAREHOUSE_FULL"
		return result
	var template_id: int = int(reward["templateId"])
	var held: Dictionary = {
		"id": "%s:%s:location:%s" % [_chapter_id, battle_id, location["id"]],
		"templateId": template_id,
		"durability": int(_combat.item_definition(template_id)["defaultDurability"])
	}
	if destination == "inventory":
		actor["inventory"].append(held)
	else:
		_warehouse.append(held)
	result["rewards"] = {
		"loot": [{"unit": id, "item": held.duplicate(true), "destination": destination}]
	}
	result["reward"] = reward.duplicate(true)
	_events["location:" + location["id"]] = true
	return result


func _visit_reward(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("INVALID_VISIT_REWARD")
	var template_id: int = -1
	var limit: int = 0
	match value.get("kind"):
		"item":
			if value.size() != 2 or not _integer_in(value.get("templateId"), 1, 2147483647):
				return _failure("INVALID_VISIT_REWARD")
			template_id = int(value["templateId"])
		"gold":
			if value.size() != 2 or not _integer_in(value.get("amount"), 1, MAX_GOLD):
				return _failure("INVALID_VISIT_REWARD")
			return {"ok": true, "reward": {"kind": "gold", "amount": int(value["amount"])}}
		"weightedItem":
			if (
				value.size() != 2
				or not value.get("weightedChoices") is Array
				or value["weightedChoices"].is_empty()
			):
				return _failure("INVALID_VISIT_REWARD")
			var total: int = 0
			for choice: Variant in value["weightedChoices"]:
				if (
					not choice is Dictionary
					or choice.size() != 2
					or not _integer_in(choice.get("weight"), 1, 100)
					or not _integer_in(choice.get("templateId"), 1, 2147483647)
					or _combat.item_definition(int(choice["templateId"])).is_empty()
				):
					return _failure("INVALID_VISIT_REWARD")
				total += int(choice["weight"])
			if total > 100:
				return _failure("INVALID_VISIT_REWARD")
			limit = 100
		"goldRange":
			if (
				value.size() != 3
				or not _integer_in(value.get("minimum"), 1, MAX_GOLD)
				or not _integer_in(value.get("maximum"), 1, MAX_GOLD)
				or value["minimum"] > value["maximum"]
			):
				return _failure("INVALID_VISIT_REWARD")
			limit = int(value["maximum"]) - int(value["minimum"]) + 1
		_:
			return _failure("INVALID_VISIT_REWARD")
	if template_id >= 0:
		if _combat.item_definition(template_id).is_empty():
			return _failure("INVALID_VISIT_REWARD")
		return {"ok": true, "reward": {"kind": "item", "templateId": template_id}}
	# A bad injected source must fail before committing action, inventory or location state.
	var draw: Variant = (
		_random_source.call(limit) if _random_source.is_valid() else _rng.randi_range(0, limit - 1)
	)
	if not _integer_in(draw, 0, limit - 1):
		return _failure("INVALID_RANDOM_RESULT")
	if value["kind"] == "goldRange":
		return {"ok": true, "reward": {"kind": "gold", "amount": int(draw) + int(value["minimum"])}}
	var remaining: int = int(draw)
	for choice: Dictionary in value["weightedChoices"]:
		remaining -= int(choice["weight"])
		if remaining < 0:
			return {"ok": true, "reward": {"kind": "item", "templateId": int(choice["templateId"])}}
	return {"ok": true, "reward": {"kind": "empty"}}


func open_chest(id: int) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	var location: Dictionary = _chest_at(id)
	if phase != 0 or location.is_empty():
		return _failure("NO_CHEST")
	var fixed_template_id: int = -1
	var gold_reward: int = -1
	if location.has("reward"):
		var fixed: Variant = location["reward"]
		if (
			location.has("weightedChoices")
			or location.has("emptyWeight")
			or not fixed is Dictionary
			or fixed.get("kind") not in ["item", "goldRange"]
		):
			return _failure("INVALID_CHEST_REWARD")
		var selected: Dictionary = _visit_reward(fixed)
		if not selected["ok"]:
			return (
				selected if fixed.get("kind") == "goldRange" else _failure("INVALID_CHEST_REWARD")
			)
		if selected["reward"]["kind"] == "gold":
			gold_reward = int(selected["reward"]["amount"])
		else:
			fixed_template_id = int(selected["reward"]["templateId"])
	var actor: Dictionary = _units[id]
	var result: Dictionary = {"ok": true, "kind": "open_chest", "actor": id, "claimed": false}
	var empty_reward: bool = false
	if location.has("emptyWeight"):
		var choices: Variant = location.get("weightedChoices")
		if not _integer_in(location["emptyWeight"], 1, 99) or not choices is Array:
			return _failure("INVALID_CHEST_REWARD")
		var total: int = int(location["emptyWeight"])
		for choice: Variant in choices:
			if not choice is Dictionary or not _integer_in(choice.get("weight"), 1, 100):
				return _failure("INVALID_CHEST_REWARD")
			total += int(choice["weight"])
		if total != 100:
			return _failure("INVALID_CHEST_REWARD")
		var selected: Dictionary = _visit_reward(
			{"kind": "weightedItem", "weightedChoices": choices}
		)
		if not selected["ok"]:
			return selected
		empty_reward = selected["reward"]["kind"] == "empty"
		if not empty_reward:
			fixed_template_id = int(selected["reward"]["templateId"])
	var destination: String = "inventory"
	if actor["inventory"].size() >= Inventory.BAG_CAPACITY:
		destination = "warehouse"
	if (
		not empty_reward
		and gold_reward < 0
		and destination == "warehouse"
		and _warehouse.size() >= Inventory.WAREHOUSE_CAPACITY
	):
		result["reason"] = "WAREHOUSE_FULL"
	else:
		var template_id: int = fixed_template_id
		if template_id < 0 and not empty_reward and gold_reward < 0:
			var total: int = 0
			for choice: Dictionary in location["weightedChoices"]:
				total += int(choice["weight"])
			var draw: int = _roll(total)
			for choice: Dictionary in location["weightedChoices"]:
				draw -= int(choice["weight"])
				if draw < 0:
					template_id = int(choice["templateId"])
					break
		var held: Dictionary = (
			{}
			if empty_reward or gold_reward >= 0
			else {
				"id": "%s:%s:location:%s" % [_chapter_id, battle_id, location["id"]],
				"templateId": template_id,
				"durability": int(_combat.item_definition(template_id)["defaultDurability"])
			}
		)
		if gold_reward >= 0:
			var previous_gold: int = gold
			gold = mini(MAX_GOLD, gold + gold_reward)
			result["reward"] = {"kind": "gold", "amount": gold - previous_gold}
		elif not empty_reward and destination == "inventory":
			actor["inventory"].append(held)
		elif not empty_reward:
			_warehouse.append(held)
		_events["location:" + location["id"]] = true
		_project_opened_location(location)
		result["claimed"] = true
		if not empty_reward and gold_reward < 0:
			result["rewards"] = {
				"loot": [{"unit": id, "item": held.duplicate(true), "destination": destination}]
			}
		for event: Dictionary in _location_events:
			if event["locationId"] != location["id"]:
				continue
			var leader: Dictionary = _units.get(int(event["unitIds"][0]), {})
			if not leader.is_empty() and leader["hp"] > 0 and not leader["visible"]:
				var focus := Vector2i(leader["x"], leader["y"])
				var arrivals: Array = _chapter_events.reinforce(_units.values(), event["unitIds"])
				result["locationEvent"] = {
					"focus": focus, "arrivals": arrivals, "sequence": event.get("sequence", "")
				}
			break
	actor["action"] = 2
	_pending_move.clear()
	_check_outcome()
	return result


func _project_opened_location(location: Dictionary) -> void:
	var cell := Vector2i(int(location["position"][0]), int(location["position"][1]))
	var variant: Dictionary = _map["tileVariants"][location["openedVariant"]]
	_map["tiles"][cell.y][cell.x] = int(variant["tileId"])
	_map["terrain"][cell.y][cell.x] = int(variant["terrain"])
	for group: String in _map["movementCosts"]:
		_map["movementCosts"][group][cell.y][cell.x] = int(variant["movementCosts"][group])


func map_state() -> Dictionary:
	var overlays: Array[Dictionary] = []
	for location: Dictionary in _map.get("locations", []):
		if location["kind"] == "chest" and event_completed("location:" + location["id"]):
			overlays.append(
				{
					"cell": Vector2i(int(location["position"][0]), int(location["position"][1])),
					"texture": _map["tileVariants"][location["openedVariant"]]["texture"]
				}
			)
	return {"map": _map.duplicate(true), "overlays": overlays}


func equip_unit(id: int, instance_id: String) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	return _inventory.equip(_units[id], instance_id)


func item_options(id: int) -> Dictionary:
	if not _action_error(id).is_empty():
		return {}
	var options: Dictionary = {}
	for operation: String in ["use", "equip", "discard"]:
		var candidates: Array[Dictionary] = _inventory.candidates(_units[id], operation)
		if not candidates.is_empty():
			options[operation] = candidates
	return options


func discard_item(id: int, instance_id: String) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	return _inventory.discard(_units[id], instance_id)


func attack_weapons(id: int) -> Array[Dictionary]:
	if not _action_error(id).is_empty():
		return []
	return _map_attack.weapons(_units[id], _units.values(), round_number, _commander())


func attack_options(id: int, instance_id: String) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	return _map_attack.options(_units[id], instance_id, _units.values(), round_number)


func map_attack_preview(id: int, instance_id: String, primary_id: int = -1) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	return _map_attack.prepare(
		_units[id], instance_id, _units.values(), round_number, _commander(), primary_id
	)


func cast_map_attack(id: int, instance_id: String, primary_id: int = -1) -> Dictionary:
	var preview: Dictionary = map_attack_preview(id, instance_id, primary_id)
	if not preview["ok"]:
		return preview
	var promotion_check: Dictionary = _promotion_preflight()
	if not promotion_check["ok"]:
		return promotion_check
	var result: Dictionary = _map_attack.resolve(preview, _commander())
	for current: Dictionary in result["changes"]:
		_units[int(current["id"])] = current
	result.erase("changes")
	_pending_move.clear()
	var actor: Dictionary = _units[id]
	var last: Dictionary = _units[int(result["targetIds"][-1])]
	result["rewards"] = {"experience": {}, "loot": []}
	if actor["faction"] != 2:
		var prior_defeats: Array = []
		for target_id: Variant in result["targetIds"].slice(0, -1):
			if _units[int(target_id)]["hp"] <= 0:
				prior_defeats.append(int(target_id))
		result["rewards"]["experience"] = _award_experience(
			actor, last, _experience_kill(last, result["anyKill"], prior_defeats), true, false
		)
	var defeats: Dictionary = _finish_defeats(result["targetIds"])
	result.merge(defeats, true)
	result["id"] = _next_action_id
	_next_action_id += 1
	_check_outcome()
	return result


func attack_targets(id: int, instance_id: String = "") -> Array[int]:
	var targets: Array[int] = []
	if not _units.has(id):
		return targets
	var actor: Dictionary = _units[id].duplicate(true)
	if not instance_id.is_empty() and not _inventory.equip(actor, instance_id)["ok"]:
		return targets
	return _map_attack.targets(actor, _units.values(), round_number)


func attack_field(id: int, instance_id: String = "") -> Dictionary:
	if not _units.has(id):
		return {}
	var actor: Dictionary = _units[id].duplicate(true)
	if not instance_id.is_empty() and not _inventory.equip(actor, instance_id)["ok"]:
		return {}
	return _map_attack.field(actor, _combat.weapon_id(actor))


func trade_field(id: int) -> Dictionary:
	var field: Dictionary = {}
	if not _units.has(id):
		return field
	var actor: Dictionary = _units[id]
	for direction: Vector2i in NEIGHBORS:
		var cell := Vector2i(actor["x"], actor["y"]) + direction
		if cell.x >= 0 and cell.y >= 0 and cell.x < _map["width"] and cell.y < _map["height"]:
			field[cell] = 1
	return field


func combat_forecast(id: int, target_id: int) -> Dictionary:
	if (
		not _units.has(id)
		or not _units.has(target_id)
		or not _map_attack.target_valid(_units[id], _units[target_id])
	):
		return _failure("INVALID_ATTACK_TARGET")
	var result: Dictionary = _combat.forecast(_units[id], _units[target_id], _commander())
	result["ok"] = true
	return result


func attack_unit(id: int, target_id: int) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	if _combat.action_mode(_combat.weapon_id(_units[id])) != "battle_clip":
		return _failure("INVALID_ACTION_MODE")
	if not _units.has(target_id) or not _map_attack.target_valid(_units[id], _units[target_id]):
		return _failure("INVALID_ATTACK_TARGET")
	var promotion_check: Dictionary = _promotion_preflight()
	if not promotion_check["ok"]:
		return promotion_check
	promotion_check = _promotion_drop_preflight(id, target_id)
	if not promotion_check["ok"]:
		return promotion_check
	var actor: Dictionary = _units[id]
	var target: Dictionary = _units[target_id]
	var preview: Dictionary = attack_preview(id, target_id)
	var resolution: Dictionary = _resolution.resolve(actor, target, _commander())
	var resolved_weapons: Dictionary = {
		str(id): _combat.weapon_id(actor), str(target_id): _combat.weapon_id(target)
	}
	var broken_items: Array[Dictionary] = _inventory.broken_items(
		resolution["participants"], _units
	)
	var strikes: Array[Dictionary] = resolution["strikes"]
	actor["action"] = 2
	_pending_move.clear()
	for unit_state: Dictionary in [actor, target]:
		_inventory.cleanup_combat(unit_state)
	var rewards: Dictionary = _settle_combat(actor, target, strikes)
	var defeats: Dictionary = _finish_defeats([id, target_id])
	var story_events: Dictionary = _chapter_events.combat_events(
		resolution["participants"], defeats["retirements"], _events
	)
	for retirement: Dictionary in story_events["retirements"]:
		if not retirement.has("revealUnitIds"):
			continue
		var queue: Array[Dictionary] = []
		for identity: Variant in retirement["revealUnitIds"]:
			var unit: Dictionary = _units.get(int(identity), {})
			if not unit.is_empty() and not unit["visible"] and unit["hp"] > 0:
				queue.append({"unit": int(identity), "from": Vector2i(unit["x"], unit["y"])})
		_chapter_events.reinforce(_units.values(), retirement["revealUnitIds"])
		for arrival: Dictionary in queue:
			var unit: Dictionary = _units[arrival["unit"]]
			arrival["to"] = Vector2i(unit["x"], unit["y"])
			arrival["revealed"] = unit["visible"]
		retirement.erase("revealUnitIds")
		retirement["arrivalQueue"] = queue
	for event_id: String in story_events["completed"]:
		_events[event_id] = true
	for identity: int in story_events["flags"]:
		_units[identity]["flags"] |= int(story_events["flags"][identity])
	var result := {
		"ok": true,
		"kind": "combat",
		"id": _next_action_id,
		"actor": id,
		"target": target_id,
		"participants": resolution["participants"],
		"forecasts": preview["forecasts"],
		"resolvedWeapons": resolved_weapons,
		"brokenItems": broken_items,
		"strikes": strikes,
		"rewards": rewards,
		"storyBefore": story_events["before"],
		"retirements": story_events["retirements"],
		"revivals": defeats["revivals"]
	}
	_next_action_id += 1
	_check_outcome()
	return result


func attack_preview(id: int, target_id: int) -> Dictionary:
	var forecast: Dictionary = combat_forecast(id, target_id)
	if not forecast["ok"]:
		return forecast
	var actor: Dictionary = _units[id]
	var target: Dictionary = _units[target_id]
	var counter: Dictionary = _combat.forecast(target, actor, _commander())
	forecast["canAttack"] = true
	counter["canAttack"] = forecast["canCounter"]
	return {
		"ok": true,
		"participants": [actor.duplicate(true), target.duplicate(true)],
		"forecasts": {str(id): forecast, str(target_id): counter}
	}


func _commander() -> Dictionary:
	if _units.has(commander_id) and _alive(_units[commander_id]):
		return _units[commander_id]
	return {}


func _roll(limit: int) -> int:
	if _random_source.is_valid():
		var value: int = _random_source.call(limit)
		assert(
			value >= 0 and value < limit,
			"Random source must return a value inside its requested range"
		)
		return value
	return _rng.randi_range(0, limit - 1)


func _can_act(id: int) -> bool:
	return (
		outcome.is_empty()
		and _units.has(id)
		and _alive(_units[id])
		and _units[id]["faction"] == phase
		and _units[id]["action"] == 0
	)


func _alive(actor: Dictionary) -> bool:
	return actor["visible"] and actor["hp"] > 0


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}


func configure_commander(id: int, follow: bool, defend: bool) -> Dictionary:
	if (
		not outcome.is_empty()
		or phase != 0
		or not _pending_move.is_empty()
		or not command_configuration()["candidates"].any(
			func(candidate: Dictionary) -> bool: return candidate["id"] == id
		)
	):
		return _failure("INVALID_COMMANDER")
	commander_id = id
	command_policy = (1 if follow else 0) | (4 if defend else 0)
	return {"ok": true}


func command_configuration() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var ids: Array = _units.keys() if event_completed("opening") else _commander_candidates
	for id: int in ids:
		var actor: Dictionary = _units.get(id, {})
		if actor.get("formal", false) and actor["faction"] == 0 and _alive(actor):
			candidates.append({"id": id, "name": actor["name"]})
	return {"commander": commander_id, "policy": command_policy, "candidates": candidates}


func _settle_combat(
	actor: Dictionary, target: Dictionary, strikes: Array[Dictionary]
) -> Dictionary:
	var rewards: Dictionary = {"experience": {}, "loot": []}
	var dead: Dictionary = actor if actor["hp"] <= 0 else (target if target["hp"] <= 0 else {})
	if not dead.is_empty() and dead["faction"] == 2:
		var killer: Dictionary = target if dead == actor else actor
		var recipient: Dictionary = _reward_recipient(killer)
		if not recipient.is_empty():
			var retain_source: bool = (
				dead["dropTemplateId"] != 80 and not _revival_item(dead).is_empty()
			)
			var held_ids: Dictionary = {}
			if retain_source:
				for owner: Dictionary in _units.values():
					for held: Dictionary in owner["inventory"]:
						held_ids[held["id"]] = true
				for held: Dictionary in _warehouse:
					held_ids[held["id"]] = true
			var loot: Dictionary = _inventory.transfer_drop(
				dead, recipient, _warehouse, retain_source, held_ids
			)
			if not loot.is_empty():
				rewards["loot"].append(loot)
	if not dead.is_empty() and dead["faction"] != 2:
		return rewards
	var fighter: Dictionary = target if phase == 2 else actor
	var opponent: Dictionary = actor if phase == 2 else target
	var recipient: Dictionary = _reward_recipient(fighter)
	if recipient.is_empty():
		return rewards
	var hit: bool = false
	for strike: Dictionary in strikes:
		if strike["hit"] and _units[strike["attacker"]]["faction"] != 2:
			hit = true
	rewards["experience"] = _award_experience(
		recipient,
		opponent,
		_experience_kill(opponent, not dead.is_empty(), []),
		hit,
		fighter["faction"] == 1
	)
	return rewards


func _experience_kill(target: Dictionary, killed: bool, prior_defeats: Array) -> bool:
	if not killed or int(target["classGroup"]) != 10:
		return killed
	for unit: Dictionary in _units.values():
		if unit["classGroup"] == 10 and unit["id"] != target["id"]:
			if (int(unit["flags"]) & 64) == 0 and unit["id"] not in prior_defeats:
				return false
	return true


func _reward_recipient(fighter: Dictionary) -> Dictionary:
	if fighter["hp"] <= 0 or fighter["faction"] == 2:
		return {}
	if fighter["faction"] == 1:
		return {} if fighter["classGroup"] in [7, 8, 9] else _commander()
	return fighter


func _award_experience(
	actor: Dictionary, target: Dictionary, killed: bool, hit: bool, borrowed: bool
) -> Dictionary:
	var commander: Dictionary = _commander().duplicate(true)
	var amount: int = _combat.experience_gain(actor, target, killed, hit, borrowed, commander)
	var recipients: Array[Dictionary] = []
	if share_experience and actor["faction"] == 0:
		for recipient: Dictionary in _units.values():
			if (
				recipient["id"] != actor["id"]
				and recipient["faction"] == 0
				and recipient["formal"]
				and recipient["visible"]
				and recipient["hp"] > 0
				and recipient["level"] < 20
				and recipient["classGroup"] not in [7, 8, 9]
			):
				var shared_amount: int = _combat.experience_gain(
					recipient, target, killed, hit, borrowed, commander
				)
				if shared_amount > 0:
					recipients.append({"unit": recipient, "amount": shared_amount})
	if amount <= 0 and recipients.is_empty():
		return {}
	var reward: Dictionary = _gain_experience(actor, amount)
	if share_experience and actor["faction"] == 0:
		var shared: Array[Dictionary] = []
		for entry: Dictionary in recipients:
			shared.append(_gain_experience(entry["unit"], entry["amount"]))
		reward["shared"] = shared
	return reward


func _gain_experience(actor: Dictionary, amount: int) -> Dictionary:
	var before: int = int(actor["experience"])
	actor["experience"] = (before + amount) % 100
	var growth: Dictionary = {}
	if before + amount >= 100:
		actor["level"] += 1
		var rates: Dictionary = _growth_rates[int(actor["growthTemplateId"])]
		for stat: String in STAT_ORDER:
			var increment: int = 1 if full_growth or _roll(100) < int(rates[stat]) else 0
			var value: int = int(
				actor[stat] if stat in ["maxHp", "move"] else actor["attributes"][stat]
			)
			increment = mini(increment, maxi(0, int(_stat_caps[stat]) - value))
			if stat in ["maxHp", "move"]:
				actor[stat] += increment
			else:
				actor["attributes"][stat] += increment
			growth[stat] = increment
	var promotion: Dictionary = {}
	if not growth.is_empty() and _progression.eligible(actor, true):
		for held: Dictionary in actor["inventory"]:
			if held["templateId"] == 76 and held["durability"] > 0:
				promotion = _promote(actor, held["id"])
				break
	var result: Dictionary = {
		"unit": actor["id"],
		"amount": amount,
		"before": before,
		"after": actor["experience"],
		"level": actor["level"],
		"growth": growth
	}
	if not promotion.is_empty():
		result["promotion"] = promotion
	return result


func healing_field(id: int, instance_id: String) -> Dictionary:
	var field: Dictionary = {}
	if not _units.has(id):
		return field
	var actor: Dictionary = _units[id]
	var held: Dictionary = _inventory.held_item(actor, instance_id)
	if not _inventory.can_heal_with(actor, held):
		return field
	return _item_field(actor, int(held["templateId"]))


func _item_field(actor: Dictionary, template: int) -> Dictionary:
	var field: Dictionary = {}
	if template <= 0 or _combat.item_definition(template)["maxRange"] == 100:
		return field
	for y: int in range(int(_map["height"])):
		for x: int in range(int(_map["width"])):
			if _combat.in_range(actor, {"x": x, "y": y}, template):
				field[Vector2i(x, y)] = 1
	return field


func heal_targets(id: int, instance_id: String) -> Array[int]:
	var targets: Array[int] = []
	if not _units.has(id):
		return targets
	var actor: Dictionary = _units[id]
	for candidate: Dictionary in _units.values():
		if (
			_alive(candidate)
			and _alliances[actor["faction"]] == _alliances[candidate["faction"]]
			and _inventory.can_heal(actor, candidate, instance_id)
		):
			targets.append(candidate["id"])
	return targets


func heal_unit(id: int, target_id: int, instance_id: String) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	if target_id not in heal_targets(id, instance_id):
		return _failure("INVALID_HEAL_TARGET")
	var promotion_check: Dictionary = _promotion_preflight()
	if not promotion_check["ok"]:
		return promotion_check
	var actor: Dictionary = _units[id]
	var result: Dictionary = _inventory.heal(actor, _units[target_id], instance_id)
	if not result["ok"]:
		return result
	result["rewards"] = {
		"experience":
		_award_experience(actor, {}, false, true, false) if actor["faction"] == 0 else {},
		"loot": []
	}
	actor["action"] = 2
	_pending_move.clear()
	_check_outcome()
	return result


func staff_mode(id: int, instance_id: String) -> String:
	if not _units.has(id):
		return ""
	var actor: Dictionary = _units[id]
	var held: Dictionary = _inventory.held_item(actor, instance_id)
	if _inventory.can_heal_with(actor, held):
		return "heal"
	if _inventory.can_summon_with(actor, held):
		return "summon"
	if (
		not held.is_empty()
		and held["durability"] > 0
		and held["templateId"] in [57, 58]
		and (int(actor["equipMask"]) & 32) != 0
	):
		return "repair" if held["templateId"] == 57 else "teleport"
	return ""


func staff_field(id: int, instance_id: String) -> Dictionary:
	if staff_mode(id, instance_id) in ["heal", "repair", "teleport"]:
		return _item_field(
			_units[id], int(_inventory.held_item(_units[id], instance_id)["templateId"])
		)
	return {}


func staff_targets(id: int, instance_id: String) -> Array[int]:
	var mode: String = staff_mode(id, instance_id)
	if mode == "heal":
		return heal_targets(id, instance_id)
	var targets: Array[int] = []
	if mode not in ["repair", "teleport"]:
		return targets
	var actor: Dictionary = _units[id]
	for candidate: Dictionary in _units.values():
		if (
			candidate["visible"]
			and candidate["id"] != id
			and _alliances[int(candidate["faction"])] == _alliances[int(actor["faction"])]
			and (
				(
					absi(int(candidate["x"]) - int(actor["x"]))
					+ absi(int(candidate["y"]) - int(actor["y"]))
				)
				== 1
			)
		):
			targets.append(int(candidate["id"]))
	return targets


func repair_options(id: int, target_id: int, instance_id: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if staff_mode(id, instance_id) == "repair" and target_id in staff_targets(id, instance_id):
		for held: Dictionary in _units[target_id]["inventory"]:
			items.append(held.duplicate(true))
	return items


func repair_unit(id: int, target_id: int, instance_id: String, repaired_id: String) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	if staff_mode(id, instance_id) != "repair" or target_id not in staff_targets(id, instance_id):
		return _failure("INVALID_REPAIR_TARGET")
	var repaired: Dictionary = _inventory.held_item(_units[target_id], repaired_id)
	if repaired.is_empty():
		return _failure("ITEM_NOT_OWNED")
	var checked: Dictionary = _promotion_preflight()
	if not checked["ok"]:
		return checked
	var before: int = int(repaired["durability"])
	repaired["durability"] = int(
		_combat.item_definition(int(repaired["templateId"]))["defaultDurability"]
	)
	var actor: Dictionary = _units[id]
	var result: Dictionary = {
		"ok": true,
		"kind": "repair",
		"actor": id,
		"target": target_id,
		"item": instance_id,
		"repairedItem": repaired.duplicate(true),
		"durabilityBefore": before,
		"durabilityAfter": repaired["durability"],
		"expiredItem": _inventory.consume_held(actor, instance_id)
	}
	_finish_staff(actor, result)
	return result


func teleport_field(id: int, target_id: int, instance_id: String) -> Dictionary:
	var field: Dictionary = {}
	if staff_mode(id, instance_id) != "teleport" or target_id not in staff_targets(id, instance_id):
		return field
	for y: int in range(int(_map["height"])):
		for x: int in range(int(_map["width"])):
			if int(_base_movement_costs[int(_map["terrain"][y][x])]) >= 100:
				continue
			var occupied: bool = false
			for actor: Dictionary in _units.values():
				if actor["visible"] and int(actor["x"]) == x and int(actor["y"]) == y:
					occupied = true
					break
			if not occupied:
				field[Vector2i(x, y)] = 1
	return field


func teleport_unit(
	id: int, target_id: int, instance_id: String, destination: Vector2i
) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	if not teleport_field(id, target_id, instance_id).has(destination):
		return _failure("INVALID_TELEPORT_DESTINATION")
	var checked: Dictionary = _promotion_preflight()
	if not checked["ok"]:
		return checked
	var target: Dictionary = _units[target_id]
	var origin := Vector2i(target["x"], target["y"])
	target["x"] = destination.x
	target["y"] = destination.y
	var actor: Dictionary = _units[id]
	var result: Dictionary = {
		"ok": true,
		"kind": "teleport",
		"actor": id,
		"target": target_id,
		"item": instance_id,
		"from": origin,
		"to": destination,
		"expiredItem": _inventory.consume_held(actor, instance_id)
	}
	_finish_staff(actor, result)
	return result


func _finish_staff(actor: Dictionary, result: Dictionary) -> void:
	result["rewards"] = {
		"experience":
		_award_experience(actor, {}, false, true, false) if actor["faction"] == 0 else {},
		"loot": []
	}
	actor["action"] = 2
	_pending_move.clear()
	_check_outcome()


func can_summon(id: int, instance_id: String) -> bool:
	if not _units.has(id):
		return false
	var actor: Dictionary = _units[id]
	var held: Dictionary = _inventory.held_item(actor, instance_id)
	return (
		_inventory.can_summon_with(actor, held)
		and Summons.placement(actor, _units.values(), _map)["ok"]
	)


func summon_unit(id: int, instance_id: String) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	if not can_summon(id, instance_id):
		return _failure("SUMMON_NOT_AVAILABLE")
	var promotion_check: Dictionary = _promotion_preflight()
	if not promotion_check["ok"]:
		return promotion_check
	var born: Dictionary = _summons.birth(
		_units[id],
		_units.values(),
		_warehouse,
		_summon_state,
		int(_clone_state.get("nextGeneration", 1)) - 1
	)
	if not born["ok"]:
		return born
	var identity: int = int(born["unit"]["id"])
	_units.erase(identity)
	_units[identity] = born["unit"]
	_definitions[identity] = born["unit"].duplicate(true)
	if identity not in _required_ids:
		_required_ids.append(identity)
	_deployment_order.erase(identity)
	_deployment_order.append(identity)
	var bindings: Array = _summon_state.get("bindings", []).filter(
		func(binding: Dictionary) -> bool: return binding["unitId"] != identity
	)
	bindings.append(born["binding"])
	_summon_state = {"nextGeneration": int(born["binding"]["generation"]) + 1, "bindings": bindings}
	_refresh_unit_records()
	var actor: Dictionary = _units[id]
	var result: Dictionary = _inventory.summon(actor, instance_id)
	result["births"] = [
		{"unit": identity, "from": born["from"], "to": born["to"], "revealed": true}
	]
	result["rewards"] = {
		"experience":
		_award_experience(actor, {}, false, true, false) if actor["faction"] == 0 else {},
		"loot": []
	}
	actor["action"] = 2
	_pending_move.clear()
	_check_outcome()
	return result


func use_item(id: int, instance_id: String) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	var actor: Dictionary = _units[id]
	var held: Dictionary = _inventory.held_item(actor, instance_id)
	if held.is_empty() or not _inventory.can_use(actor, held):
		return _failure("ITEM_NOT_USABLE")
	var template: int = int(held["templateId"])
	var result: Dictionary
	if template == 76:
		var checked: Dictionary = _promotion_preflight(id)
		if not checked["ok"]:
			return checked
		result = {
			"ok": true,
			"kind": "use_item",
			"effect": "promotion",
			"actor": id,
			"item": instance_id,
			"promotion": _promote(actor, instance_id),
			"consumed": true,
			"expiredItem": {}
		}
	elif template == 63:
		var before: int = gold
		var amount: int = 1000 + _roll(2001)
		gold = mini(MAX_GOLD, gold + amount)
		result = {
			"ok": true,
			"kind": "use_item",
			"effect": "gold",
			"actor": id,
			"item": instance_id,
			"goldBefore": before,
			"goldAfter": gold,
			"rolledGold": amount,
			"creditedGold": gold - before,
			"consumed": true,
			"expiredItem": _inventory.consume_held(actor, instance_id)
		}
	elif template >= 68 and template <= 75:
		var stats: Array[String] = [
			"strength", "skill", "speed", "luck", "defense", "magic", "maxHp", "move"
		]
		var stat: String = stats[template - 68]
		var root_stat: bool = stat in ["maxHp", "move"]
		var before: int = int(actor[stat] if root_stat else actor["attributes"][stat])
		var hp_before: int = int(actor["hp"])
		var max_hp_before: int = int(actor["maxHp"])
		var amount: int = 3 if stat == "maxHp" else (1 if stat == "move" else 2)
		var cap: int = 60 if stat == "maxHp" else (10 if stat == "move" else 30)
		var after: int = mini(cap, before + amount)
		if root_stat:
			actor[stat] = after
		else:
			actor["attributes"][stat] = after
		actor["hp"] = mini(int(actor["hp"]), int(actor["maxHp"]))
		result = {
			"ok": true,
			"kind": "use_item",
			"effect": "attribute",
			"actor": id,
			"item": instance_id,
			"stat": stat,
			"statBefore": before,
			"statAfter": after,
			"hpBefore": hp_before,
			"hpAfter": actor["hp"],
			"maxHpBefore": max_hp_before,
			"maxHpAfter": actor["maxHp"],
			"consumed": true,
			"expiredItem": _inventory.consume_held(actor, instance_id)
		}
	else:
		result = _inventory.use_item(actor, instance_id)
	if result["ok"]:
		result["templateId"] = template
		actor["action"] = 2
		_pending_move.clear()
		_check_outcome()
	return result


func _promotion_preflight(only_id: int = -1, prospective_id: int = -1) -> Dictionary:
	for actor: Dictionary in _units.values():
		if (only_id >= 0 and actor["id"] != only_id) or actor["faction"] != 0 or not _alive(actor):
			continue
		if _progression.definition(int(actor["classId"])).is_empty():
			continue
		var owns_emblem: bool = actor["inventory"].any(
			func(held: Dictionary) -> bool:
				return held["templateId"] == 76 and held["durability"] > 0
		)
		if not owns_emblem and actor["id"] != prospective_id:
			continue
		var identity: int = int(actor["id"])
		var target: Dictionary = _promotion_targets.get(
			identity, _promotion_targets.get(str(identity), {})
		)
		var error: Variant = _promotion_errors.get(
			identity, _promotion_errors.get(str(identity), "")
		)
		if target.is_empty() or not str(error).is_empty():
			return _failure("PROMOTION_PRESENTATION_UNAVAILABLE")
	return {"ok": true}


func _promotion_drop_preflight(actor_id: int, target_id: int) -> Dictionary:
	var actor: Dictionary = _units[actor_id]
	var target: Dictionary = _units[target_id]
	var enemy: Dictionary = (
		actor if actor["faction"] == 2 else (target if target["faction"] == 2 else {})
	)
	if enemy.is_empty() or enemy["dropTemplateId"] != 76:
		return {"ok": true}
	if not enemy["inventory"].any(
		func(held: Dictionary) -> bool: return held["templateId"] == 76 and held["durability"] > 0
	):
		return {"ok": true}
	var fighter: Dictionary = target if enemy["id"] == actor_id else actor
	if fighter["id"] == target_id and not _combat.can_counter(fighter, enemy):
		return {"ok": true}
	var recipient: Dictionary = _reward_recipient(fighter)
	if recipient.is_empty():
		return {"ok": true}
	var promotion: Dictionary = _progression.definition(int(recipient["classId"]))
	if promotion.is_empty() or int(recipient["level"]) + 1 != int(promotion["minimumLevel"]):
		return {"ok": true}
	if not _drop_may_enter_bag(recipient, actor, target):
		return {"ok": true}
	# A marked emblem is transferred before XP. Check its prospective owner now,
	# without replaying combat or spending any of the action's random draws.
	return _promotion_preflight(int(recipient["id"]), int(recipient["id"]))


func _drop_may_enter_bag(recipient: Dictionary, actor: Dictionary, target: Dictionary) -> bool:
	if recipient["inventory"].size() < Inventory.BAG_CAPACITY:
		return true
	if recipient["id"] not in [actor["id"], target["id"]]:
		return false
	var cleaned: Dictionary = recipient.duplicate(true)
	_inventory.cleanup_combat(cleaned)
	if cleaned["inventory"].size() < Inventory.BAG_CAPACITY:
		return true
	var opponent: Dictionary = target if recipient["id"] == actor["id"] else actor
	var weapon: int = _combat.weapon_id(recipient)
	var outgoing: int = 2 * (2 if _combat.item_definition(weapon)["doubleStrike"] else 1)
	var incoming: int = 0
	if recipient["id"] == target["id"] or _combat.can_counter(opponent, recipient):
		var opponent_weapon: int = _combat.weapon_id(opponent)
		incoming = 2 * (2 if _combat.item_definition(opponent_weapon)["doubleStrike"] else 1)
	for held: Dictionary in cleaned["inventory"]:
		if held["id"] == recipient["equippedInstanceId"] and held["durability"] <= outgoing:
			return true
		if held["templateId"] in [65, 66, 67] and held["durability"] <= incoming:
			return true
	return false


func _promote(actor: Dictionary, instance_id: String) -> Dictionary:
	var result: Dictionary = _progression.apply(actor, _combat)
	var identity: int = int(actor["id"])
	var target: Dictionary = _promotion_targets.get(
		identity, _promotion_targets.get(str(identity), {})
	)
	for field: String in ["name", "className", "sprite", "spriteOffsetX", "spriteOffsetY"]:
		if target.has(field):
			actor[field] = target[field]
	assert(result["ok"], "Promotion was preflighted before mutation")
	_inventory.consume_held(actor, instance_id)
	return result


func _revival_item(actor: Dictionary) -> Dictionary:
	for held: Dictionary in actor["inventory"]:
		if held["templateId"] == 80 and held["durability"] > 0:
			return held.duplicate(true)
	return {}


func _finish_defeats(ids: Array) -> Dictionary:
	var revivals: Array[Dictionary] = []
	var retirements: Array[Dictionary] = []
	var updates: Array[Dictionary] = []
	for identity: int in ids:
		var actor: Dictionary = _units[identity]
		if actor["hp"] > 0 or not actor["visible"]:
			continue
		var changed: Array[Dictionary] = []
		if actor["classGroup"] == 10:
			actor["flags"] |= 64
			var ready: bool = true
			for unit: Dictionary in _units.values():
				if unit["classGroup"] == 10 and (int(unit["flags"]) & 64) == 0:
					ready = false
					break
			if ready:
				var ordered: Array = _units.values()
				ordered.reverse()
				for unit: Dictionary in ordered:
					if unit["classGroup"] == 10 and unit["visible"]:
						retirements.append(
							{"unitId": int(unit["id"]), "before": unit.duplicate(true)}
						)
						unit["visible"] = false
						unit["flags"] |= 1
						changed.append(
							{"unitId": int(unit["id"]), "hp": unit["hp"], "visible": false}
						)
			else:
				actor["hp"] = 1
				changed.append({"unitId": identity, "hp": 1, "visible": true})
		else:
			var ring: Dictionary = _revival_item(actor)
			if ring.is_empty():
				if actor["faction"] == 0:
					Statistics.increment(chapter_stats, "playerRetirements")
				elif actor["faction"] == 1:
					Statistics.increment(chapter_stats, "allyRetirements")
				retirements.append({"unitId": identity, "before": actor.duplicate(true)})
				actor["visible"] = false
				actor["flags"] |= 1
			else:
				var old_action: int = int(actor["action"])
				actor["hp"] = actor["maxHp"]
				actor["flags"] |= 64
				if actor["faction"] == phase:
					actor["action"] = 2
				_inventory.consume_template(actor, 80)
				revivals.append(
					{
						"unit": identity,
						"hpBefore": 0,
						"hpAfter": actor["hp"],
						"actionBefore": old_action,
						"actionAfter": actor["action"],
						"consumedItem": ring,
						"expiredItem":
						ring if actor["faction"] == 0 and ring["durability"] == 1 else {}
					}
				)
			changed.append({"unitId": identity, "hp": actor["hp"], "visible": actor["visible"]})
		updates.append({"triggerUnitId": identity, "units": changed})
	return {"revivals": revivals, "retirements": retirements, "updates": updates}


func trade_targets(id: int) -> Array[int]:
	var targets: Array[int] = []
	if not _units.has(id):
		return targets
	var actor: Dictionary = _units[id]
	for candidate: Dictionary in _units.values():
		var distance: int = (
			absi(int(actor["x"]) - int(candidate["x"]))
			+ absi(int(actor["y"]) - int(candidate["y"]))
		)
		if _alive(candidate) and candidate["faction"] == actor["faction"] and distance == 1:
			targets.append(candidate["id"])
	return targets


func movement_committed(id: int) -> bool:
	return _pending_move.get("id", -1) == id and _pending_move.get("committed", false)


func begin_trade(id: int, target_id: int) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	if target_id not in trade_targets(id):
		return _failure("INVALID_TRADE_TARGET")
	_commit_position(id)
	return {"ok": true, "kind": "begin_trade", "unit": id, "target": target_id}


func _commit_position(id: int) -> void:
	if _pending_move.is_empty():
		_pending_move = {"id": id, "origin": Vector2i(_units[id]["x"], _units[id]["y"])}
	_pending_move["committed"] = true


func trade_item(
	id: int, target_id: int, instance_id: String, exchange_id: String = ""
) -> Dictionary:
	var error: String = _action_error(id)
	if not error.is_empty():
		return _failure(error)
	if target_id not in trade_targets(id):
		return _failure("INVALID_TRADE_TARGET")
	var source: Dictionary = _units[id]
	var destination: Dictionary = _units[target_id]
	if _inventory.held_item(source, instance_id).is_empty():
		source = _units[target_id]
		destination = _units[id]
	var result: Dictionary = _inventory.trade(source, destination, instance_id, exchange_id)
	if result["ok"]:
		_inventory.auto_equip(source)
		_inventory.auto_equip(destination)
		_commit_position(id)
	return result


func _check_outcome() -> void:
	if outcome.is_empty():
		outcome = _chapter_events.outcome(_units.values(), round_number)


func end_phase() -> Dictionary:
	if not _pending_move.is_empty():
		return _failure("ACTION_PENDING")
	_check_outcome()
	if not outcome.is_empty():
		return _failure("BATTLE_ENDED")
	if phase != 0:
		# Births are ready for a later phase, outside this phase's original queue.
		for identity: int in _automatic_queue:
			if _can_act(identity):
				return _failure("AUTOMATIC_ACTIONS_PENDING")
	var events: Array[Dictionary] = []
	for iteration: int in range(3):
		if phase == 2:
			for event: Dictionary in _chapter_events.turn_events_due(round_number):
				if event_completed(event["id"]):
					continue
				if event.has("withdrawUnitId"):
					var before: Dictionary = _chapter_events.withdraw(
						_units.values(), int(event["withdrawUnitId"])
					)
					complete_event(event["id"])
					if not before.is_empty():
						events.append(
							{
								"kind": "withdrawal",
								"unit": before,
								"sequence": event.get("sequence", "")
							}
						)
					continue
				var queue: Array[Dictionary] = []
				if event.get("arrivalMode") == "nativeQueue":
					for identity: Variant in event["unitIds"]:
						var actor: Dictionary = _units.get(int(identity), {})
						if actor.is_empty() or actor["visible"] or actor["hp"] <= 0:
							continue
						queue.append(
							{"unit": int(identity), "from": Vector2i(actor["x"], actor["y"])}
						)
				var arrivals: Array[Dictionary] = _chapter_events.reinforce(
					_units.values(), event["unitIds"]
				)
				complete_event(event["id"])
				var emitted: Dictionary = {
					"kind": "reinforcements",
					"sequence": event.get("sequence", ""),
					"arrivals": arrivals
				}
				if event.get("arrivalMode") == "nativeQueue":
					for arrival: Dictionary in queue:
						var actor: Dictionary = _units[int(arrival["unit"])]
						arrival["to"] = Vector2i(actor["x"], actor["y"])
						arrival["revealed"] = actor["visible"]
					emitted["arrivalMode"] = "nativeQueue"
					emitted["arrivalQueue"] = queue
				events.append(emitted)
			var cloned: Dictionary = _commit_clone_wave()
			if not cloned["ok"]:
				return cloned
			if not cloned["event"].is_empty():
				events.append(cloned["event"])
			round_number += 1
			Statistics.increment(chapter_stats, "rounds")
		phase = (phase + 1) % 3
		var phase_units: Array = _units.values()
		phase_units.reverse()
		for actor: Dictionary in phase_units:
			actor["action"] = 0
			actor["flags"] &= ~64
			if phase == 0:
				actor["flags"] &= ~(8 | 32)
				for held: Dictionary in actor["inventory"]:
					if int(held["templateId"]) == 81:
						var percent: int = _roll(11) + 10
						var recovered: int = floori(float(actor["maxHp"] * percent) / 100.0)
						actor["hp"] = mini(actor["maxHp"], actor["hp"] + recovered)
						break
		_assignments.clear()
		_automatic_queue.clear()
		if phase != 0:
			_chapter_events.prepare_automatic_phase(round_number, phase, _units.values())
			_automatic_queue = _ai.order(_units.values(), phase)
		if phase == 0 or not _automatic_queue.is_empty():
			break
	_check_outcome()
	return {"ok": true, "kind": "phase", "phase": phase, "round": round_number, "events": events}


func _commit_clone_wave() -> Dictionary:
	if _clone_policy == null:
		return {"ok": true, "event": {}}
	var planned: Dictionary = _clones.plan_wave(
		round_number, _units, _warehouse, _clone_state, _events
	)
	if not planned["ok"]:
		return planned
	if planned["eventId"].is_empty():
		return {"ok": true, "event": {}}
	if planned.get("skipped", false):
		complete_event(planned["eventId"])
		return {"ok": true, "event": {}}
	var units: Dictionary = planned["units"]
	var arrivals: Array = _chapter_events.reinforce(units.values(), planned["birthIds"])
	var births: Array[Dictionary] = []
	for identity: int in planned["birthIds"]:
		var actor: Dictionary = units[identity]
		births.append(
			{
				"unit": identity,
				"from": planned["origins"][identity],
				"to": Vector2i(actor["x"], actor["y"]),
				"revealed": actor["visible"]
			}
		)
		_definitions[identity] = actor.duplicate(true)
	_units = units
	_deployment_order.assign(_units.keys())
	_clone_state = planned["cloneState"]
	_refresh_unit_records()
	complete_event(planned["eventId"])
	return {"ok": true, "event": {"kind": "clones", "births": births, "arrivals": arrivals}}


func automatic_actor() -> int:
	if phase == 0 or not outcome.is_empty():
		return -1
	while not _automatic_queue.is_empty():
		var id: int = _automatic_queue[0]
		if _can_act(id):
			return id
		_automatic_queue.pop_front()
	return -1


func begin_automatic_action(id: int) -> Dictionary:
	if phase == 0 or id < 0 or automatic_actor() != id or not _can_act(id):
		return _failure("INVALID_AUTOMATIC_ACTOR")
	if not _pending_move.is_empty():
		return _failure("ACTION_PENDING")
	var plan: Dictionary = _ai.plan(
		_units[id], _units.values(), _commander(), command_policy, round_number, _assignments
	)
	var preview: Dictionary = preview_move(id, plan["cell"])
	if not preview["ok"]:
		return preview
	var previous: Dictionary = _units[id].duplicate(true)
	if not plan["equipItem"].is_empty():
		var equipped: Dictionary = _inventory.equip(_units[id], plan["equipItem"])
		if not equipped["ok"]:
			return equipped
	var moved: Dictionary = move_unit(id, plan["cell"])
	if not moved["ok"]:
		_units[id] = previous
		return moved
	var allocation: Dictionary = plan["allocation"]
	if not allocation.is_empty():
		var target: int = int(allocation["unit"])
		_assignments[target] = int(_assignments.get(target, 0)) + int(allocation["power"])
	_automatic_queue.pop_front()
	return {
		"ok": true, "kind": "automatic_action", "actor": id, "plan": plan, "path": moved["path"]
	}


func win_with_assistance() -> Dictionary:
	if not can_save():
		return _failure("BATTLE_NOT_READY")
	outcome = {"kind": "victory", "reason": "assistance"}
	return {"ok": true, "kind": "assisted_victory"}


func complete_victory(route: int) -> Dictionary:
	var terminal_route: bool = (
		(
			_record_content["story"].has("chapterEnd")
			or _record_content["story"].get("encounter", false) == true
		)
		and route == int(_campaign.get("route", -1))
	)
	if (not _routes.has(route) and not terminal_route) or outcome.get("kind") != "victory":
		return _failure("INVALID_COMPLETION")
	if not _completion.is_empty():
		if _completion["route"] != route:
			return _failure("ROUTE_ALREADY_CHOSEN")
		return {"ok": true, "alreadyComplete": true, "progress": _completion.duplicate(true)}
	var context: Dictionary = _campaign_rules.complete(snapshot(), route)
	if not context["ok"]:
		return context
	_completion = context["progress"]
	gold = _completion["gold"]
	_units = context["party"]
	phase = 0
	_pending_move.clear()
	_automatic_queue.clear()
	_assignments.clear()
	complete_event("settled")
	return {"ok": true, "alreadyComplete": false, "progress": _completion.duplicate(true)}
