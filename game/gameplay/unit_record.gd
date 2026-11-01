extends RefCounted

const Inventory = preload("res://gameplay/unit_inventory.gd")

# One canonical unit-record validator serves battle saves and completed campaign progress.
var _blueprints: Dictionary = {}
var _jobs: Dictionary = {}
var _growth_rates: Dictionary = {}
var _stat_caps: Dictionary
var _combat: RefCounted
var _bounds: Rect2i


func _init(content: Dictionary, combat: RefCounted) -> void:
	_combat = combat
	_stat_caps = content["rules"]["statCaps"]
	_bounds = Rect2i(0, 0, int(content["map"]["width"]), int(content["map"]["height"]))
	for unit: Dictionary in content["units"]:
		_blueprints[int(unit["id"])] = unit
	for job: Dictionary in content["rules"]["jobTemplates"]:
		_jobs[int(job["id"])] = job
	for growth: Dictionary in content["rules"]["growthRates"]:
		_growth_rates[int(growth["id"])] = growth


func decode(value: Dictionary, held_ids: Dictionary) -> Dictionary:
	if not _nonnegative_integer(value.get("id")) or not _blueprints.has(int(value["id"])):
		return _failure("INVALID_SAVE_IDENTITY")
	var id: int = int(value["id"])
	var current: Dictionary = _blueprints[id].duplicate(true)
	# Static names, sprites and anchors are chapter content, not save authority.
	for key: String in [
		"id",
		"sourceId",
		"faction",
		"classId",
		"classGroup",
		"flags",
		"equipMask",
		"dropTemplateId",
		"policy",
		"growthTemplateId",
		"formal",
		"visible",
		"level",
		"hp",
		"maxHp",
		"move",
		"experience",
		"proficiency",
		"action",
		"x",
		"y",
		"attributes",
		"inventory",
		"equippedInstanceId"
	]:
		if not value.has(key):
			return _failure("INVALID_SAVE_UNIT_FIELD")
		current[key] = (
			value[key].duplicate(true)
			if value[key] is Dictionary or value[key] is Array
			else value[key]
		)
	current["id"] = id
	for key: String in [
		"sourceId",
		"faction",
		"classId",
		"classGroup",
		"flags",
		"equipMask",
		"dropTemplateId",
		"policy",
		"growthTemplateId"
	]:
		if not _integer_in(current.get(key), 0, 255):
			return _failure("INVALID_SAVE_UNIT_FIELD")
		current[key] = int(current[key])
	if (
		current["sourceId"] != _blueprints[id]["sourceId"]
		or current["faction"] != _blueprints[id]["faction"]
		or not current.get("formal") is bool
		or current["formal"] != _blueprints[id]["formal"]
		or not current.get("visible") is bool
	):
		return _failure("INVALID_SAVE_IDENTITY")
	if (
		not _jobs.has(current["classId"])
		or current["classGroup"] != _jobs[current["classId"]]["classGroup"]
		or current["equipMask"] != _jobs[current["classId"]]["equipMask"]
		or not _growth_rates.has(current["growthTemplateId"])
	):
		return _failure("INVALID_SAVE_CLASS")
	for key: String in [
		"level", "hp", "maxHp", "move", "experience", "proficiency", "action", "x", "y"
	]:
		if not _integer_in(current.get(key), 0, 32767):
			return _failure("INVALID_SAVE_UNIT_FIELD")
		current[key] = int(current[key])
	if (
		current["level"] < 1
		or current["level"] > 20
		or current["maxHp"] < 1
		or current["maxHp"] > int(_stat_caps["maxHp"])
		or current["hp"] > current["maxHp"]
		or (current["hp"] == 0 and current["visible"])
		or current["move"] > int(_stat_caps["move"])
		or current["experience"] > 99
		or current["action"] not in [0, 2]
		or not _bounds.has_point(Vector2i(current["x"], current["y"]))
	):
		return _failure("INVALID_SAVE_UNIT_STATE")
	if not current.get("attributes") is Dictionary:
		return _failure("INVALID_SAVE_ATTRIBUTES")
	for stat: String in ["strength", "skill", "speed", "defense", "magic", "luck"]:
		if not _integer_in(current["attributes"].get(stat), 0, int(_stat_caps[stat])):
			return _failure("INVALID_SAVE_ATTRIBUTES")
		current["attributes"][stat] = int(current["attributes"][stat])
	if (
		not current.get("inventory") is Array
		or current["inventory"].size() > Inventory.BAG_CAPACITY
		or not validate_inventory(current["inventory"], held_ids)
		or not current.get("equippedInstanceId") is String
	):
		return _failure("INVALID_SAVE_INVENTORY")
	var equipped_valid: bool = current["equippedInstanceId"].is_empty()
	for item: Dictionary in current["inventory"]:
		if item["id"] == current["equippedInstanceId"]:
			equipped_valid = _combat.can_equip(current, item)
	if not equipped_valid:
		return _failure("INVALID_SAVE_EQUIPMENT")
	return {"ok": true, "unit": current}


func validate_inventory(inventory: Array, ids: Dictionary) -> bool:
	for value: Variant in inventory:
		if (
			not value is Dictionary
			or not value.get("id") is String
			or value["id"].is_empty()
			or ids.has(value["id"])
			or not _nonnegative_integer(value.get("templateId"))
			or value["templateId"] <= 0
			or not _integer_in(value.get("durability"), 0, 127)
		):
			return false
		value["templateId"] = int(value["templateId"])
		value["durability"] = int(value["durability"])
		if _combat.item_definition(value["templateId"]).is_empty():
			return false
		ids[value["id"]] = true
	return true


func _nonnegative_integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= 0
	)


func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and float(value) >= minimum
		and float(value) <= maximum
	)


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
