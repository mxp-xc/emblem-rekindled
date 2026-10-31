# gdlint: disable=max-public-methods
# Named commands and queries share the single authoritative battle state.
extends RefCounted

const MAX_GOLD: int = 9999999

const NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const AI = preload("res://gameplay/tactical_ai.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Resolution = preload("res://gameplay/combat_resolution.gd")
const UnitRecord = preload("res://gameplay/unit_record.gd")
const MapRules = preload("res://gameplay/map_rules.gd")
const Inventory = preload("res://gameplay/unit_inventory.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const STAT_ORDER: Array[String] = [
	"strength", "skill", "speed", "defense", "magic", "luck", "maxHp", "move"
]
const INITIAL_NOISE: Array[int] = [3, 2, 2, 2, 2, 5, 2, 0]

var phase: int = 0
var round_number: int = 1
var commander_id: int = 9
var command_policy: int = 0
var gold: int = 0
var outcome: Dictionary = {}
var _initial_gold: int
var _completion: Dictionary = {}
var _routes: Dictionary = {}
var _gold_reward: int
var _chapter_id: String
var _battle_id: String
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
var _base_stats: Dictionary = {}
var _growth_rates: Dictionary = {}
var _stat_caps: Dictionary
var _unit_records: RefCounted
var _warehouse: Array = []
var _events: Dictionary = {}
var _units: Dictionary = {}
var _pending_move: Dictionary = {}


func _init(content: Dictionary, random_source: Callable = Callable()) -> void:
	_chapter_id = content["entry"]["id"]
	_battle_id = content["entry"]["firstBattle"]
	_initial_gold = int(content["rules"]["initialGold"])
	gold = _initial_gold
	_gold_reward = int(content["story"]["sequences"]["victory"][-1]["goldReward"])
	for route: Dictionary in content["story"]["routeChoices"]:
		_routes[int(route["routeIndex"])] = route
	_map = content["map"].duplicate(true)
	_alliances = content["rules"]["alliances"].duplicate()
	_movement = MapRules.new(_map, _alliances)
	_combat = Combat.new(content["rules"], _map["terrain"])
	_random_source = random_source
	_inventory = Inventory.new(_combat, _roll)
	_resolution = Resolution.new(_combat, _inventory, _roll)
	_chapter_events = Events.new(content)
	_ai = AI.new(content)
	_rng.randomize()
	_stat_caps = content["rules"]["statCaps"].duplicate(true)
	for row: Dictionary in content["rules"]["baseStats"]:
		_base_stats[int(row["id"])] = row.duplicate(true)
	for row: Dictionary in content["rules"]["growthRates"]:
		_growth_rates[int(row["id"])] = row.duplicate(true)
	_unit_records = UnitRecord.new(content, _combat)
	var spawns: Dictionary = {}
	for spawn: Dictionary in content["spawns"]:
		spawns[int(spawn["id"])] = spawn
	for definition: Dictionary in content["units"]:
		var current: Dictionary = definition.duplicate(true)
		for key: String in [
			"id",
			"faction",
			"x",
			"y",
			"classId",
			"classGroup",
			"move",
			"hp",
			"maxHp",
			"level",
			"flags",
			"equipMask",
			"sourceId",
			"dropTemplateId",
			"proficiency",
			"experience"
		]:
			current[key] = int(current[key])
		current["action"] = 0
		_initialize_unit(current, spawns[current["id"]])
		_units[current["id"]] = current


func _initialize_unit(current: Dictionary, spawn: Dictionary) -> void:
	current["sourceId"] = int(spawn["sourceId"])
	current["formal"] = spawn["formal"]
	current["flags"] = int(spawn["flags"])
	current["policy"] = int(spawn["policy"])
	current["visible"] = spawn["visible"]
	current["level"] = int(spawn["level"])
	current["growthTemplateId"] = int(spawn["growthTemplateId"])
	current["experience"] = 0
	current["proficiency"] = 0
	current["x"] = int(spawn["position"][0])
	current["y"] = int(spawn["position"][1])
	current["inventory"] = []
	current["equippedInstanceId"] = ""
	var choices: Array = spawn["itemChoices"].duplicate()
	if spawn["randomEquipment"]:
		var selected: int = _roll(choices.size())
		for index: int in range(choices.size()):
			if index != selected:
				choices[index] = 0
	for template_id: Variant in choices:
		_add_initial_item(current, int(template_id))
	_add_initial_item(current, int(spawn["dropTemplateId"]))
	var values: Dictionary
	if spawn.has("explicitStats"):
		values = spawn["explicitStats"].duplicate(true)
	else:
		values = {}
		var base: Dictionary = _base_stats[int(spawn["baseTemplateId"])]
		var growth: Dictionary = _growth_rates[int(spawn["initialGrowthTemplateId"])]
		for index: int in range(STAT_ORDER.size()):
			var stat: String = STAT_ORDER[index]
			var value: int = int(base[stat]) + int(float(growth[stat]) * current["level"] / 100.0)
			if current["faction"] != 0:
				value += _roll(INITIAL_NOISE[index] + 1)
			if value < 0 or value > int(_stat_caps[stat]):
				value = int(_stat_caps[stat])
			values[stat] = value
	current["attributes"] = {}
	for stat: String in STAT_ORDER:
		if stat in ["maxHp", "move"]:
			current[stat] = int(values[stat])
		else:
			current["attributes"][stat] = int(values[stat])
	current["hp"] = current["maxHp"]
	_inventory.auto_equip(current)


func _add_initial_item(current: Dictionary, template_id: int) -> void:
	if template_id <= 0:
		return
	current["inventory"].append(
		{
			"id": "chapter_1:unit_%d:item_%d" % [current["id"], current["inventory"].size()],
			"templateId": template_id,
			"durability": int(_combat.item_definition(template_id)["defaultDurability"])
		}
	)


func unit(id: int) -> Dictionary:
	return _units.get(id, {}).duplicate(true)


func unit_information(id: int, instance_id: String = "") -> Dictionary:
	var actor: Dictionary = _units.get(id, {}).duplicate(true)
	if actor.is_empty():
		return {}
	if not instance_id.is_empty() and not _inventory.equip(actor, instance_id)["ok"]:
		return {}
	return {} if actor.is_empty() else _combat.information(actor, _commander())


func snapshot() -> Dictionary:
	return {
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


func can_save() -> bool:
	return phase == 0 and _pending_move.is_empty() and outcome.is_empty()


func event_completed(event_id: String) -> bool:
	return _events.get(event_id, false)


func complete_event(event_id: String) -> void:
	_events[event_id] = true


func restore_snapshot(state: Dictionary) -> Dictionary:
	if not state.get("events") is Dictionary:
		return _failure("INVALID_SAVE_EVENTS")
	for event_id: Variant in state["events"]:
		if not event_id is String or not state["events"][event_id] is bool:
			return _failure("INVALID_SAVE_EVENTS")
	if (
		not _integer_in(state.get("phase"), 0, 0)
		or not _integer_in(state.get("round"), 1, 2147483647)
		or not _integer_in(state.get("commander"), -1, 9)
		or not _integer_in(state.get("nextActionId"), 1, 2147483647)
	):
		return _failure("INVALID_SAVE_FLOW")
	if (
		not state.get("pending_move") is Dictionary
		or not state["pending_move"].is_empty()
		or not state.get("units") is Array
		or state["units"].size() != _units.size()
		or not state.get("warehouse") is Array
		or state["warehouse"].size() > 40
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
		if not value is Dictionary or not _integer_in(value.get("id"), 0, 126):
			return _failure("INVALID_SAVE_UNIT")
		var id: int = int(value["id"])
		if not _units.has(id) or candidate.has(id):
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
	var warehouse: Array = state["warehouse"].duplicate(true)
	if not _unit_records.validate_inventory(warehouse, held_ids):
		return _failure("INVALID_SAVE_WAREHOUSE")
	if (
		not _integer_in(state.get("commandPolicy", 0), 0, 5)
		or int(state.get("commandPolicy", 0)) not in [0, 1, 4, 5]
	):
		return _failure("INVALID_SAVE_COMMAND")
	var commander: int = int(state["commander"])
	if (
		commander >= 0
		and (
			not candidate.has(commander)
			or not candidate[commander]["formal"]
			or not _alive(candidate[commander])
		)
	):
		return _failure("INVALID_SAVE_COMMANDER")
	if not _chapter_events.outcome(candidate.values()).is_empty():
		return _failure("SAVE_NOT_STABLE")
	outcome.clear()
	_completion.clear()
	_automatic_queue.clear()
	_assignments.clear()
	_units = candidate
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
	var weapons: Array[Dictionary] = []
	if not _can_act(id) or (not _pending_move.is_empty() and _pending_move["id"] != id):
		return weapons
	for held: Dictionary in _units[id]["inventory"]:
		var targets: Array[int] = attack_targets(id, held["id"])
		if not targets.is_empty():
			weapons.append(
				{"item": held.duplicate(true), "information": unit_information(id, held["id"])}
			)
	return weapons


func attack_targets(id: int, instance_id: String = "") -> Array[int]:
	var targets: Array[int] = []
	if not _units.has(id):
		return targets
	var actor: Dictionary = _units[id].duplicate(true)
	if not instance_id.is_empty() and not _inventory.equip(actor, instance_id)["ok"]:
		return targets
	for candidate: Dictionary in _units.values():
		if _attack_target_valid(actor, candidate):
			targets.append(candidate["id"])
	return targets


func attack_field(id: int, instance_id: String = "") -> Dictionary:
	if not _units.has(id):
		return {}
	var actor: Dictionary = _units[id].duplicate(true)
	if not instance_id.is_empty() and not _inventory.equip(actor, instance_id)["ok"]:
		return {}
	return _item_field(actor, _combat.weapon_id(actor))


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
		or not _attack_target_valid(_units[id], _units[target_id])
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
	if not _units.has(target_id) or not _attack_target_valid(_units[id], _units[target_id]):
		return _failure("INVALID_ATTACK_TARGET")
	var actor: Dictionary = _units[id]
	var target: Dictionary = _units[target_id]
	var preview: Dictionary = attack_preview(id, target_id)
	var resolution: Dictionary = _resolution.resolve(actor, target, _commander())
	var resolved_weapons: Dictionary = {
		str(id): _combat.weapon_id(actor), str(target_id): _combat.weapon_id(target)
	}
	var broken_items: Array[Dictionary] = []
	for participant: Dictionary in resolution["participants"]:
		for held: Dictionary in participant["inventory"]:
			var remaining: Dictionary = _inventory.held_item(
				_units[int(participant["id"])], held["id"]
			)
			if held["durability"] > 0 and (remaining.is_empty() or remaining["durability"] <= 0):
				broken_items.append(
					{
						"unit": participant["id"],
						"item": held["id"],
						"templateId": held["templateId"]
					}
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
		"rewards": rewards
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


func _attack_target_valid(actor: Dictionary, target: Dictionary) -> bool:
	var weapon: int = _combat.weapon_id(actor)
	return (
		_alive(actor)
		and _alive(target)
		and _alliances[actor["faction"]] != _alliances[target["faction"]]
		and weapon > 0
		and _combat.item_definition(weapon)["damageKind"] in ["physical", "magic"]
		and _combat.in_range(actor, target, weapon)
	)


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
		or id not in [0, 9]
		or not _alive(_units[id])
	):
		return _failure("INVALID_COMMANDER")
	commander_id = id
	command_policy = (1 if follow else 0) | (4 if defend else 0)
	return {"ok": true}


func command_configuration() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for id: int in [9, 0]:
		if _alive(_units.get(id, {})):
			candidates.append({"id": id, "name": _units[id]["name"]})
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
	if (
		held.is_empty()
		or held["durability"] <= 0
		or int(held["templateId"]) not in [53, 54]
		or (int(actor["equipMask"]) & 32) == 0
	):
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
		outcome = _chapter_events.outcome(_units.values())


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
			if (
				_chapter_events.reinforcements_due(round_number)
				and not event_completed("reinforcements")
			):
				var arrivals: Array[Dictionary] = _chapter_events.reinforce(_units.values())
				complete_event("reinforcements")
				events.append({"kind": "reinforcements", "arrivals": arrivals})
			round_number += 1
		phase = (phase + 1) % 3
		for actor: Dictionary in _units.values():
			actor["action"] = 0
			actor["flags"] &= ~128
			if phase == 0:
				actor["flags"] &= ~(16 | 64)
		_assignments.clear()
		_automatic_queue.clear()
		if phase != 0:
			_automatic_queue = _ai.order(_units.values(), phase)
		if phase == 0 or not _automatic_queue.is_empty():
			break
	return {"ok": true, "kind": "phase", "phase": phase, "round": round_number, "events": events}


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
	gold = mini(MAX_GOLD, gold + _gold_reward)
	var retained: Dictionary = {}
	for actor: Dictionary in _units.values():
		if actor["formal"]:
			actor["hp"] = actor["maxHp"]
			actor["flags"] = 0
			actor["action"] = 0
			actor["visible"] = true
			retained[int(actor["id"])] = actor
	_units = retained
	phase = 0
	_pending_move.clear()
	_automatic_queue.clear()
	_assignments.clear()
	complete_event("settled")
	_completion = {
		"chapterId": _chapter_id,
		"completedBattle": _battle_id,
		"worldNode": 0,
		"route": route,
		"gold": gold,
		"commander": commander_id,
		"commandPolicy": command_policy,
		"party": _units.values().duplicate(true),
		"warehouse": _warehouse.duplicate(true)
	}
	return {"ok": true, "alreadyComplete": false, "progress": _completion.duplicate(true)}
