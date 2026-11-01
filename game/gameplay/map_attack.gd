extends RefCounted

const Shapes = preload("res://gameplay/map_attack_rules.gd")
var _combat: RefCounted
var _inventory: RefCounted
var _resolution: RefCounted
var _map: Dictionary
var _alliances: Array
var _effects: Dictionary = {}


func _init(
	combat: RefCounted,
	inventory: RefCounted,
	resolution: RefCounted,
	map: Dictionary,
	alliances: Array,
	effects: Variant
) -> void:
	_combat = combat
	_inventory = inventory
	_resolution = resolution
	_map = map
	_alliances = alliances
	if effects is Dictionary:
		_effects = effects.duplicate(true)


# Queries bind actual held items on copies; they never draw random numbers.
func weapons(
	actor: Dictionary, units: Array, round_number: int, commander: Dictionary
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for held: Dictionary in actor["inventory"]:
		var available: Dictionary = options(actor, held["id"], units, round_number)
		if (
			not available.get("ok", false)
			or (not available["available"] and available["actionMode"] != "map_attack")
		):
			continue
		var equipped: Dictionary = actor.duplicate(true)
		_inventory.equip(equipped, held["id"])
		rows.append(
			{
				"item": held.duplicate(true),
				"information": _combat.information(equipped, commander),
				"actionMode": available["actionMode"],
				"available": available["available"],
				"reason": available["reason"]
			}
		)
	return rows


func options(actor: Dictionary, instance_id: String, units: Array, round_number: int) -> Dictionary:
	var held: Dictionary = _inventory.held_item(actor, instance_id)
	if held.is_empty():
		return _failure("ITEM_NOT_OWNED")
	if not _combat.can_equip(actor, held):
		return _failure("EQUIPMENT_NOT_ALLOWED")
	var weapon: int = int(held["templateId"])
	var item: Dictionary = _combat.item_definition(weapon)
	var mode: String = _combat.action_mode(weapon)
	if mode not in ["battle_clip", "map_attack"]:
		return _failure("INVALID_ACTION_MODE")
	var primary: Array[int] = []
	var selection: String = "hostile_unit"
	var reason: String = ""
	var cells: Dictionary = {}
	if mode == "map_attack":
		if not Shapes.valid_definition(item):
			reason = "INVALID_MAP_ATTACK_RULE"
		else:
			selection = item["targetRule"]["selection"]
			cells = field(actor, weapon)
			primary = Shapes.primary_targets(actor, item, units, _alliances)
			var affected: Array[int] = (
				Shapes.affected_targets(actor, item, units, _alliances)
				if selection == "none"
				else primary
			)
			if not _combat.map_attack_available(weapon, round_number):
				reason = "ROUND_UNAVAILABLE"
			elif affected.is_empty():
				reason = "NO_ATTACK_TARGETS"
			elif (
				not (_effects.get(item["mapEffect"]) is Dictionary)
				or _effects[item["mapEffect"]].is_empty()
			):
				reason = "MAP_EFFECT_UNAVAILABLE"
	else:
		var equipped: Dictionary = actor.duplicate(true)
		_inventory.equip(equipped, instance_id)
		primary = targets(equipped, units, round_number)
		cells = field(equipped, weapon)
		if primary.is_empty():
			reason = "NO_ATTACK_TARGETS"
	return {
		"ok": true,
		"actionMode": mode,
		"available": reason.is_empty(),
		"reason": reason,
		"selection": selection,
		"primaryTargets": primary,
		"rangeCells": cells
	}


func targets(actor: Dictionary, units: Array, round_number: int) -> Array[int]:
	var weapon: int = _combat.weapon_id(actor)
	if _combat.action_mode(weapon) == "map_attack":
		if not _combat.map_attack_available(weapon, round_number):
			return []
		return Shapes.primary_targets(actor, _combat.item_definition(weapon), units, _alliances)
	var primary: Array[int] = []
	for target: Dictionary in units:
		if target_valid(actor, target):
			primary.append(int(target["id"]))
	return primary


func target_valid(actor: Dictionary, target: Dictionary) -> bool:
	var weapon: int = _combat.weapon_id(actor)
	return (
		actor["visible"]
		and actor["hp"] > 0
		and target["visible"]
		and target["hp"] > 0
		and _alliances[int(actor["faction"])] != _alliances[int(target["faction"])]
		and weapon > 0
		and _combat.action_mode(weapon) == "battle_clip"
		and _combat.item_definition(weapon)["damageKind"] in ["physical", "magic"]
		and _combat.in_range(actor, target, weapon)
	)


func field(actor: Dictionary, weapon: int) -> Dictionary:
	if weapon <= 0:
		return {}
	var item: Dictionary = _combat.item_definition(weapon)
	if item.get("actionMode") == "map_attack":
		if not Shapes.valid_definition(item):
			return {}
	elif item["maxRange"] == 100:
		return {}
	return Shapes.range_cells(actor, item, Vector2i(_map["width"], _map["height"]))


func prepare(
	actor: Dictionary,
	instance_id: String,
	units: Array,
	round_number: int,
	commander: Dictionary,
	primary_id: int = -1
) -> Dictionary:
	var available: Dictionary = options(actor, instance_id, units, round_number)
	if not available["ok"]:
		return available
	if available["actionMode"] != "map_attack":
		return _failure("INVALID_ACTION_MODE")
	if not available["available"]:
		return _failure(available["reason"])
	var equipped: Dictionary = actor.duplicate(true)
	_inventory.equip(equipped, instance_id)
	var weapon: int = _combat.weapon_id(equipped)
	var item: Dictionary = _combat.item_definition(weapon)
	var target_ids: Array[int] = Shapes.affected_targets(
		equipped, item, units, _alliances, primary_id
	)
	if target_ids.is_empty():
		return _failure("INVALID_ATTACK_TARGET")
	var participants: Array = [equipped]
	var forecasts: Dictionary = {}
	var primary: Dictionary = {}
	for target: Dictionary in units:
		if int(target["id"]) == primary_id:
			primary = target
		if int(target["id"]) in target_ids:
			participants.append(target.duplicate(true))
			forecasts[str(int(target["id"]))] = _combat.map_attack_forecast(
				equipped, target, commander
			)
	return {
		"ok": true,
		"actionMode": "map_attack",
		"actor": actor["id"],
		"item": instance_id,
		"weapon": weapon,
		"primary": primary_id,
		"participants": participants,
		"targetIds": target_ids,
		"forecasts": forecasts,
		"rangeCells": available["rangeCells"],
		"affectedCells":
		Shapes.affected_cells(item, primary, Vector2i(_map["width"], _map["height"])),
		"mapEffect": item["mapEffect"]
	}


# Resolve a prepared cast entirely on copies. BattleState alone commits the change set.
func resolve(prepared: Dictionary, commander: Dictionary) -> Dictionary:
	var changed: Array = prepared["participants"].duplicate(true)
	var actor: Dictionary = changed[0]
	var affected: Array = changed.slice(1)
	var resolved: Dictionary = _resolution.resolve_map_attack(actor, affected, commander)
	var indexed: Dictionary = {}
	for current: Dictionary in changed:
		indexed[int(current["id"])] = current
	var broken: Array[Dictionary] = _inventory.broken_items(prepared["participants"], indexed)
	_inventory.cleanup_combat(actor)
	_inventory.cleanup_combat(affected[-1])
	for target: Dictionary in affected:
		if target["hp"] <= 0:
			target["visible"] = false
			target["flags"] |= 1
	actor["action"] = 2
	var result: Dictionary = prepared.duplicate(true)
	result.merge(
		{
			"kind": "map_attack",
			"hits": resolved["hits"],
			"anyKill": resolved["anyKill"],
			"brokenItems": broken,
			"storyBefore": [],
			"storyAfter": [],
			"changes": changed
		},
		true
	)
	return result


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
