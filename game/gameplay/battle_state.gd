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
const MapRules = preload("res://gameplay/map_rules.gd")
const Inventory = preload("res://gameplay/unit_inventory.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const MapAttack = preload("res://gameplay/map_attack.gd")
const Clones = preload("res://gameplay/battle_clones.gd")
const STAT_ORDER: Array[String] = [
	"strength", "skill", "speed", "defense", "magic", "luck", "maxHp", "move"
]

var phase: int = 0
var round_number: int = 1
var commander_id: int = -1
var command_policy: int = 0
var gold: int = 0
var outcome: Dictionary = {}
var battle_id: String
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
var _alliances: Array
var _combat: RefCounted
var _inventory: RefCounted
var _movement: RefCounted
var _random_source: Callable
var _rng := RandomNumberGenerator.new()
var _next_action_id: int = 1
var _growth_rates: Dictionary = {}
var _stat_caps: Dictionary
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
var _record_content: Dictionary


func _init(
	content: Dictionary, random_source: Callable = Callable(), initialize: bool = true
) -> void:
	_chapter_id = content["entry"]["id"]
	battle_id = content["entry"]["battleId"]
	for step: Dictionary in content["story"]["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			for id: Variant in step["candidates"]:
				_commander_candidates.append(int(id))
			commander_id = int(step["defaultCommanderId"])
			break
	_initial_gold = int(content["rules"]["initialGold"])
	gold = _initial_gold
	for route: Dictionary in content["story"]["routeChoices"]:
		_routes[int(route["routeIndex"])] = route
	_map = content["map"].duplicate(true)
	_alliances = content["rules"]["alliances"].duplicate()
	_movement = MapRules.new(_map, _alliances)
	_combat = Combat.new(content["rules"], _map["terrain"])
	_random_source = random_source
	_inventory = Inventory.new(_combat, _roll)
	_resolution = Resolution.new(_combat, _inventory, _roll)
	_map_attack = MapAttack.new(
		_combat, _inventory, _resolution, _map, _alliances, content.get("mapEffects")
	)
	_chapter_events = Events.new(content)
	_ai = AI.new(content)
	_clone_policy = content["story"].get("periodicClones")
	_clone_records = content.get("_deployments", [])
	_clones = Clones.new(content, _combat, _inventory)
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
	for definition: Dictionary in content["units"]:
		_definitions[int(definition["id"])] = definition.duplicate(true)
		if int(definition["id"]) not in content.get("optionalIds", []):
			_required_ids.append(int(definition["id"]))
	if initialize:
		var initial: Dictionary = Deployment.new(content, _combat, _inventory, _roll).create()
		_units = initial["units"]
		_definitions = initial["definitions"]
		_required_ids = initial["requiredIds"]
		_deployment_bindings = initial["bindings"]
	_adopt_unit_order(content)
	_record_content = content.duplicate()
	_refresh_unit_records()


func deployment_bindings() -> Dictionary:
	return _deployment_bindings.duplicate()


# Rebind presentation identities after optional deployments have been resolved.
# This replaces no battle result and performs no initialization or random draw.
func adopt_content(content: Dictionary) -> void:
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
	_refresh_unit_records()
	_chapter_events = Events.new(content)
	_ai = AI.new(content)
	_clones = Clones.new(content, _combat, _inventory)


func _refresh_unit_records() -> void:
	_record_content["units"] = _definitions.values()
	_unit_records = UnitRecord.new(_record_content, _combat)
	_campaign_rules = Campaign.new(_record_content, _unit_records, MAX_GOLD)


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
	if not _campaign_rules.valid_context(state.get("campaign", {})):
		return _failure("INVALID_SAVE_CAMPAIGN")
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
	_campaign = state.get("campaign", {}).duplicate(true)
	for field: String in ["route", "worldStep"]:
		if _campaign.has(field):
			_campaign[field] = int(_campaign[field])
	_events = state["events"].duplicate(true)
	_warehouse = warehouse
	phase = int(state["phase"])
	round_number = int(state["round"])
	commander_id = commander
	gold = int(state.get("gold", _initial_gold))
	command_policy = int(state.get("commandPolicy", 0))
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


func actions_for(id: int) -> Array[String]:
	if not _can_act(id) or (not _pending_move.is_empty() and _pending_move["id"] != id):
		return []
	var actions: Array[String] = ["wait"]
	if _pending_move.is_empty():
		actions.push_front("move")
	elif not movement_committed(id):
		actions.append("cancel_move")
	for held: Dictionary in _units[id]["inventory"]:
		if not heal_targets(id, held["id"]).is_empty():
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
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	_units[id]["action"] = 2
	_pending_move.clear()
	_check_outcome()
	return {"ok": true, "kind": "wait", "unit": id}


func equip_unit(id: int, instance_id: String) -> Dictionary:
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	return _inventory.equip(_units[id], instance_id)


func item_options(id: int) -> Dictionary:
	if not _can_act(id) or (not _pending_move.is_empty() and _pending_move["id"] != id):
		return {}
	var options: Dictionary = {}
	for operation: String in ["use", "equip", "discard"]:
		var candidates: Array[Dictionary] = _inventory.candidates(_units[id], operation)
		if not candidates.is_empty():
			options[operation] = candidates
	return options


func discard_item(id: int, instance_id: String) -> Dictionary:
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	return _inventory.discard(_units[id], instance_id)


func attack_weapons(id: int) -> Array[Dictionary]:
	if not _can_act(id) or (not _pending_move.is_empty() and _pending_move["id"] != id):
		return []
	return _map_attack.weapons(_units[id], _units.values(), round_number, _commander())


func attack_options(id: int, instance_id: String) -> Dictionary:
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	return _map_attack.options(_units[id], instance_id, _units.values(), round_number)


func map_attack_preview(id: int, instance_id: String, primary_id: int = -1) -> Dictionary:
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	return _map_attack.prepare(
		_units[id], instance_id, _units.values(), round_number, _commander(), primary_id
	)


func cast_map_attack(id: int, instance_id: String, primary_id: int = -1) -> Dictionary:
	var preview: Dictionary = map_attack_preview(id, instance_id, primary_id)
	if not preview["ok"]:
		return preview
	var result: Dictionary = _map_attack.resolve(preview, _commander())
	for current: Dictionary in result["changes"]:
		_units[int(current["id"])] = current
	result.erase("changes")
	_pending_move.clear()
	var actor: Dictionary = _units[id]
	var last: Dictionary = _units[int(result["targetIds"][-1])]
	result["rewards"] = {"experience": {}, "loot": []}
	if actor["faction"] != 2:
		result["rewards"]["experience"] = _award_experience(
			actor,
			_combat.experience_gain(actor, last, result["anyKill"], true, false, _commander())
		)
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
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	if _combat.action_mode(_combat.weapon_id(_units[id])) != "battle_clip":
		return _failure("INVALID_ACTION_MODE")
	if not _units.has(target_id) or not _map_attack.target_valid(_units[id], _units[target_id]):
		return _failure("INVALID_ATTACK_TARGET")
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
		if unit_state["hp"] <= 0:
			unit_state["visible"] = false
			unit_state["flags"] |= 1
	var rewards: Dictionary = _settle_combat(actor, target, strikes)
	var story_events: Dictionary = _chapter_events.combat_events(
		resolution["participants"], _units.values(), _events
	)
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
		"retirements": story_events["retirements"]
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
			var loot: Dictionary = _inventory.transfer_drop(dead, recipient, _warehouse)
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
	var amount: int = _combat.experience_gain(
		recipient, opponent, not dead.is_empty(), hit, fighter["faction"] == 1, _commander()
	)
	rewards["experience"] = _award_experience(recipient, amount)
	return rewards


func _reward_recipient(fighter: Dictionary) -> Dictionary:
	if fighter["hp"] <= 0 or fighter["faction"] == 2:
		return {}
	if fighter["faction"] == 1:
		return {} if fighter["classGroup"] in [7, 8, 9] else _commander()
	return fighter


func _award_experience(actor: Dictionary, amount: int) -> Dictionary:
	if amount <= 0:
		return {}
	var before: int = int(actor["experience"])
	actor["experience"] = (before + amount) % 100
	var growth: Dictionary = {}
	if before + amount >= 100:
		actor["level"] += 1
		var rates: Dictionary = _growth_rates[int(actor["growthTemplateId"])]
		for stat: String in STAT_ORDER:
			var increment: int = 1 if _roll(100) < int(rates[stat]) else 0
			var value: int = int(
				actor[stat] if stat in ["maxHp", "move"] else actor["attributes"][stat]
			)
			increment = mini(increment, int(_stat_caps[stat]) - value)
			if stat in ["maxHp", "move"]:
				actor[stat] += increment
			else:
				actor["attributes"][stat] += increment
			growth[stat] = increment
	return {
		"unit": actor["id"],
		"amount": amount,
		"before": before,
		"after": actor["experience"],
		"level": actor["level"],
		"growth": growth
	}


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
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	if target_id not in heal_targets(id, instance_id):
		return _failure("INVALID_HEAL_TARGET")
	var actor: Dictionary = _units[id]
	var result: Dictionary = _inventory.heal(actor, _units[target_id], instance_id)
	if not result["ok"]:
		return result
	result["rewards"] = {
		"experience":
		(
			_award_experience(
				actor, _combat.experience_gain(actor, {}, false, true, false, _commander())
			)
			if actor["faction"] == 0
			else {}
		),
		"loot": []
	}
	actor["action"] = 2
	_pending_move.clear()
	_check_outcome()
	return result


func use_item(id: int, instance_id: String) -> Dictionary:
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
	var result: Dictionary = _inventory.use_item(_units[id], instance_id)
	if result["ok"]:
		_units[id]["action"] = 2
		_pending_move.clear()
		_check_outcome()
	return result


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
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
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
	if not _can_act(id):
		return _failure("UNIT_NOT_READY")
	if not _pending_move.is_empty() and _pending_move["id"] != id:
		return _failure("ACTION_PENDING")
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
		for actor: Dictionary in _units.values():
			if _can_act(actor["id"]):
				return _failure("AUTOMATIC_ACTIONS_PENDING")
	var events: Array[Dictionary] = []
	for iteration: int in range(3):
		if phase == 2:
			for event: Dictionary in _chapter_events.turn_events_due(round_number):
				if event_completed(event["id"]):
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
		phase = (phase + 1) % 3
		var phase_units: Array = _units.values()
		phase_units.reverse()
		for actor: Dictionary in phase_units:
			actor["action"] = 0
			actor["flags"] &= ~128
			if phase == 0:
				actor["flags"] &= ~(16 | 64)
				for held: Dictionary in actor["inventory"]:
					if int(held["templateId"]) == 81:
						var percent: int = _roll(11) + 10
						var recovered: int = floori(float(actor["maxHp"] * percent) / 100.0)
						actor["hp"] = mini(actor["maxHp"], actor["hp"] + recovered)
						break
		_assignments.clear()
		_automatic_queue.clear()
		if phase == 2:
			_chapter_events.prepare_enemy_phase(round_number, _units.values())
		if phase != 0:
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
	if not _routes.has(route) or outcome.get("kind") != "victory":
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
