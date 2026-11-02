extends RefCounted

const Inventory = preload("res://gameplay/unit_inventory.gd")
const MAX_ID: int = 2147483647
var _definition: Dictionary
var _records: Array
var _combat: RefCounted
var _inventory: RefCounted
var _item_prefix: String


func _init(content: Dictionary, combat: RefCounted, inventory: RefCounted) -> void:
	_records = content.get("_deployments", [])
	_definition = definition(content.get("story", {}).get("periodicClones"), _records)
	_combat = combat
	_inventory = inventory
	_item_prefix = "%s:%s:clone_" % [content["entry"]["id"], content["entry"]["battleId"]]


# The declaration is the sole authority for pool identities and presentation families.
static func definition(policy: Variant, records: Array) -> Dictionary:
	if policy == null:
		return {"ok": true, "enabled": false, "policy": {}, "templateIndices": {}}
	if (
		not policy is Dictionary
		or policy.size() != 4
		or not policy.get("id") is String
		or policy["id"].is_empty()
		or not policy.get("pool") is Array
		or policy["pool"].size() != 2
		or not _integer_in(policy["pool"][0], 0, MAX_ID)
		or not _integer_in(policy["pool"][1], int(policy["pool"][0]), MAX_ID)
		or not _integer_in(policy.get("throughRound"), 1, 32767)
		or not policy.get("branches") is Array
		or policy["branches"].is_empty()
	):
		return _failure("INVALID_CLONE_DEFINITION")
	var normalized: Dictionary = {
		"id": policy["id"],
		"pool": [int(policy["pool"][0]), int(policy["pool"][1])],
		"throughRound": int(policy["throughRound"]),
		"branches": []
	}
	var templates: Dictionary = {}
	for branch: Variant in policy["branches"]:
		if (
			not branch is Dictionary
			or branch.size() != 2
			or not _integer_in(branch.get("period"), 1, 32767)
			or not branch.get("templateUnitIds") is Array
			or branch["templateUnitIds"].is_empty()
		):
			return _failure("INVALID_CLONE_DEFINITION")
		var identities: Array[int] = []
		for identity: Variant in branch["templateUnitIds"]:
			if not _integer_in(identity, 0, MAX_ID) or int(identity) in identities:
				return _failure("INVALID_CLONE_DEFINITION")
			identities.append(int(identity))
			templates[int(identity)] = -1
		normalized["branches"].append(
			{"period": int(branch["period"]), "templateUnitIds": identities}
		)
	var seen: Dictionary = {}
	for index: int in range(records.size()):
		var record: Variant = records[index]
		if not record is Dictionary or not _integer_in(record.get("sourceId"), 0, 255):
			return _failure("INVALID_CLONE_DEPLOYMENT")
		var identity: Variant = record.get("id", record["sourceId"])
		if not _integer_in(identity, 0, MAX_ID) or seen.has(int(identity)):
			return _failure("INVALID_CLONE_DEPLOYMENT")
		seen[int(identity)] = true
		var in_pool: bool = identity >= normalized["pool"][0] and identity <= normalized["pool"][1]
		if not templates.has(int(identity)):
			if in_pool or record.has("deploymentSlot") and _pool_overlaps_temporary(normalized):
				return _failure("INVALID_CLONE_POOL")
			continue
		if (
			record.get("formal", false) != false
			or record.get("faction") != 2
			or record.has("deploymentSlot")
			or record.get("temporary", false) != false
			or not _integer_in(record.get("classId"), 0, 40)
		):
			return _failure("INVALID_CLONE_TEMPLATE")
		templates[int(identity)] = index
	for index: int in templates.values():
		if index < 0:
			return _failure("MISSING_CLONE_TEMPLATE")
	return {"ok": true, "enabled": true, "policy": normalized, "templateIndices": templates}


# Split dynamic actors before ordinary deployment inference, without trusting saved blueprints.
static func saved_bindings(policy: Variant, records: Array, state: Dictionary) -> Dictionary:
	var declared: Dictionary = definition(policy, records)
	if not declared["ok"]:
		return declared
	if not state.get("units") is Array:
		return _failure("INVALID_CLONE_SAVE")
	if not declared["enabled"]:
		if state.has("cloneState") and state["cloneState"] != {}:
			return _failure("UNDECLARED_CLONE_STATE")
		return {
			"ok": true,
			"staticUnits": state["units"].duplicate(true),
			"bindings": [],
			"nextGeneration": 1,
			"replacedIndices": []
		}
	if (
		not _integer_in(state.get("round"), 1, 32767)
		or not _integer_in(state.get("phase"), 0, 0)
		or not state.get("events") is Dictionary
	):
		return _failure("INVALID_CLONE_SAVE")
	var normalized: Dictionary = declared["policy"]
	var expected: Dictionary = {}
	var attempts: int = 0
	for round_number: int in range(1, normalized["throughRound"] + 1):
		var branch: Array = _templates_due(normalized, round_number)
		if branch.is_empty():
			continue
		var event_id: String = _event_id(normalized, round_number)
		var completed: bool = round_number < int(state["round"])
		expected[event_id] = completed
		if completed:
			attempts += branch.size()
	for event_id: Variant in state["events"]:
		if not event_id is String or not state["events"][event_id] is bool:
			return _failure("INVALID_CLONE_EVENTS")
		if event_id.begins_with(normalized["id"] + ":round_") and not expected.has(event_id):
			return _failure("INVALID_CLONE_EVENTS")
	for event_id: String in expected:
		if state["events"].get(event_id, false) != expected[event_id]:
			return _failure("INVALID_CLONE_EVENTS")
	var current: Dictionary = current_bindings(
		policy, records, state["units"], state.get("cloneState")
	)
	if current["ok"] and current["nextGeneration"] > attempts + 1:
		return _failure("INVALID_CLONE_GENERATION")
	return current


# Projection also uses the same actor algebra, without fabricating a save phase or event history.
static func current_bindings(
	policy: Variant, records: Array, units: Array, clone_state: Variant
) -> Dictionary:
	var declared: Dictionary = definition(policy, records)
	if not declared["ok"]:
		return declared
	if not declared["enabled"]:
		if clone_state != null and clone_state != {}:
			return _failure("UNDECLARED_CLONE_STATE")
		return {
			"ok": true,
			"staticUnits": units.duplicate(true),
			"bindings": [],
			"nextGeneration": 1,
			"replacedIndices": []
		}
	var attempts: int = 0
	for round_number: int in range(1, declared["policy"]["throughRound"] + 1):
		attempts += _templates_due(declared["policy"], round_number).size()
	return _saved_actors(declared, records, units, clone_state, attempts)


static func _saved_actors(
	declared: Dictionary, records: Array, units: Array, clone_state: Variant, attempts: int
) -> Dictionary:
	if (
		not clone_state is Dictionary
		or clone_state.size() != 2
		or not _integer_in(clone_state.get("nextGeneration"), 1, attempts + 1)
		or not clone_state.get("bindings") is Array
	):
		return _failure("INVALID_CLONE_STATE")
	var actors: Dictionary = {}
	for actor: Variant in units:
		if (
			not actor is Dictionary
			or not _integer_in(actor.get("id"), 0, MAX_ID)
			or actors.has(int(actor["id"]))
		):
			return _failure("INVALID_CLONE_ACTOR")
		actors[int(actor["id"])] = actor
	for identity: int in declared["templateIndices"]:
		if not actors.has(identity):
			return _failure("MISSING_CLONE_TEMPLATE")
	var bindings: Array[Dictionary] = []
	var dynamic: Dictionary = {}
	var generations: Dictionary = {}
	var highest: int = 0
	var policy: Dictionary = declared["policy"]
	for value: Variant in clone_state["bindings"]:
		if (
			not value is Dictionary
			or value.size() != 3
			or not _integer_in(value.get("unitId"), policy["pool"][0], policy["pool"][1])
			or not _integer_in(value.get("generation"), 1, attempts)
			or not _integer_in(value.get("templateDeploymentIndex"), 0, records.size() - 1)
			or int(value["templateDeploymentIndex"]) not in declared["templateIndices"].values()
		):
			return _failure("INVALID_CLONE_BINDING")
		var identity: int = int(value["unitId"])
		var generation: int = int(value["generation"])
		var family: int = int(value["templateDeploymentIndex"])
		if dynamic.has(identity) or generations.has(generation) or not actors.has(identity):
			return _failure("INVALID_CLONE_BINDING")
		var actor: Dictionary = actors[identity]
		if (
			actor.get("sourceId") != records[family]["sourceId"]
			or actor.get("classId") != records[family]["classId"]
			or actor.get("faction") != 2
			or actor.get("formal") != false
			or actor.has("deploymentIndex")
			or actor.has("deploymentSlot")
			or actor.has("temporary")
		):
			return _failure("INVALID_CLONE_ACTOR")
		dynamic[identity] = true
		generations[generation] = true
		highest = maxi(highest, generation)
		bindings.append(
			{"unitId": identity, "generation": generation, "templateDeploymentIndex": family}
		)
	if int(clone_state["nextGeneration"]) != highest + 1:
		return _failure("INVALID_CLONE_GENERATION")
	bindings.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["generation"] < b["generation"]
	)
	var static_units: Array[Dictionary] = []
	for actor: Dictionary in units:
		if not dynamic.has(int(actor["id"])):
			var identity: int = int(actor["id"])
			if identity >= policy["pool"][0] and identity <= policy["pool"][1]:
				if not declared["templateIndices"].has(identity):
					return _failure("INVALID_CLONE_ACTOR")
				var original: Dictionary = records[declared["templateIndices"][identity]]
				if (
					actor.get("sourceId") != original["sourceId"]
					or actor.get("classId") != original["classId"]
					or actor.get("faction") != 2
					or actor.get("formal") != false
				):
					return _failure("INVALID_CLONE_ACTOR")
			static_units.append(actor.duplicate(true))
	var replaced: Array[int] = []
	for index: int in range(records.size()):
		if dynamic.has(int(records[index].get("id", records[index]["sourceId"]))):
			replaced.append(index)
	return {
		"ok": true,
		"staticUnits": static_units,
		"bindings": bindings,
		"nextGeneration": highest + 1,
		"replacedIndices": replaced
	}


# Construct every hidden birth before the caller reveals any of them.
func plan_wave(
	round_number: int,
	ordered_units: Dictionary,
	warehouse: Array,
	clone_state: Dictionary,
	completed_events: Dictionary
) -> Dictionary:
	if not _definition["ok"]:
		return _definition.duplicate(true)
	var units: Dictionary = ordered_units.duplicate(true)
	var next_state: Dictionary = clone_state.duplicate(true)
	var result: Dictionary = {
		"ok": true,
		"units": units,
		"cloneState": next_state,
		"birthIds": [],
		"origins": {},
		"eventId": ""
	}
	if not _definition["enabled"]:
		return result
	var policy: Dictionary = _definition["policy"]
	var templates: Array = _templates_due(policy, round_number)
	var event_id: String = _event_id(policy, round_number)
	if templates.is_empty() or completed_events.get(event_id, false):
		return result
	var attempts: int = 0
	for earlier: int in range(1, policy["throughRound"] + 1):
		attempts += _templates_due(policy, earlier).size()
	var valid: Dictionary = _saved_actors(
		_definition, _records, units.values(), next_state, attempts
	)
	if not valid["ok"]:
		return valid
	next_state["bindings"] = valid["bindings"]
	next_state["nextGeneration"] = valid["nextGeneration"]
	var held_ids: Dictionary = {}
	for actor: Dictionary in units.values():
		for held: Dictionary in actor["inventory"]:
			held_ids[held["id"]] = true
	for held: Dictionary in warehouse:
		held_ids[held["id"]] = true
	for template_id: int in templates:
		# The next allocation can remove this very template, so capture its current value first.
		var source: Dictionary = units[template_id].duplicate(true)
		var family: int = _definition["templateIndices"][template_id]
		for binding: Dictionary in next_state["bindings"]:
			if binding["unitId"] == template_id:
				family = binding["templateDeploymentIndex"]
		var identity: int = _free_identity(policy, units)
		if identity < 0:
			continue
		var generation: int = next_state["nextGeneration"]
		var born: Dictionary = _birth(source, identity, generation, held_ids)
		if not born["ok"]:
			return born
		units.erase(identity)
		units[identity] = born["unit"]
		next_state["bindings"] = next_state["bindings"].filter(
			func(binding: Dictionary) -> bool: return binding["unitId"] != identity
		)
		next_state["bindings"].append(
			{"unitId": identity, "generation": generation, "templateDeploymentIndex": family}
		)
		next_state["nextGeneration"] = generation + 1
		result["birthIds"].append(identity)
		result["origins"][identity] = Vector2i(source["x"], source["y"])
	result["eventId"] = event_id
	return result


func _birth(source: Dictionary, identity: int, generation: int, held_ids: Dictionary) -> Dictionary:
	var actor: Dictionary = source.duplicate(true)
	for key: String in ["deploymentIndex", "deploymentSlot", "temporary"]:
		actor.erase(key)
	actor.merge(
		{
			"id": identity,
			"faction": 2,
			"formal": false,
			"visible": false,
			"flags": 1,
			"hp": int(source["maxHp"]),
			"policy": 0,
			"action": 0,
			"experience": 0,
			"proficiency": 0,
			"inventory": [],
			"equippedInstanceId": ""
		},
		true
	)
	var item_templates: Array[int] = []
	var drop: int = int(source["dropTemplateId"])
	for held: Dictionary in source["inventory"]:
		if int(held["templateId"]) != drop:
			item_templates.append(int(held["templateId"]))
	if drop > 0:
		item_templates.append(drop)
	for template_id: int in item_templates:
		if actor["inventory"].size() >= Inventory.BAG_CAPACITY:
			break
		var item: Dictionary = _combat.item_definition(template_id)
		if item.is_empty():
			return _failure("INVALID_CLONE_ITEM")
		var candidate: String = (
			"%s%d:item_%d" % [_item_prefix, generation, actor["inventory"].size()]
		)
		var item_id: String = candidate
		var suffix: int = 1
		while held_ids.has(item_id):
			item_id = "%s:%d" % [candidate, suffix]
			suffix += 1
		held_ids[item_id] = true
		actor["inventory"].append(
			{"id": item_id, "templateId": template_id, "durability": int(item["defaultDurability"])}
		)
	_inventory.auto_equip(actor)
	return {"ok": true, "unit": actor}


static func _free_identity(policy: Dictionary, units: Dictionary) -> int:
	for identity: int in range(policy["pool"][0], policy["pool"][1] + 1):
		if not units.has(identity) or not units[identity]["visible"] and units[identity]["hp"] <= 0:
			return identity
	return -1


static func _templates_due(policy: Dictionary, round_number: int) -> Array:
	if round_number < 1 or round_number > policy["throughRound"]:
		return []
	for branch: Dictionary in policy["branches"]:
		if round_number % int(branch["period"]) == 0:
			return branch["templateUnitIds"]
	return []


static func _event_id(policy: Dictionary, round_number: int) -> String:
	return "%s:round_%d" % [policy["id"], round_number]


static func _pool_overlaps_temporary(policy: Dictionary) -> bool:
	return policy["pool"][0] <= 104 and policy["pool"][1] >= 95


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
