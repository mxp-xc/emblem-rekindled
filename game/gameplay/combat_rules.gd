extends RefCounted

const HOLY: Array[int] = [9, 18, 26, 37]
const MapAttacks = preload("res://gameplay/map_attack_rules.gd")
var _items: Dictionary = {}
var _terrain: Array
var _defense: Array
var _evasion: Array


func _init(definitions: Dictionary, terrain: Array) -> void:
	for item: Dictionary in definitions["itemTemplates"]:
		_items[int(item["id"])] = item
	_terrain = terrain
	_defense = definitions["terrainDefense"]
	_evasion = definitions["terrainEvasion"]


func item_definition(id: int) -> Dictionary:
	return _items.get(id, {})


func action_mode(template_id: int) -> String:
	var mode: Variant = item_definition(template_id).get("actionMode", "")
	return mode if mode is String else ""


func map_attack_available(template_id: int, round_number: int) -> bool:
	return MapAttacks.round_available(item_definition(template_id), round_number)


func map_attack_forecast(
	actor: Dictionary, target: Dictionary, commander: Dictionary = {}
) -> Dictionary:
	var weapon: int = weapon_id(actor)
	var damage: int = _damage(actor, weapon, target, false, commander)
	return {
		"weapon": weapon,
		"damage": damage,
		"criticalDamage": damage,
		"hit": _hit(actor, weapon, target, commander),
		"critical": 0,
		"double": false,
		"canCounter": false
	}


func can_equip(actor: Dictionary, held: Dictionary) -> bool:
	var definition: Dictionary = item_definition(int(held["templateId"]))
	return (
		not definition.is_empty()
		and held["durability"] > 0
		and definition["damageKind"] in ["physical", "magic"]
		and (int(definition["categoryMask"]) & int(actor["equipMask"])) != 0
	)


func is_named_boss(actor: Dictionary) -> bool:
	return actor["faction"] == 2 and actor["id"] >= 80 and actor["id"] <= 94


func weapon_id(unit: Dictionary) -> int:
	for item: Dictionary in unit["inventory"]:
		if item["id"] == unit["equippedInstanceId"] and item["durability"] > 0:
			return int(item["templateId"])
	return 0


func forecast(actor: Dictionary, target: Dictionary, commander: Dictionary = {}) -> Dictionary:
	var weapon: int = weapon_id(actor)
	return {
		"weapon": weapon,
		"damage": _damage(actor, weapon, target, false, commander),
		"criticalDamage": _damage(actor, weapon, target, true, commander),
		"hit": _hit(actor, weapon, target, commander),
		"critical": _critical(actor, weapon, target, commander),
		"speed": effective_speed(actor, commander),
		"double": effective_speed(actor, commander) - effective_speed(target, commander) >= 5,
		"canCounter": can_counter(target, actor),
		"advantage": _advantage(actor, target),
	}


func in_range(actor: Dictionary, target: Dictionary, template_id: int) -> bool:
	var item: Dictionary = _items[template_id]
	var distance: int = (
		absi(int(actor["x"]) - int(target["x"])) + absi(int(actor["y"]) - int(target["y"]))
	)
	return distance >= int(item["minRange"]) and distance <= int(item["maxRange"])


func can_counter(actor: Dictionary, target: Dictionary, candidate_weapon: int = -1) -> bool:
	var weapon: int = weapon_id(actor)
	var opposing_weapon: int = weapon_id(target) if candidate_weapon < 0 else candidate_weapon
	if (
		weapon == 0
		or action_mode(weapon) == "map_attack"
		or action_mode(opposing_weapon) == "map_attack"
	):
		return false
	return in_range(actor, target, weapon)


func effective_speed(unit: Dictionary, commander: Dictionary = {}) -> int:
	return (
		int(unit["attributes"]["speed"])
		+ _bonus(unit, "speed", commander)
		- int(_items[weapon_id(unit)]["weight"])
	)


func healing_amount(unit: Dictionary, staff: int) -> int:
	return _damage(unit, staff, {}, false, {})


func information(unit: Dictionary, commander: Dictionary = {}) -> Dictionary:
	var basic: Dictionary = {}
	for stat: String in unit["attributes"]:
		basic[stat] = int(unit["attributes"][stat]) + _bonus(unit, stat, commander)
	basic["move"] = int(unit["move"])
	if _receives_command(unit, commander):
		basic["move"] += maxi(int(commander["move"]) - int(unit["move"]), 0) >> 2
	var weapon: int = weapon_id(unit)
	if weapon <= 0:
		return {
			"basic": basic,
			"attack": "--",
			"critical": "--",
			"hit": "--",
			"avoid": "--",
			"range": "--"
		}
	var item: Dictionary = _items[weapon]
	var minimum: int = int(item["minRange"])
	var maximum: int = int(item["maxRange"])
	var reach: String = str(minimum) if minimum == maximum else "%d–%d" % [minimum, maximum]
	return {
		"basic": basic,
		"attack": str(_damage(unit, weapon, {}, false, commander)),
		"critical": str(_critical(unit, weapon, {}, commander)),
		"hit": str(_hit(unit, weapon, {}, commander)),
		"avoid": str(_avoid(unit, commander)),
		"range": "--" if maximum == 100 else reach
	}


func power(unit: Dictionary, commander: Dictionary = {}) -> int:
	var weapon: int = weapon_id(unit)
	var item: Dictionary = _items[weapon]
	var speed: int = effective_speed(unit, commander)
	var evasion: int = _avoid(unit, commander)
	var attack_score: int = 0
	if item["damageKind"] != "healing":
		attack_score = (
			_damage(unit, weapon, {}, false, commander)
			* 3
			* (_quotient(_hit(unit, weapon, {}, commander), 2) + 50)
		)
		attack_score = _quotient(attack_score, 100)
		attack_score = _quotient(attack_score * (speed + 100), 100)
		if item["damageKind"] == "magic":
			attack_score = _quotient(attack_score * 12, 10)
		if weapon in HOLY:
			attack_score = _quotient(attack_score * 15, 10)
		if item["doubleStrike"]:
			attack_score = _quotient(attack_score * 13, 10)
		attack_score = _quotient(attack_score * (_critical(unit, weapon, {}, commander) + 100), 100)
	var physical_score: int = _physical_defense(unit, commander) * 3
	physical_score = _quotient(physical_score * (_quotient(evasion, 2) + 100), 100)
	physical_score = _quotient(physical_score * (speed + 100), 100)
	var magic_score: int = _magic_defense(unit, commander) * 3
	magic_score = _quotient(magic_score * (_quotient(evasion, 2) + 100), 100)
	magic_score = _quotient(magic_score * (speed + 100), 100)
	return (
		int(unit["maxHp"])
		+ attack_score
		+ physical_score
		+ magic_score
		+ int(unit["move"])
		+ (1000 if int(unit["classGroup"]) == 10 else 0)
	)


func _damage(
	actor: Dictionary, weapon: int, target: Dictionary, critical: bool, commander: Dictionary
) -> int:
	if weapon == 0:
		return 0
	var item: Dictionary = _items[weapon]
	var value: int = 0
	if item["damageKind"] == "physical":
		var strength: int = int(item["power"])
		if _effective(weapon, target):
			strength *= 2
		value = (
			int(actor["attributes"]["strength"]) + _bonus(actor, "strength", commander) + strength
		)
	elif item["damageKind"] == "healing":
		value = int(actor["attributes"]["magic"]) + 10
	else:
		value = (
			int(actor["attributes"]["magic"])
			+ _bonus(actor, "magic", commander)
			+ int(item["power"])
		)
	if not target.is_empty():
		value += _advantage(actor, target)
		if weapon == 28:
			value += int(actor["maxHp"]) - int(actor["hp"])
		if not item["ignoresDefense"]:
			if item["damageKind"] == "physical":
				value -= _physical_defense(target, commander)
			elif item["damageKind"] == "magic":
				value -= _magic_defense(target, commander)
		if critical:
			value *= 2
		if weapon_id(target) == 35 or _has(target, 83):
			value >>= 1
	return maxi(value, 1)


func _hit(actor: Dictionary, weapon: int, target: Dictionary, commander: Dictionary) -> int:
	var value: int = (
		3 * (int(actor["attributes"]["skill"]) + _bonus(actor, "skill", commander))
		+ int(_items[weapon]["hit"])
		+ _proficiency(actor, commander)
	)
	if not target.is_empty():
		value += _advantage(actor, target) * 15
	value = clampi(value, 0, 200)
	if not target.is_empty():
		value = clampi(value - _avoid(target, commander), 0, 100)
	return value


func _critical(actor: Dictionary, weapon: int, target: Dictionary, commander: Dictionary) -> int:
	var value: int = (
		int(actor["attributes"]["skill"])
		+ _bonus(actor, "skill", commander)
		+ int(_items[weapon]["critical"])
		+ _proficiency(actor, commander)
	)
	if _has(actor, 82):
		value += int(actor["maxHp"]) - int(actor["hp"])
	if _has(actor, 84) or (not target.is_empty() and _has(target, 84)):
		value = 0
	return mini(value, 99)


func _physical_defense(unit: Dictionary, commander: Dictionary) -> int:
	var value: int = (
		int(unit["attributes"]["defense"])
		+ _bonus(unit, "defense", commander)
		+ int(_defense[_terrain_at(unit)])
	)
	if _has(unit, 65):
		value += 4
	elif _has(unit, 66):
		value += 8
	return value


func _magic_defense(unit: Dictionary, commander: Dictionary) -> int:
	var value: int = (int(unit["attributes"]["magic"]) + _bonus(unit, "magic", commander)) >> 1
	return value + (4 if _has(unit, 67) else 0)


func _avoid(unit: Dictionary, commander: Dictionary) -> int:
	return clampi(
		(
			2 * effective_speed(unit, commander)
			+ int(unit["attributes"]["luck"])
			+ _bonus(unit, "luck", commander)
			+ int(_evasion[_terrain_at(unit)])
		),
		0,
		200
	)


func _bonus(unit: Dictionary, stat: String, commander: Dictionary) -> int:
	var value: int = 0
	if stat == "strength" and int(unit["flags"]) & 8:
		value = 5
	elif stat == "magic" and int(unit["flags"]) & 32:
		value = 5
	if _receives_command(unit, commander):
		var difference: int = int(commander["attributes"][stat]) - int(unit["attributes"][stat])
		if difference > 0:
			value += difference >> 2
	return value


func _proficiency(unit: Dictionary, commander: Dictionary) -> int:
	var value: int = _quotient(int(unit["proficiency"]), 10)
	if _receives_command(unit, commander):
		value += int(commander["proficiency"]) >> 1
	return mini(value, 99)


func _receives_command(unit: Dictionary, commander: Dictionary) -> bool:
	return (
		not commander.is_empty()
		and unit["faction"] == 1
		and int(unit["classGroup"]) not in [7, 8, 9]
	)


func _advantage(actor: Dictionary, target: Dictionary) -> int:
	var first: int = weapon_id(actor)
	var second: int = weapon_id(target)
	if (
		first in [29, 30]
		or second in [29, 30]
		or _effective(first, target)
		or _effective(second, actor)
	):
		return 0
	var first_type: int = int(_items[first]["categoryMask"])
	var second_type: int = int(_items[second]["categoryMask"])
	if [first_type, second_type] in [[1, 4], [4, 2], [2, 1]]:
		return 1
	if [second_type, first_type] in [[1, 4], [4, 2], [2, 1]]:
		return -1
	var first_magic: int = _magic_group(first)
	var second_magic: int = _magic_group(second)
	if first_magic >= 0 and second_magic >= 0:
		if (first_magic + 1) % 3 == second_magic:
			return 1
		if (second_magic + 1) % 3 == first_magic:
			return -1
	return 0


func _magic_group(template_id: int) -> int:
	if template_id in [40, 41]:
		return 0
	if template_id in [44, 45]:
		return 1
	if template_id in [42, 43]:
		return 2
	return -1


func _effective(weapon: int, target: Dictionary) -> bool:
	return not target.is_empty() and int(target["classGroup"]) in _items[weapon]["effectiveGroups"]


func _has(unit: Dictionary, template_id: int) -> bool:
	for item: Dictionary in unit["inventory"]:
		if int(item["templateId"]) == template_id:
			return true
	return false


func _terrain_at(unit: Dictionary) -> int:
	return int(_terrain[int(unit["y"])][int(unit["x"])])


func _quotient(value: int, divisor: int) -> int:
	return int(float(value) / float(divisor))


func experience_gain(
	actor: Dictionary,
	target: Dictionary,
	killed: bool,
	hit: bool,
	borrowed: bool,
	commander: Dictionary = {}
) -> int:
	if actor["level"] >= 20 or actor["classGroup"] in [7, 8, 9]:
		return 0
	if not hit:
		return 1
	var gains: Array[int] = [12, 11, 11, 10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 5, 4, 3, 2, 2, 1, 1]
	var amount: int = gains[int(actor["level"]) - 1]
	if killed and not target.is_empty():
		var named_boss: bool = is_named_boss(target)
		var difference: int = _quotient(power(target, commander) - power(actor, commander), 3)
		amount = maxi((40 if named_boss else 30) + difference, 30 if named_boss else 10)
		var divisor: int = int(actor["level"]) - int(target["level"]) - 1
		if not named_boss and divisor > 0:
			amount = _quotient(amount, divisor)
		amount = mini(amount, 100)
		if borrowed:
			amount = _quotient(amount, 2)
	if weapon_id(actor) == 7:
		amount *= 2
	return amount
