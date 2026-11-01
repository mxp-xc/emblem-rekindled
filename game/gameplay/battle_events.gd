extends RefCounted

const MapRules = preload("res://gameplay/map_rules.gd")
var _rules: Dictionary
var _turn_events: Array
var _ai_changes: Array
var _combat_events: Array
var _movement: RefCounted


func _init(content: Dictionary) -> void:
	_rules = content["story"]["outcomeRules"]
	_turn_events = content["story"]["turnEvents"]
	_ai_changes = content["story"]["aiChanges"]
	_combat_events = content["story"].get("combatEvents", [])
	_movement = MapRules.new(content["map"], content["rules"]["alliances"])


func outcome(units: Array, round_number: int = 1) -> Dictionary:
	var indexed: Dictionary = {}
	for unit: Dictionary in units:
		indexed[int(unit["id"])] = unit
	for check: Dictionary in _rules["checks"]:
		var result: Dictionary = _outcome_check(check, indexed, round_number)
		if not result.is_empty():
			return result
	return {}


func _outcome_check(check: Dictionary, units: Dictionary, round_number: int) -> Dictionary:
	var reason: String = ""
	var fallen: int = -1
	match check["condition"]:
		"unitRetired":
			var target: Dictionary = units.get(int(check["unitId"]), {})
			if target.is_empty() or target["hp"] <= 0 or not target["visible"]:
				reason = "boss_defeated"
		"allEnemiesDefeated", "noVisibleEnemies":
			var remaining: bool = false
			for unit: Dictionary in units.values():
				if (
					unit["faction"] == check["faction"]
					and unit["visible"]
					and (check["condition"] == "noVisibleEnemies" or unit["hp"] > 0)
				):
					remaining = true
					break
			if not remaining:
				reason = "all_enemies_defeated"
		"requiredUnitFallen":
			for id: Variant in check["unitIds"]:
				var unit: Dictionary = units.get(int(id), {})
				if not unit.is_empty() and unit["hp"] <= 0 and not unit["visible"]:
					reason = "required_unit_fallen"
					fallen = int(id)
					break
		"escaped":
			var actor: Dictionary = units.get(int(check["unitId"]), {})
			if not actor.is_empty() and actor["y"] >= check["row"] and actor["action"] == 2:
				reason = "escaped"
		"roundAfter":
			if round_number > check["round"]:
				reason = "survived"
	if reason.is_empty():
		return {}
	var result: Dictionary = {"kind": check["kind"], "reason": check.get("reason", reason)}
	if fallen >= 0:
		result["unit"] = fallen
	return result


func combat_events(participants: Array, battle_units: Array, completed: Dictionary) -> Dictionary:
	var before: Array[String] = []
	var retirements: Array[Dictionary] = []
	var markers: Array[String] = []
	var flags: Dictionary = {}
	var initial: Dictionary = {}
	var current: Dictionary = {}
	for unit: Dictionary in participants:
		initial[int(unit["id"])] = unit
	for unit: Dictionary in battle_units:
		current[int(unit["id"])] = unit
	var retiring: Dictionary = {}
	for unit: Dictionary in participants:
		var id: int = int(unit["id"])
		if unit["hp"] <= 0 or not current.has(id) or current[id]["hp"] > 0:
			continue
		var death_before: Array[String] = []
		var death_after: Array[String] = []
		var retirement: Dictionary = {
			"unitId": id, "beforeRetirement": death_before, "afterRetirement": death_after
		}
		retiring[id] = retirement
		retirements.append(retirement)
	var enemy: Dictionary = {}
	if participants.size() >= 2:
		enemy = participants[0] if participants[0]["faction"] == 2 else participants[1]
		if (int(enemy["flags"]) & 4) == 0:
			flags[int(enemy["id"])] = 4
	for event: Dictionary in _combat_events:
		var id: int = int(event["unitId"])
		if completed.get(event["id"], false) or not initial.has(id):
			continue
		match event["trigger"]:
			"firstCombat":
				if enemy.get("id") != id or not flags.has(id):
					continue
				before.append(event["sequence"])
			"unitDeath":
				if not retiring.has(id):
					continue
				for phase: String in ["beforeRetirement", "afterRetirement"]:
					if event.has(phase):
						retiring[id][phase].append(event[phase])
		markers.append(event["id"])
	return {"before": before, "retirements": retirements, "completed": markers, "flags": flags}


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
