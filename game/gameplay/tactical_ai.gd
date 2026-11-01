extends RefCounted

const Combat = preload("res://gameplay/combat_rules.gd")
const MapRules = preload("res://gameplay/map_rules.gd")
const MapAttacks = preload("res://gameplay/map_attack_rules.gd")
var _combat: RefCounted
var _movement: RefCounted
var _map: Dictionary
var _rules: Dictionary
var _alliances: Array
var _priorities: Array
var _friends: Array = []
var _enemies: Array = []
var _occupants: Dictionary = {}
var _powers: Dictionary = {}
var _commander: Dictionary = {}
var _strategic := Vector2i(-1, -1)
var _approach: Dictionary = {}


func _init(content: Dictionary) -> void:
	_map = content["map"]
	_rules = content["rules"]
	_alliances = _rules["alliances"]
	_priorities = _rules["aiClassOrder"]
	_combat = Combat.new(_rules, _map["terrain"])
	_movement = MapRules.new(_map, _alliances)


func order(units: Array, phase: int) -> Array[int]:
	var ordered: Array[Dictionary] = []
	for actor: Dictionary in units:
		if (
			not actor["visible"]
			or actor["hp"] <= 0
			or actor["faction"] != phase
			or actor.get("action", 0) != 0
		):
			continue
		var slot: int = ordered.size()
		for index: int in range(ordered.size()):
			var previous: Dictionary = ordered[index]
			var priority: int = int(_priorities[int(actor["classGroup"])])
			var previous_priority: int = int(_priorities[int(previous["classGroup"])])
			if (
				priority < previous_priority
				or (
					priority == previous_priority
					and actor["maxHp"] - actor["hp"] < previous["maxHp"] - previous["hp"]
				)
			):
				slot = index
				break
		ordered.insert(slot, actor)
	var ids: Array[int] = []
	for actor: Dictionary in ordered:
		ids.append(int(actor["id"]))
	return ids


func plan(
	actor: Dictionary,
	units: Array,
	commander: Dictionary,
	policy: int,
	round_number: int,
	assignments: Dictionary = {}
) -> Dictionary:
	_commander = commander
	_friends = []
	_enemies = []
	_occupants = {}
	_powers = {}
	for current: Dictionary in units:
		if not current["visible"] or current["hp"] <= 0:
			continue
		_occupants[_cell(current)] = current
		_powers[int(current["id"])] = _combat.power(current, commander)
		if _alliances[int(current["faction"])] == _alliances[int(actor["faction"])]:
			_friends.append(current)
		else:
			_enemies.append(current)
	var allocation: Dictionary = _choose_strategic(actor, policy, assignments)
	_approach = {} if _strategic.x < 0 else _movement.field(actor, units, _strategic, 10)
	var field: Dictionary = _movement.field(actor, units)
	var enemies: Array = _enemies.duplicate()
	var friends: Array = _friends.duplicate()
	enemies.sort_custom(_coordinate_order)
	friends.sort_custom(_coordinate_order)
	var best: int = -10000
	var result: Dictionary = {
		"cell": _cell(actor),
		"strategic": _strategic,
		"attackTarget": -1,
		"healTarget": -1,
		"healItem": "",
		"equipItem": "",
		"actionMode": "",
		"mapItem": "",
		"mapPrimary": -1,
		"allocation": allocation
	}
	var chosen_slot: int = -1
	for slot: int in range(mini(2, actor["inventory"].size())):
		var held: Dictionary = actor["inventory"][slot]
		var weapon: int = int(held["templateId"])
		var definition: Dictionary = _combat.item_definition(weapon)
		if (
			held["durability"] <= 0
			or (int(definition["categoryMask"]) & int(actor["equipMask"])) == 0
		):
			weapon = 0
		elif (
			_combat.action_mode(weapon) == "map_attack"
			and not _combat.map_attack_available(weapon, round_number)
		):
			weapon = 0
		definition = _combat.item_definition(weapon)
		var mode: String = _combat.action_mode(weapon)
		if (
			mode == "map_attack"
			and definition["targetRule"]["selection"] == "none"
			and not MapAttacks.affected_targets(actor, definition, units, _alliances).is_empty()
		):
			chosen_slot = slot
			result["cell"] = _cell(actor)
			result["attackTarget"] = -1
			result["healTarget"] = -1
			result["actionMode"] = "map_attack"
			result["mapItem"] = held["id"]
			result["mapPrimary"] = -1
			break
		for y: int in range(int(_map["height"])):
			for x: int in range(int(_map["width"])):
				var cell := Vector2i(x, y)
				var occupant: Dictionary = _occupants.get(cell, {})
				if (
					not field.has(cell)
					or (not occupant.is_empty() and occupant["id"] != actor["id"])
					or ((int(actor.get("policy", 0)) & 4) != 0 and cell != _cell(actor))
				):
					continue
				var defend: bool = (
					actor["faction"] == 1
					and not commander.is_empty()
					and actor["classGroup"] not in [7, 8, 9]
					and (policy & 4) != 0
				)
				if not defend and definition["damageKind"] != "healing":
					for target: Dictionary in enemies:
						if not _in_range(cell, target, definition):
							continue
						var score: int = _score(actor, weapon, cell, target)
						if mode == "map_attack":
							var moved: Dictionary = actor.duplicate()
							moved["x"] = cell.x
							moved["y"] = cell.y
							score += (
								150
								* (
									MapAttacks
									. affected_targets(
										moved, definition, units, _alliances, int(target["id"])
									)
									. size()
								)
							)
						if score > best:
							best = score
							chosen_slot = slot
							result["cell"] = cell
							result["attackTarget"] = (
								-1 if mode == "map_attack" else int(target["id"])
							)
							result["healTarget"] = -1
							result["actionMode"] = mode
							result["mapItem"] = held["id"] if mode == "map_attack" else ""
							result["mapPrimary"] = int(target["id"]) if mode == "map_attack" else -1
				if definition["damageKind"] == "healing":
					var heal_candidates: Array = (
						friends if weapon == 53 else (_friends if weapon == 54 else [])
					)
					for target: Dictionary in heal_candidates:
						if (
							target["id"] == actor["id"]
							or target["hp"] == target["maxHp"]
							or (weapon == 53 and not _in_range(cell, target, definition))
						):
							continue
						var score: int = _score(actor, weapon, cell, {}, target)
						if score > best:
							best = score
							result["cell"] = cell
							result["attackTarget"] = -1
							result["healTarget"] = int(target["id"])
							result["healItem"] = held["id"]
							result["actionMode"] = ""
							result["mapItem"] = ""
							result["mapPrimary"] = -1
				var score: int = _score(actor, weapon, cell)
				if score > best:
					best = score
					result["cell"] = cell
					result["attackTarget"] = -1
					result["healTarget"] = -1
					result["actionMode"] = ""
					result["mapItem"] = ""
					result["mapPrimary"] = -1
	if (
		(int(actor.get("policy", 0)) & 2) != 0
		and result["attackTarget"] < 0
		and result["healTarget"] < 0
		and result["actionMode"] != "map_attack"
	):
		result["cell"] = _cell(actor)
	if chosen_slot >= 0:
		var held: Dictionary = actor["inventory"][chosen_slot]
		if _combat.item_definition(int(held["templateId"]))["damageKind"] in ["physical", "magic"]:
			result["equipItem"] = held["id"]
	return result


func _choose_strategic(actor: Dictionary, policy: int, assignments: Dictionary) -> Dictionary:
	_strategic = Vector2i(-1, -1)
	if (
		actor["faction"] == 1
		and not _commander.is_empty()
		and actor["classGroup"] not in [7, 8, 9]
		and (policy & 1) != 0
	):
		_strategic = _cell(_commander)
		return {}
	var armed: bool = _combat.weapon_id(actor) != 0
	var rows: Array[Dictionary] = []
	var closest: int = 10000
	for target: Dictionary in _friends + _enemies:
		var allied: bool = _alliances[int(target["faction"])] == _alliances[int(actor["faction"])]
		var row: Dictionary = {
			"unit": int(target["id"]),
			"cell": _cell(target),
			"score": 0,
			"distance": 0,
			"penalty": 0
		}
		if not allied and not armed:
			row["cell"] = Vector2i.ZERO
			row["score"] = -6666
			rows.append(row)
			continue
		if allied:
			for enemy: Dictionary in _enemies:
				var distance: int = _distance(_cell(target), _cell(enemy))
				if distance >= 1 and distance <= 3:
					row["score"] += _power_at(enemy, _cell(enemy))
		else:
			row["score"] += 2 * _power_at(target, _cell(target))
		if row["score"] > 0:
			row["penalty"] = (
				_power_at(target, _cell(target)) + int(assignments.get(int(target["id"]), 0))
			)
			row["distance"] = maxi(1, _distance(_cell(actor), _cell(target)))
			closest = mini(closest, int(row["distance"]))
		else:
			row["score"] = -6666
		rows.append(row)
	var best: int = -6666 if armed else 10000
	var chosen: Dictionary = {}
	for row: Dictionary in rows:
		var score: int = int(row["score"])
		if armed and score <= -6666:
			continue
		if score > 0:
			score = _quotient(
				score * (closest if armed else int(row["distance"]) - closest), int(row["distance"])
			)
		score -= int(row["penalty"])
		if (armed and score > best) or (not armed and score < best):
			best = score
			chosen = row
	if chosen.is_empty():
		return {}
	_strategic = chosen["cell"]
	return {"unit": chosen["unit"], "power": _power_at(actor, _cell(actor))}


func _score(
	actor: Dictionary, weapon: int, cell: Vector2i, attack: Dictionary = {}, heal: Dictionary = {}
) -> int:
	var score: int = 0
	var movement: int = int(actor["move"])
	var distance_gain: int = _distance(_strategic, _cell(actor)) - _distance(_strategic, cell)
	var approach: int = int(_approach.get(cell, 0))
	var terrain: int = int(_map["terrain"][cell.y][cell.x])
	if _strategic.x >= 0:
		if approach > 0:
			score = 100 + _quotient(100 * approach, 10)
		else:
			if movement > 0:
				score = _quotient(100 * distance_gain, movement)
			if _rules["baseMovementCosts"][terrain] <= 1:
				score += 20
	if not attack.is_empty():
		if (int(actor.get("policy", 0)) & 32) != 0:
			score += maxi(300 * (10 - _distance(_cell(actor), _cell(attack))), 0)
		var moved: Dictionary = actor.duplicate()
		moved["x"] = cell.x
		moved["y"] = cell.y
		if not _combat.can_counter(attack, moved, weapon):
			score += _power_at(actor, cell) * 5
		else:
			score += _quotient(_power_at(actor, cell) * 9, 2) - _power_at(attack, cell)
		if actor["faction"] == 2 and attack["classGroup"] == 11:
			score += 2500
		if (
			weapon == 8
			and int(_combat.item_definition(_combat.weapon_id(attack))["categoryMask"]) == 1
		):
			score += 400
	if not heal.is_empty():
		if _combat.is_named_boss(heal):
			score += 500
		score += 200 + (int(heal["maxHp"]) - int(heal["hp"])) * 15
	score += int(_rules["terrainDefense"][terrain]) * 8 + int(_rules["terrainEvasion"][terrain])
	if actor["hp"] < actor["maxHp"] and terrain == 6:
		score += int(actor["maxHp"]) - int(actor["hp"])
	if approach > 0:
		var cap: int = 10 - _quotient(movement + 1, 2)
		score += 50 + _quotient(100 * mini(approach, cap), cap)
	elif _strategic.x >= 0 and movement > 0:
		score += _quotient(50 * distance_gain, movement)
	if movement > 0:
		score += _quotient(20 * _distance(_cell(actor), cell), movement)
	return score


func _power_at(actor: Dictionary, cell: Vector2i) -> int:
	return int(_powers[int(actor["id"])]) + (15 if int(_map["terrain"][cell.y][cell.x]) == 6 else 0)


func _in_range(cell: Vector2i, target: Dictionary, item: Dictionary) -> bool:
	var distance: int = _distance(cell, _cell(target))
	return distance >= int(item["minRange"]) and distance <= int(item["maxRange"])


func _coordinate_order(first: Dictionary, second: Dictionary) -> bool:
	return first["x"] < second["x"] or (first["x"] == second["x"] and first["y"] < second["y"])


func _cell(actor: Dictionary) -> Vector2i:
	return Vector2i(actor["x"], actor["y"])


func _distance(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)


func _quotient(value: int, divisor: int) -> int:
	return int(float(value) / float(divisor))
