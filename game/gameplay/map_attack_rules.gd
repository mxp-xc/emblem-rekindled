extends RefCounted


static func valid_definition(item: Dictionary) -> bool:
	if item.get("actionMode", "") != "map_attack":
		return false
	if not item.get("targetRule") is Dictionary or not item.get("roundRule") is Dictionary:
		return false
	var rule: Dictionary = item.get("targetRule", {})
	var rounds: Dictionary = item.get("roundRule", {})
	if (
		not item.get("mapEffect") is String
		or item["mapEffect"].is_empty()
		or not _integer_in(rounds.get("period"), 1, 3)
		or not _integer_in(rounds.get("remainder"), 0, 0)
		or not _integer_in(item.get("minRange"), 0, 100)
		or not _integer_in(item.get("maxRange"), int(item.get("minRange", 0)), 100)
	):
		return false
	if rule.get("shape", "") == "all_hostile":
		return (
			rule.get("selection") == "none"
			and rule.get("range") == "map"
			and not rule.has("radius")
		)
	return (
		rule.get("shape", "") in ["square", "cross"]
		and rule.get("selection") == "hostile_unit"
		and rule.get("range") == "item"
		and _integer_in(rule.get("radius"), 1, 1)
	)


static func round_available(item: Dictionary, round_number: int) -> bool:
	if not valid_definition(item) or round_number < 1:
		return false
	return round_number % int(item["roundRule"]["period"]) == 0


static func primary_targets(
	actor: Dictionary, item: Dictionary, units: Array, alliances: Array
) -> Array[int]:
	var targets: Array[int] = []
	if not valid_definition(item) or item["targetRule"]["selection"] == "none":
		return targets
	for candidate: Dictionary in units:
		if not _hostile(actor, candidate, alliances):
			continue
		var distance: int = _distance(actor, candidate)
		if distance >= int(item["minRange"]) and distance <= int(item["maxRange"]):
			targets.append(int(candidate["id"]))
	return targets


# The caller supplies original deployment order, never snapshot array or ID order.
static func affected_targets(
	actor: Dictionary, item: Dictionary, units: Array, alliances: Array, primary_id: int = -1
) -> Array[int]:
	var targets: Array[int] = []
	if not valid_definition(item):
		return targets
	var rule: Dictionary = item["targetRule"]
	if rule["shape"] == "all_hostile":
		if primary_id != -1:
			return targets
		for candidate: Dictionary in units:
			if _hostile(actor, candidate, alliances):
				targets.append(int(candidate["id"]))
		return targets
	if primary_id not in primary_targets(actor, item, units, alliances):
		return targets
	var primary: Dictionary = {}
	for candidate: Dictionary in units:
		if int(candidate["id"]) == primary_id:
			primary = candidate
			break
	for candidate: Dictionary in units:
		if (
			_live(candidate)
			and alliances[int(candidate["faction"])] == alliances[int(primary["faction"])]
			and _inside_shape(candidate, primary, rule["shape"])
		):
			targets.append(int(candidate["id"]))
	return targets


static func range_cells(actor: Dictionary, item: Dictionary, size: Vector2i) -> Dictionary:
	var cells: Dictionary = {}
	for y: int in range(size.y):
		for x: int in range(size.x):
			var distance: int = absi(x - int(actor["x"])) + absi(y - int(actor["y"]))
			if (
				item.get("targetRule", {}).get("range", "") == "map"
				or (distance >= int(item["minRange"]) and distance <= int(item["maxRange"]))
			):
				cells[Vector2i(x, y)] = 1
	return cells


static func affected_cells(item: Dictionary, primary: Dictionary, size: Vector2i) -> Dictionary:
	var cells: Dictionary = {}
	if not valid_definition(item):
		return cells
	var shape: String = item["targetRule"]["shape"]
	for y: int in range(size.y):
		for x: int in range(size.x):
			if shape == "all_hostile" or _inside_shape({"x": x, "y": y}, primary, shape):
				cells[Vector2i(x, y)] = 1
	return cells


static func _inside_shape(candidate: Dictionary, primary: Dictionary, shape: String) -> bool:
	var dx: int = absi(int(candidate["x"]) - int(primary["x"]))
	var dy: int = absi(int(candidate["y"]) - int(primary["y"]))
	return maxi(dx, dy) <= 1 if shape == "square" else dx + dy <= 1


static func _distance(first: Dictionary, second: Dictionary) -> int:
	return absi(int(first["x"]) - int(second["x"])) + absi(int(first["y"]) - int(second["y"]))


static func _hostile(actor: Dictionary, candidate: Dictionary, alliances: Array) -> bool:
	return (
		_live(candidate)
		and alliances[int(actor["faction"])] != alliances[int(candidate["faction"])]
	)


static func _live(unit: Dictionary) -> bool:
	return unit["visible"] and int(unit["hp"]) > 0


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)
