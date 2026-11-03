extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
var _fixed_roll: int
var _roll_count: int = 0


func _initialize() -> void:
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/map_magic_native.json")
	)
	for sample: Dictionary in oracle["cases"]:
		if not _check_case(oracle, sample):
			return
	print(
		"PASS native map attacks: captured caster10, original hits/cleanup, kill XP27, all-miss XP12"
	)
	quit(0)


func _check_case(oracle: Dictionary, sample: Dictionary) -> bool:
	var actor_id: int = int(sample["actorId"])
	var primary_id: int = int(sample["primaryId"])
	var units: Array = _native_integers(sample["before"])
	var content: Dictionary = _content(oracle, units, sample["unitOrder"])
	_fixed_roll = int(sample["fixedRoll"])
	_roll_count = 0
	var battle: RefCounted = Battle.new(content, _roll, false)
	var captured: Dictionary = {}
	for current: Dictionary in units:
		captured[int(current["id"])] = current
	# Native controlled fixtures include HP100/max30 and an overridden class group.
	# Install the exact probe state only here; no production debug loader or save bypass exists.
	battle.set("_units", captured)
	battle.round_number = int(sample["round"])
	var actor_before: Dictionary = captured[actor_id].duplicate(true)
	var item_id: String = actor_before["equippedInstanceId"]
	var result: Dictionary = battle.cast_map_attack(actor_id, item_id, primary_id)
	if not result["ok"]:
		return _fail(sample, "Captured native cast was rejected: " + str(result))
	var expected: Dictionary = _native_integers(sample["expected"])
	var native_ids: Array[int] = []
	for identity: Variant in sample["targetIds"]:
		native_ids.append(int(identity))
	if result["targetIds"] != native_ids or _roll_count != native_ids.size():
		return _fail(sample, "Native target order or one independent hit roll per target differs")
	if result["hits"].size() != expected["nativeResults"].size():
		return _fail(sample, "Native result queue length differs")
	for index: int in range(result["hits"].size()):
		var hit: Dictionary = result["hits"][index]
		var native: Array = expected["nativeResults"][index]
		if (
			hit["hit"] != (int(native[1]) == 0)
			or hit["hpBefore"] != native[3]
			or hit["hpAfter"] != native[4]
			or hit["damage"] != native[5]
		):
			return _fail(sample, "Native hit/miss, HP or damage differs at target " + str(index))
	for after: Dictionary in expected["after"]:
		var current: Dictionary = battle.unit(int(after["id"]))
		for key: String in ["hp", "experience", "proficiency", "inventory", "equippedInstanceId"]:
			if current[key] != after[key]:
				return _fail(
					sample, "Native settlement differs for unit %s field %s" % [after["id"], key]
				)
	for missing: Variant in expected["absentAfter"]:
		var retired: Dictionary = battle.unit(int(missing))
		if retired["hp"] != 0 or retired["visible"]:
			return _fail(sample, "A target absent from native visible rows must retire")
		if retired["inventory"] != captured[int(missing)]["inventory"]:
			return _fail(
				sample, "The native map path must retain the defeated target's marked drop"
			)
	var native_actor: Dictionary = {}
	for after: Dictionary in expected["after"]:
		if int(after["id"]) == actor_id:
			native_actor = after
	var reward: Dictionary = result["rewards"]["experience"]
	if (
		expected["experiencePanels"] != 1
		or reward.get("unit") != actor_id
		or reward.get("amount") != int(native_actor["experience"]) - int(actor_before["experience"])
		or not result["rewards"]["loot"].is_empty()
	):
		return _fail(sample, "The one native XP reward or ordinary-loot exclusion differs")
	return true


func _content(oracle: Dictionary, units: Array, unit_order: Array) -> Dictionary:
	var rules: Dictionary = oracle["rules"].duplicate(true)
	# Movement is not exercised by these captured attack probes.
	rules["baseMovementCosts"] = [1]
	# These command-routing fields are modern metadata; all numeric combat tables above
	# remain the retained original values, independent from current generated content.
	for item: Dictionary in rules["itemTemplates"]:
		if item["damageKind"] in ["physical", "magic"]:
			item["actionMode"] = "battle_clip"
		if int(item["id"]) == 50:
			item["actionMode"] = "map_attack"
			item["targetRule"] = {
				"selection": "hostile_unit", "range": "item", "shape": "cross", "radius": 1
			}
			item["roundRule"] = {"period": 1, "remainder": 0}
			item["mapEffect"] = "wind"
	return {
		"entry": {"id": "native_oracle", "battleId": "m0", "initialParty": [], "recruitByNode": {}},
		"unitOrder": unit_order,
		"units": units,
		"spawns": [],
		"map": oracle["map"].duplicate(true),
		"rules": rules,
		"mapEffects": {"wind": {"kind": "native_oracle"}},
		"story":
		{
			"sequences": {"opening": [], "victory": [{"goldReward": 0}]},
			"worldNode": 0,
			"world": {"routes": [[0, 1]]},
			"routeChoices": [],
			"outcomeRules": {"checks": []},
			"turnEvents": [],
			"aiChanges": [],
			"combatEvents": []
		}
	}


func _roll(limit: int) -> int:
	_roll_count += 1
	return _fixed_roll % limit


func _native_integers(value: Variant) -> Variant:
	# Java captured integral fields; bypassing save decode still requires runtime int types.
	if value is float:
		assert(is_finite(value) and value == floorf(value), "Native capture must contain integers")
		return int(value)
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_native_integers(item))
		return items
	if value is Dictionary:
		var fields: Dictionary = {}
		for key: String in value:
			fields[key] = _native_integers(value[key])
		return fields
	return value


func _fail(sample: Dictionary, message: String) -> bool:
	push_error("Native %s roll%s: %s" % [sample["name"], sample["fixedRoll"], message])
	quit(1)
	return false
