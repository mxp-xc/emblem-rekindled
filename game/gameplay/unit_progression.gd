extends RefCounted

# Finite chapter promotion rules are exported from the original job tables.
var _promotions: Array
var _jobs: Dictionary = {}
var _caps: Dictionary


func _init(rules: Dictionary) -> void:
	_promotions = rules.get("promotions", [])
	_caps = rules["statCaps"]
	for job: Dictionary in rules["jobTemplates"]:
		_jobs[int(job["id"])] = job


func definition(class_id: int) -> Dictionary:
	for promotion: Dictionary in _promotions:
		if int(promotion["fromClassId"]) == class_id:
			return promotion
	return {}


func eligible(actor: Dictionary, automatic: bool = false) -> bool:
	var promotion: Dictionary = definition(int(actor["classId"]))
	return (
		actor["faction"] == 0
		and not promotion.is_empty()
		and (
			actor["level"] == promotion["minimumLevel"]
			if automatic
			else actor["level"] >= promotion["minimumLevel"]
		)
	)


func bounds(blueprint: Dictionary, class_id: int) -> Dictionary:
	var caps: Dictionary = _caps.duplicate(true)
	if (
		blueprint.get("faction") == 2
		and (
			(int(blueprint["id"]) >= 80 and int(blueprint["id"]) <= 94)
			or blueprint.get("bossInheritedStats", false)
		)
	):
		for stat: String in ["strength", "skill", "speed", "defense", "magic", "luck", "maxHp"]:
			caps[stat] = 99
		return caps
	# promotionBaseClassId is chapter/profile authority; UnitRecord never copies it from a save.
	if blueprint.get("faction") != 0 or not blueprint.has("promotionBaseClassId"):
		return caps
	var promotion: Dictionary = definition(int(blueprint["promotionBaseClassId"]))
	if promotion.is_empty() or int(promotion["toClassId"]) != class_id:
		return caps
	for stat: String in promotion["gains"]:
		caps[stat] = int(caps[stat]) + int(promotion["gains"][stat])
	return caps


func apply(actor: Dictionary, combat: RefCounted) -> Dictionary:
	if not eligible(actor):
		return {"ok": false, "error": "PROMOTION_NOT_ALLOWED"}
	var promotion: Dictionary = definition(int(actor["classId"]))
	var next_class: int = int(promotion["toClassId"])
	if not _jobs.has(next_class):
		return {"ok": false, "error": "PROMOTION_CLASS_UNAVAILABLE"}
	var before: Dictionary = actor.duplicate(true)
	var job: Dictionary = _jobs[next_class]
	actor["classId"] = next_class
	actor["classGroup"] = int(job["classGroup"])
	actor["equipMask"] = int(job["equipMask"])
	actor["className"] = job["name"]
	for stat: String in promotion["gains"]:
		if stat in ["maxHp", "move"]:
			actor[stat] += int(promotion["gains"][stat])
		else:
			actor["attributes"][stat] += int(promotion["gains"][stat])
	for held: Dictionary in actor["inventory"]:
		if held["id"] == actor["equippedInstanceId"] and not combat.can_equip(actor, held):
			actor["equippedInstanceId"] = ""
	return {
		"ok": true,
		"unit": actor["id"],
		"classBefore": before["classId"],
		"classAfter": next_class,
		"equipMaskBefore": before["equipMask"],
		"equipMaskAfter": actor["equipMask"],
		"increments": promotion["gains"].duplicate(true),
		"before": _stats(before),
		"after": _stats(actor)
	}


func _stats(actor: Dictionary) -> Dictionary:
	var result: Dictionary = actor["attributes"].duplicate(true)
	result["maxHp"] = actor["maxHp"]
	result["move"] = actor["move"]
	return result
