extends RefCounted


static func is_valid(value: Variant) -> bool:
	if value == null:
		return true
	if not value is Dictionary or not value.get("attributes") is Dictionary:
		return false
	for stat: String in ["strength", "skill", "speed", "defense", "magic", "luck"]:
		if not _integer_in(value["attributes"].get(stat), 127):
			return false
	if not _integer_in(value.get("maxHp"), 127):
		return false
	for field: String in ["maxInternalLevel", "averageInternalLevel"]:
		if not _integer_in(value.get(field), 19):
			return false
	return _integer_in(value.get("maxProficiency"), 99)


static func _integer_in(value: Variant, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= 0
		and value <= maximum
	)


static func accumulate(previous: Variant, units: Array) -> Variant:
	var result: Dictionary = (
		previous.duplicate(true)
		if previous != null
		else {
			"attributes":
			{"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
			"maxHp": 0,
			"maxInternalLevel": 0,
			"averageInternalLevel": 0,
			"maxProficiency": 0
		}
	)
	var total_level: int = 0
	var count: int = 0
	for unit: Dictionary in units:
		if int(unit["faction"]) != 0:
			continue
		count += 1
		var level: int = int(unit["level"]) - 1
		total_level += level
		result["maxInternalLevel"] = maxi(int(result["maxInternalLevel"]), level)
		result["maxHp"] = maxi(int(result["maxHp"]), int(unit["maxHp"]))
		result["maxProficiency"] = maxi(
			int(result["maxProficiency"]), mini(99, int(int(unit["proficiency"]) / 10))
		)
		for stat: String in result["attributes"]:
			result["attributes"][stat] = maxi(
				int(result["attributes"][stat]), int(unit["attributes"][stat])
			)
	if count == 0:
		return previous
	result["averageInternalLevel"] = int(total_level / count)
	return result
