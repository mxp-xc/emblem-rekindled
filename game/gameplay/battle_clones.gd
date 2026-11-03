extends RefCounted

const Inventory = preload("res://gameplay/unit_inventory.gd")
const MAX_ID: int = 2147483647
var _definition: Dictionary
var _records: Array
var _combat: RefCounted
var _inventory: RefCounted
var _item_prefix: String
var _random_source: Callable


func _init(
	content: Dictionary,
	combat: RefCounted,
	inventory: RefCounted,
	random_source: Callable = Callable()
) -> void:
	_records = content.get("_deployments", [])
	_definition = definition(content.get("story", {}).get("periodicClones"), _records)
	_combat = combat
	_inventory = inventory
	_random_source = random_source
	_item_prefix = "%s:%s:clone_" % [content["entry"]["id"], content["entry"]["battleId"]]


# The declaration is the sole authority for pool identities and presentation families.
static func definition(policy: Variant, records: Array) -> Dictionary:
	if policy == null:
		return {"ok": true, "enabled": false, "policy": {}, "templateIndices": {}}
	if (
		not policy is Dictionary
		or not policy.get("id") is String
		or policy["id"].is_empty()
		or not policy.get("pool") is Array
		or policy["pool"].size() != 2
		or not _integer_in(policy["pool"][0], 0, MAX_ID)
		or not _integer_in(policy["pool"][1], int(policy["pool"][0]), MAX_ID)
	):
		return _failure("INVALID_CLONE_DEFINITION")
	var normalized: Dictionary = {
		"id": policy["id"], "pool": [int(policy["pool"][0]), int(policy["pool"][1])]
	}
	var templates: Dictionary = {}
	var groups: Array = []
	if policy.has("randomEachRound"):
		var schedule: Variant = policy["randomEachRound"]
		if (
			policy.size() != 3
			or not schedule is Dictionary
			or schedule.size() != (4 if schedule.has("whenUnitHidden") else 3)
			or not _integer_in(schedule.get("fromRound"), 1, MAX_ID)
			or not _integer_in(schedule.get("count"), 1, 127)
			or (
				schedule.has("whenUnitHidden")
				and not _integer_in(schedule["whenUnitHidden"], 0, MAX_ID)
			)
		):
			return _failure("INVALID_CLONE_DEFINITION")
		normalized["randomEachRound"] = {
			"fromRound": int(schedule["fromRound"]),
			"count": int(schedule["count"]),
			"templateUnitIds": schedule.get("templateUnitIds")
		}
		if schedule.has("whenUnitHidden"):
			normalized["randomEachRound"]["whenUnitHidden"] = int(schedule["whenUnitHidden"])
		groups.append(normalized["randomEachRound"])
	elif policy.has("conditionalEvery"):
		var schedule: Variant = policy["conditionalEvery"]
		if (
			policy.size() != 3
			or not schedule is Dictionary
			or schedule.size() != 3
			or not _integer_in(schedule.get("period"), 1, 32767)
			or not schedule.get("groups") is Array
			or schedule["groups"].is_empty()
			or not schedule.get("reservedUnitIds") is Array
		):
			return _failure("INVALID_CLONE_DEFINITION")
		normalized["conditionalEvery"] = {"period": int(schedule["period"]), "groups": []}
		var gates: Array[int] = []
		for branch: Variant in schedule["groups"]:
			if (
				not branch is Dictionary
				or branch.size() != 2
				or not _integer_in(branch.get("whenUnitVisible"), 0, MAX_ID)
				or int(branch["whenUnitVisible"]) in gates
			):
				return _failure("INVALID_CLONE_DEFINITION")
			gates.append(int(branch["whenUnitVisible"]))
			var group: Dictionary = {
				"whenUnitVisible": int(branch["whenUnitVisible"]),
				"templateUnitIds": branch.get("templateUnitIds")
			}
			normalized["conditionalEvery"]["groups"].append(group)
			groups.append(group)
		if not schedule["reservedUnitIds"].is_empty():
			var reserved: Dictionary = {"templateUnitIds": schedule["reservedUnitIds"]}
			groups.append(reserved)
			normalized["conditionalEvery"]["reservedUnitIds"] = reserved["templateUnitIds"]
	else:
		if (
			policy.size() != 4
			or not _integer_in(policy.get("throughRound"), 1, 32767)
			or not policy.get("branches") is Array
			or policy["branches"].is_empty()
		):
			return _failure("INVALID_CLONE_DEFINITION")
		normalized["throughRound"] = int(policy["throughRound"])
		normalized["branches"] = []
		for branch: Variant in policy["branches"]:
			if (
				not branch is Dictionary
				or branch.size() != 2
				or not _integer_in(branch.get("period"), 1, 32767)
			):
				return _failure("INVALID_CLONE_DEFINITION")
			var group: Dictionary = {
				"period": int(branch["period"]), "templateUnitIds": branch.get("templateUnitIds")
			}
			normalized["branches"].append(group)
			groups.append(group)
	for group: Dictionary in groups:
		if not group.get("templateUnitIds") is Array or group["templateUnitIds"].is_empty():
			return _failure("INVALID_CLONE_DEFINITION")
		var identities: Array[int] = []
		for identity: Variant in group["templateUnitIds"]:
			if (
				not _integer_in(identity, 0, MAX_ID)
				or int(identity) in identities
				or normalized.has("conditionalEvery") and templates.has(int(identity))
			):
				return _failure("INVALID_CLONE_DEFINITION")
			identities.append(int(identity))
			templates[int(identity)] = -1
		group["templateUnitIds"] = identities
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
	if normalized.has("randomEachRound") and normalized["randomEachRound"].has("whenUnitHidden"):
		var gate: int = normalized["randomEachRound"]["whenUnitHidden"]
		if not seen.has(gate) or (gate >= normalized["pool"][0] and gate <= normalized["pool"][1]):
			return _failure("INVALID_CLONE_GATE")
	if normalized.has("conditionalEvery"):
		for group: Dictionary in normalized["conditionalEvery"]["groups"]:
			var gate: int = group["whenUnitVisible"]
			if (
				not seen.has(gate)
				or (gate >= normalized["pool"][0] and gate <= normalized["pool"][1])
			):
				return _failure("INVALID_CLONE_GATE")
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
	var normalized: Dictionary = declared["policy"]
	var random_mode: bool = normalized.has("randomEachRound")
	var conditional_mode: bool = normalized.has("conditionalEvery")
	var gated: bool = random_mode and normalized["randomEachRound"].has("whenUnitHidden")
	if (
		not _integer_in(state.get("round"), 1, MAX_ID if random_mode or conditional_mode else 32767)
		or not _integer_in(state.get("phase"), 0, 0)
		or not state.get("events") is Dictionary
	):
		return _failure("INVALID_CLONE_SAVE")
	if gated:
		var gate_id: int = int(normalized["randomEachRound"]["whenUnitHidden"])
		var gate_found: bool = false
		for actor: Variant in state["units"]:
			if actor is Dictionary and actor.get("id") == gate_id and actor.get("visible") is bool:
				gate_found = true
				break
		if not gate_found:
			return _failure("INVALID_CLONE_GATE")
	if conditional_mode:
		for group: Dictionary in normalized["conditionalEvery"]["groups"]:
			var gate_found: bool = false
			for actor: Variant in state["units"]:
				if (
					actor is Dictionary
					and actor.get("id") == group["whenUnitVisible"]
					and actor.get("visible") is bool
				):
					gate_found = true
					break
			if not gate_found:
				return _failure("INVALID_CLONE_GATE")
	var expected: Dictionary = {}
	var attempts: int = 0
	if conditional_mode:
		attempts = _attempts_through(normalized, int(state["round"]) - 1)
	elif not random_mode:
		for round_number: int in range(1, normalized["throughRound"] + 1):
			var branch: Array = _templates_due(normalized, round_number)
			if branch.is_empty():
				continue
			var event_id: String = _event_id(normalized, round_number)
			var completed: bool = round_number < int(state["round"])
			expected[event_id] = completed
			if completed:
				attempts += branch.size()
	var marked_rounds: Dictionary = {}
	var active_rounds: int = 0
	for event_id: Variant in state["events"]:
		if not event_id is String or not state["events"][event_id] is bool:
			return _failure("INVALID_CLONE_EVENTS")
		var prefix: String = normalized["id"] + ":round_"
		var skipped_prefix: String = normalized["id"] + ":skip_round_"
		var skipped: bool = event_id.begins_with(skipped_prefix)
		if not event_id.begins_with(prefix) and not skipped:
			continue
		if conditional_mode:
			if skipped:
				return _failure("INVALID_CLONE_EVENTS")
			var suffix: String = event_id.trim_prefix(prefix)
			if not suffix.is_valid_int() or suffix != str(int(suffix)):
				return _failure("INVALID_CLONE_EVENTS")
			var event_round: int = int(suffix)
			if (
				event_round < 1
				or event_round >= int(state["round"])
				or event_round % int(normalized["conditionalEvery"]["period"]) != 0
				or not state["events"][event_id]
			):
				return _failure("INVALID_CLONE_EVENTS")
			marked_rounds[event_round] = true
			continue
		if not random_mode:
			if not expected.has(event_id):
				return _failure("INVALID_CLONE_EVENTS")
			continue
		if skipped and not gated:
			return _failure("INVALID_CLONE_EVENTS")
		var suffix: String = event_id.trim_prefix(skipped_prefix if skipped else prefix)
		if not suffix.is_valid_int() or suffix != str(int(suffix)):
			return _failure("INVALID_CLONE_EVENTS")
		var event_round: int = int(suffix)
		if (
			event_round < normalized["randomEachRound"]["fromRound"]
			or event_round >= int(state["round"])
			or not state["events"][event_id]
			or marked_rounds.has(event_round)
		):
			return _failure("INVALID_CLONE_EVENTS")
		marked_rounds[event_round] = true
		if not skipped:
			active_rounds += 1
	if conditional_mode:
		var completed: int = int(
			(int(state["round"]) - 1) / int(normalized["conditionalEvery"]["period"])
		)
		if marked_rounds.size() != completed:
			return _failure("INVALID_CLONE_EVENTS")
	elif random_mode:
		var completed_rounds: int = maxi(
			0, int(state["round"]) - normalized["randomEachRound"]["fromRound"]
		)
		# Canonical distinct keys, all within this interval, must cover every completed round.
		if marked_rounds.size() != completed_rounds:
			return _failure("INVALID_CLONE_EVENTS")
		attempts = mini(MAX_ID - 1, active_rounds * normalized["randomEachRound"]["count"])
	else:
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
	var normalized: Dictionary = declared["policy"]
	var attempts: int = (
		MAX_ID - 1
		if normalized.has("randomEachRound") or normalized.has("conditionalEvery")
		else _attempts_through(normalized, normalized["throughRound"])
	)
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
			or not _allowed_family_class(records[family], actor.get("classId"))
			or actor.get("faction") != 2
			or actor.get("formal") != false
			or actor.has("deploymentIndex")
			or actor.has("deploymentSlot")
			or actor.has("temporary")
		):
			return _failure("INVALID_CLONE_ACTOR")
		var root_id: int = int(records[family].get("id", records[family]["sourceId"]))
		if actors.has(root_id):
			var root: Dictionary = actors[root_id]
			if (
				root.get("deploymentIndex", -1) == family
				and root.get("classId") != actor["classId"]
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
					or not _allowed_family_class(original, actor.get("classId"))
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
		"eventId": "",
		"skipped": false
	}
	if not _definition["enabled"]:
		return result
	var policy: Dictionary = _definition["policy"]
	var templates: Array = _templates_due(policy, round_number)
	var random_mode: bool = policy.has("randomEachRound")
	var conditional_mode: bool = policy.has("conditionalEvery")
	var count: int = templates.size()
	if random_mode and round_number >= policy["randomEachRound"]["fromRound"]:
		count = int(policy["randomEachRound"]["count"])
	var event_id: String = _event_id(policy, round_number)
	var skipped_id: String = _skipped_event_id(policy, round_number)
	var due_conditional: bool = (
		conditional_mode
		and round_number > 0
		and round_number % int(policy["conditionalEvery"]["period"]) == 0
	)
	if (
		(count == 0 and not due_conditional)
		or completed_events.get(event_id, false)
		or completed_events.get(skipped_id, false)
	):
		return result
	var attempts: int = _attempts_through(
		policy, round_number - 1 if random_mode or conditional_mode else policy["throughRound"]
	)
	var valid: Dictionary = _saved_actors(
		_definition, _records, units.values(), next_state, attempts
	)
	if not valid["ok"]:
		return valid
	if due_conditional:
		for group: Dictionary in policy["conditionalEvery"]["groups"]:
			var gate: int = group["whenUnitVisible"]
			if not units.has(gate) or not units[gate].get("visible") is bool:
				return _failure("INVALID_CLONE_GATE")
			if units[gate]["visible"]:
				templates.append_array(group["templateUnitIds"])
		count = templates.size()
	if random_mode and policy["randomEachRound"].has("whenUnitHidden"):
		var gate: int = int(policy["randomEachRound"]["whenUnitHidden"])
		if not units.has(gate) or not units[gate].get("visible") is bool:
			return _failure("INVALID_CLONE_GATE")
		if units[gate]["visible"]:
			result["eventId"] = skipped_id
			result["skipped"] = true
			return result
	if random_mode and not _random_source.is_valid():
		return _failure("MISSING_CLONE_RANDOM_SOURCE")
	next_state["bindings"] = valid["bindings"]
	next_state["nextGeneration"] = valid["nextGeneration"]
	var held_ids: Dictionary = {}
	for actor: Dictionary in units.values():
		for held: Dictionary in actor["inventory"]:
			held_ids[held["id"]] = true
	for held: Dictionary in warehouse:
		held_ids[held["id"]] = true
	for index: int in range(count):
		var template_id: int
		if random_mode:
			var choices: Array = policy["randomEachRound"]["templateUnitIds"]
			template_id = int(choices[int(_random_source.call(choices.size()))])
		else:
			template_id = int(templates[index])
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
		if generation >= MAX_ID:
			return _failure("CLONE_GENERATION_EXHAUSTED")
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


static func _allowed_family_class(record: Dictionary, value: Variant) -> bool:
	if not _integer_in(value, 0, 40):
		return false
	var base: int = int(record["classId"])
	return (
		int(value) == base
		or (
			int(record.get("kind", -1)) == 1
			and int(record["faction"]) != 0
			and base % 4 == 0
			and int(value) == base + 1
		)
	)


static func _free_identity(policy: Dictionary, units: Dictionary) -> int:
	for identity: int in range(policy["pool"][0], policy["pool"][1] + 1):
		if not units.has(identity) or not units[identity]["visible"] and units[identity]["hp"] <= 0:
			return identity
	return -1


static func _templates_due(policy: Dictionary, round_number: int) -> Array:
	if policy.has("randomEachRound") or policy.has("conditionalEvery"):
		return []
	if round_number < 1 or round_number > policy["throughRound"]:
		return []
	for branch: Dictionary in policy["branches"]:
		if round_number % int(branch["period"]) == 0:
			return branch["templateUnitIds"]
	return []


static func _attempts_through(policy: Dictionary, last_round: int) -> int:
	if policy.has("conditionalEvery"):
		var schedule: Dictionary = policy["conditionalEvery"]
		var per_round: int = 0
		for group: Dictionary in schedule["groups"]:
			per_round += group["templateUnitIds"].size()
		return mini(MAX_ID - 1, int(maxi(0, last_round) / int(schedule["period"])) * per_round)
	if policy.has("randomEachRound"):
		var schedule: Dictionary = policy["randomEachRound"]
		return mini(MAX_ID - 1, maxi(0, last_round - schedule["fromRound"] + 1) * schedule["count"])
	var attempts: int = 0
	for round_number: int in range(1, mini(last_round, policy["throughRound"]) + 1):
		attempts += _templates_due(policy, round_number).size()
	return attempts


static func _event_id(policy: Dictionary, round_number: int) -> String:
	return "%s:round_%d" % [policy["id"], round_number]


static func _skipped_event_id(policy: Dictionary, round_number: int) -> String:
	return "%s:skip_round_%d" % [policy["id"], round_number]


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
