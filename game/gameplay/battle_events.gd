extends RefCounted

const MapRules = preload("res://gameplay/map_rules.gd")
var _rules: Dictionary
var _turn_events: Array
var _ai_changes: Array
var _movement: RefCounted


func _init(content: Dictionary) -> void:
	_rules = content["story"]["outcomeRules"]
	_turn_events = content["story"]["turnEvents"]
	_ai_changes = content["story"]["aiChanges"]
	_movement = MapRules.new(content["map"], content["rules"]["alliances"])


func outcome(units: Array) -> Dictionary:
	var indexed: Dictionary = {}
	var enemy_count: int = 0
	for unit: Dictionary in units:
		indexed[int(unit["id"])] = unit
		if unit["visible"] and unit["hp"] > 0 and unit["faction"] == _rules["enemyFaction"]:
			enemy_count += 1
	if _rules.has("defeatUnitId"):
		var target: Dictionary = indexed.get(int(_rules["defeatUnitId"]), {})
		if target.is_empty() or target["hp"] <= 0 or not target["visible"]:
			return {"kind": "victory", "reason": "boss_defeated"}
	else:
		if enemy_count == 0:
			return {"kind": "victory", "reason": "all_enemies_defeated"}
		var escape: Dictionary = indexed[int(_rules["escapeUnitId"])]
		if escape["y"] >= _rules["escapeRow"] and escape["action"] == 2:
			return {"kind": "victory", "reason": "escaped"}
	for id: Variant in _rules["requiredUnitIds"]:
		var unit: Dictionary = indexed[int(id)]
		if unit["hp"] <= 0 and not unit["visible"]:
			return {"kind": "defeat", "reason": "required_unit_fallen", "unit": int(id)}
	return {}


func reinforce(units: Array, unit_ids: Array) -> Array[Dictionary]:
	var arrivals: Array[Dictionary] = []
	for id: Variant in unit_ids:
		for unit: Dictionary in units:
			if unit["id"] != id or unit["visible"] or unit["hp"] <= 0:
				continue
			var origin := Vector2i(unit["x"], unit["y"])
			var destination := origin
			if not _movement.unit_at(units, destination).is_empty():
				for offset: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]:
					var cell: Vector2i = origin + offset
					if _movement.inside(cell) and _movement.unit_at(units, cell).is_empty():
						destination = cell
						break
			if not _movement.unit_at(units, destination).is_empty():
				continue
			unit["visible"] = true
			unit["flags"] &= ~1
			unit["x"] = destination.x
			unit["y"] = destination.y
			unit["action"] = 0
			arrivals.append({"unit": int(id), "from": origin, "to": destination})
	return arrivals


func turn_events_due(round_number: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in _turn_events:
		if event["afterEnemyPhaseOfRound"] == round_number:
			result.append(event)
	return result


func prepare_enemy_phase(round_number: int, units: Array) -> void:
	for change: Dictionary in _ai_changes:
		if change["beforeEnemyPhaseOfRound"] != round_number:
			continue
		for id: Variant in change["unitIds"]:
			for unit: Dictionary in units:
				if unit["id"] == int(id):
					unit["flags"] |= int(change["flagsSet"])
					unit["policy"] &= ~int(change["policyClear"])
