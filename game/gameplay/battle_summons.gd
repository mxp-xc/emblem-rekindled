extends RefCounted

const Deployment = preload("res://gameplay/battle_deployment.gd")
const CLASS_POOL: Array[int] = [28, 28, 28, 29, 32, 32, 32, 33, 36, 36, 36, 37]
const NEIGHBORS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]
var _content: Dictionary
var _combat: RefCounted
var _inventory: RefCounted
var _roll: Callable


func _init(content: Dictionary, combat: RefCounted, inventory: RefCounted, roll: Callable) -> void:
	_content = content
	_combat = combat
	_inventory = inventory
	_roll = roll


# Availability is a pure query; dead hidden identities are only replaced on commit.
static func placement(actor: Dictionary, units: Array, map: Dictionary) -> Dictionary:
	var first: int = 70 if int(actor["faction"]) == 2 else 20
	var identity: int = -1
	var by_id: Dictionary = {}
	var occupied: Dictionary = {}
	for current: Dictionary in units:
		by_id[int(current["id"])] = current
		if current["visible"]:
			occupied[Vector2i(current["x"], current["y"])] = true
	for candidate: int in range(first, first + 10):
		if (
			not by_id.has(candidate)
			or (not by_id[candidate]["visible"] and by_id[candidate]["hp"] <= 0)
		):
			identity = candidate
			break
	if identity < 0:
		return _failure("SUMMON_POOL_FULL")
	var origin := Vector2i(actor["x"], actor["y"])
	var bounds := Rect2i(0, 0, int(map["width"]), int(map["height"]))
	for offset: Vector2i in NEIGHBORS:
		var cell: Vector2i = origin + offset
		if bounds.has_point(cell) and not occupied.has(cell):
			return {"ok": true, "unitId": identity, "from": origin, "to": cell}
	return _failure("NO_SUMMON_SPACE")


func birth(
	actor: Dictionary,
	units: Array,
	warehouse: Array,
	summon_state: Dictionary,
	after_clone_generation: int = 0
) -> Dictionary:
	var chosen: Dictionary = placement(actor, units, _content["map"])
	if not chosen["ok"]:
		return chosen
	var generation: int = int(summon_state.get("nextGeneration", 1))
	var level: int = maxi(1, int(actor["level"]) - 2 + int(_roll.call(5)))
	var job: int = CLASS_POOL[int(_roll.call(CLASS_POOL.size()))]
	if level >= 10:
		job = int(job / 4) * 4 + 1
	var faction: int = 1 if actor["faction"] == 0 else int(actor["faction"])
	var binding: Dictionary = {
		"unitId": chosen["unitId"],
		"generation": generation,
		"classId": job,
		"faction": faction,
		"afterCloneGeneration": after_clone_generation
	}
	var registry: Dictionary = _content.get("_library", {}).get("summons", {})
	var family: Dictionary = blueprint(registry, _content["_library"]["profiles"], binding)
	if not family["ok"]:
		return family
	var group: int = int(job / 4)
	var weapon: int = 29 if group == 7 else 30 if group == 8 else 40 + int(_roll.call(6))
	var unit: Dictionary = family["unit"]
	unit["sprite"] = _content.get("_textureOverrides", {}).get(unit["sprite"], unit["sprite"])
	var spawn: Dictionary = {
		"id": chosen["unitId"],
		"sourceId": chosen["unitId"],
		"classId": job,
		"faction": faction,
		"formal": false,
		"flags": 0,
		"policy": 0,
		"visible": true,
		"level": level,
		"growthTemplateId": 10 + group,
		"baseTemplateId": 10 + job,
		"initialGrowthTemplateId": 10 + group,
		"initialWeaponId": weapon,
		"randomEquipment": false,
		"itemChoices": [weapon],
		"dropTemplateId": 0,
		"position": [chosen["to"].x, chosen["to"].y]
	}
	var content: Dictionary = _content.duplicate()
	content["units"] = [unit]
	content["spawns"] = [spawn]
	var initialized: Dictionary = Deployment.new(content, _combat, _inventory, _roll).create()
	unit = initialized["units"][int(chosen["unitId"])]
	var held_ids: Dictionary = {}
	for current: Dictionary in units:
		for held: Dictionary in current["inventory"]:
			held_ids[held["id"]] = true
	for held: Dictionary in warehouse:
		held_ids[held["id"]] = true
	for index: int in range(unit["inventory"].size()):
		var held: Dictionary = unit["inventory"][index]
		var previous: String = held["id"]
		var candidate: String = (
			"%s:%s:summon_%d:item_%d"
			% [_content["entry"]["id"], _content["entry"]["battleId"], generation, index]
		)
		var fresh: String = candidate
		var suffix: int = 1
		while held_ids.has(fresh):
			fresh = "%s:%d" % [candidate, suffix]
			suffix += 1
		held["id"] = fresh
		if unit["equippedInstanceId"] == previous:
			unit["equippedInstanceId"] = fresh
		held_ids[fresh] = true
	return {
		"ok": true, "unit": unit, "binding": binding, "from": chosen["from"], "to": chosen["to"]
	}


# The shared catalog declares the source appearances a summoned actor may use.
static func blueprint(
	registry: Dictionary, profiles: Dictionary, binding: Dictionary
) -> Dictionary:
	var identity: int = int(binding.get("unitId", -1))
	var faction: int = int(binding.get("faction", -1))
	var job: int = int(binding.get("classId", -1))
	var key: String = _profile_key(registry, faction, job, identity)
	if key.is_empty() or not profiles.get(key) is Dictionary:
		return _failure("MISSING_SUMMON_PROFILE")
	var source: Variant = profiles[key].get("unit")
	if not source is Dictionary or source.get("classId") != job or source.get("faction") != faction:
		return _failure("INVALID_SUMMON_PROFILE")
	var actor: Dictionary = source.duplicate(true)
	for field: String in ["deploymentIndex", "deploymentSlot", "temporary"]:
		actor.erase(field)
	actor.merge(
		{
			"id": identity,
			"sourceId": identity,
			"faction": faction,
			"formal": false,
			"summoned": true,
			"flags": 0,
			"policy": 0,
			"dropTemplateId": 0,
			"visible": false,
			"growthTemplateId": int(source.get("growthTemplateId", 10 + int(job / 4))),
			"level": 1,
			"hp": 1,
			"maxHp": 1,
			"move": 0,
			"experience": 0,
			"proficiency": 0,
			"action": 0,
			"x": 0,
			"y": 0,
			"attributes":
			{"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
			"inventory": [],
			"equippedInstanceId": ""
		},
		true
	)
	return {"ok": true, "unit": actor, "profile": key}


static func saved_bindings(registry: Dictionary, records: Array, state: Dictionary) -> Dictionary:
	if not state.get("units") is Array:
		return _failure("INVALID_SUMMON_SAVE")
	var current: Dictionary = current_bindings(
		registry, records, state["units"], state.get("summonState", {})
	)
	if not current["ok"] or current["bindings"].is_empty():
		return current
	var clones: Variant = state.get("cloneState", {})
	if not clones is Dictionary or not _integer_in(clones.get("nextGeneration", 1), 1, 2147483647):
		return _failure("INVALID_SUMMON_ANCHOR")
	for binding: Dictionary in current["bindings"]:
		if binding["afterCloneGeneration"] >= int(clones.get("nextGeneration", 1)):
			return _failure("INVALID_SUMMON_ANCHOR")
	return current


static func current_bindings(
	registry: Dictionary, records: Array, units: Array, summon_state: Variant
) -> Dictionary:
	var result: Dictionary = {
		"ok": true,
		"staticUnits": units.duplicate(true),
		"bindings": [],
		"nextGeneration": 1,
		"replacedIndices": []
	}
	if summon_state == null or summon_state == {}:
		for actor: Variant in units:
			if actor is Dictionary and actor.get("summoned", false) == true:
				return _failure("UNDECLARED_SUMMON_ACTOR")
		return result
	if (
		not summon_state is Dictionary
		or summon_state.size() != 2
		or not _integer_in(summon_state.get("nextGeneration"), 1, 2147483647)
		or not summon_state.get("bindings") is Array
	):
		return _failure("INVALID_SUMMON_STATE")
	var actors: Dictionary = {}
	for value: Variant in units:
		if not value is Dictionary or not _integer_in(value.get("id"), 0, 2147483647):
			return _failure("INVALID_SUMMON_ACTOR")
		var identity: int = int(value["id"])
		if actors.has(identity):
			return _failure("INVALID_SUMMON_ACTOR")
		actors[identity] = value
	var dynamic: Dictionary = {}
	var generations: Dictionary = {}
	var bindings: Array[Dictionary] = []
	var highest: int = 0
	for value: Variant in summon_state["bindings"]:
		if (
			not value is Dictionary
			or value.size() != 5
			or not _integer_in(value.get("unitId"), 20, 79)
			or not _integer_in(value.get("generation"), 1, 2147483646)
			or not _integer_in(value.get("afterCloneGeneration"), 0, 2147483646)
			or not _integer_in(value.get("classId"), 0, 40)
			or not _integer_in(value.get("faction"), 1, 2)
		):
			return _failure("INVALID_SUMMON_BINDING")
		var identity: int = int(value["unitId"])
		var generation: int = int(value["generation"])
		var job: int = int(value["classId"])
		var faction: int = int(value["faction"])
		var first: int = 70 if faction == 2 else 20
		if identity < first or identity > first + 9:
			return _failure("INVALID_SUMMON_BINDING")
		var key: String = _profile_key(registry, faction, job, identity)
		if key.is_empty():
			return _failure("MISSING_SUMMON_PROFILE")
		if dynamic.has(identity) or generations.has(generation) or not actors.has(identity):
			return _failure("INVALID_SUMMON_BINDING")
		var actor: Dictionary = actors[identity]
		if (
			actor.get("sourceId") != identity
			or actor.get("classId") != job
			or actor.get("faction") != faction
			or actor.get("formal") != false
			or actor.get("dropTemplateId") != 0
			or actor.get("policy") != 0
			or actor.has("deploymentIndex")
			or actor.has("deploymentSlot")
			or actor.has("temporary")
		):
			return _failure("INVALID_SUMMON_ACTOR")
		dynamic[identity] = true
		generations[generation] = true
		highest = maxi(highest, generation)
		bindings.append(
			{
				"unitId": identity,
				"generation": generation,
				"classId": job,
				"faction": faction,
				"afterCloneGeneration": int(value["afterCloneGeneration"])
			}
		)
	if int(summon_state["nextGeneration"]) != highest + 1:
		return _failure("INVALID_SUMMON_GENERATION")
	bindings.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["generation"] < b["generation"]
	)
	var previous_anchor: int = 0
	for binding: Dictionary in bindings:
		if binding["afterCloneGeneration"] < previous_anchor:
			return _failure("INVALID_SUMMON_ANCHOR")
		previous_anchor = binding["afterCloneGeneration"]
	var static_units: Array[Dictionary] = []
	for actor: Dictionary in units:
		if not dynamic.has(int(actor["id"])):
			if actor.get("summoned", false) == true:
				return _failure("UNDECLARED_SUMMON_ACTOR")
			static_units.append(actor.duplicate(true))
	var replaced: Array[int] = []
	for index: int in range(records.size()):
		var record: Dictionary = records[index]
		if (
			not record.has("deploymentSlot")
			and dynamic.has(int(record.get("id", record["sourceId"])))
		):
			replaced.append(index)
	return {
		"ok": true,
		"staticUnits": static_units,
		"bindings": bindings,
		"nextGeneration": highest + 1,
		"replacedIndices": replaced
	}


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)


static func _profile_key(registry: Dictionary, faction: int, job: int, identity: int) -> String:
	var side: Variant = registry.get(str(faction))
	if not side is Dictionary:
		return ""
	var family: Variant = side.get(str(job))
	if not family is Dictionary:
		return ""
	var key: Variant = family.get(str(identity))
	return key if key is String else ""


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
