extends RefCounted

const MAX_ID: int = 2147483647

const STAT_FIELDS: Array[String] = [
	"strength", "skill", "speed", "defense", "magic", "luck", "maxHp", "move"
]


static func recruit_order(
	route: Array, recruits: Dictionary, world_step: int, initial_party: Array = [0]
) -> Array[int]:
	if world_step < 0 or world_step > route.size():
		return []
	var result: Array[int] = []
	for identity: Variant in initial_party:
		if not _integer_in(identity, 0, MAX_ID) or int(identity) in result:
			return []
		result.append(int(identity))
	for index: int in range(world_step):
		if not _integer_in(route[index], 0, 127):
			return []
		var member: Variant = recruits.get(str(int(route[index])), -1)
		if not _integer_in(member, -1, MAX_ID):
			return []
		if member >= 0 and int(member) not in result:
			result.append(int(member))
	return result


# Resolve identities and static blueprints without drawing randomness.
static func bind(
	records: Array,
	profiles: Dictionary,
	recipes: Dictionary,
	party: Array,
	identity_bindings: Dictionary = {},
	class_bindings: Dictionary = {},
	replaced_indices: Array = []
) -> Dictionary:
	var resolved: Dictionary = _resolve(
		records, party, identity_bindings, class_bindings, replaced_indices
	)
	if not resolved["ok"]:
		return resolved
	var units: Array[Dictionary] = []
	var spawns: Array[Dictionary] = []
	var bindings: Dictionary = {}
	var optional: Array[int] = []
	for descriptor: Dictionary in resolved["records"]:
		var index: int = descriptor["deploymentIndex"]
		var record: Dictionary = records[index]
		var identity: int = descriptor["id"]
		if identity < 0:
			continue
		var request: String = descriptor["recipe"]
		var profile_id: Variant = recipes.get(request)
		if not profile_id is String or not profiles.get(profile_id) is Dictionary:
			return {
				"ok": false,
				"error": "MISSING_PRESENTATION_PROFILE",
				"record": index,
				"profile": request
			}
		var profile: Dictionary = profiles[profile_id]
		if (
			not profile.get("unit") is Dictionary
			or profile["unit"].get("classId") != descriptor["classId"]
		):
			return _failure("INVALID_PRESENTATION_PROFILE", index)
		var spawn: Dictionary = _spawn(record, descriptor)
		if record.has("deploymentRegions"):
			optional.append(identity)
		bindings[identity] = profile_id
		units.append(_prototype(profile["unit"], spawn))
		spawns.append(spawn)
	return {
		"ok": true,
		"units": units,
		"spawns": spawns,
		"slots": resolved["slots"],
		"profiles": bindings,
		"optionalIds": optional,
		"referenceIds": resolved["referenceIds"]
	}


# Saved coordinates can be anywhere inside the map, not only the initial region.
static func infer_bindings(
	records: Array, party: Array, saved_units: Array, replaced_indices: Array = []
) -> Dictionary:
	var resolved: Dictionary = _resolve(records, party)
	if not resolved["ok"]:
		return resolved
	var bindings: Dictionary = {}
	var classes: Dictionary = {}
	var identities: Dictionary = {}
	for index: int in range(records.size()):
		bindings[index] = -1
	for value: Variant in saved_units:
		if not value is Dictionary or not _saved_identity_valid(value):
			return _failure("INVALID_SAVED_DEPLOYMENT", -1)
		var saved: Dictionary = value
		var identity: int = int(saved["id"])
		if identities.has(identity):
			return _failure("DUPLICATE_DEPLOYMENT_IDENTITY", -1)
		var candidates: Array[int] = []
		for descriptor: Dictionary in resolved["records"]:
			if (
				descriptor["deploymentIndex"] not in replaced_indices
				and _matches_saved(descriptor, saved)
			):
				candidates.append(int(descriptor["deploymentIndex"]))
		if candidates.size() != 1:
			return _failure("INVALID_SAVED_DEPLOYMENT", -1)
		var index: int = candidates[0]
		if bindings[index] >= 0:
			return _failure("DUPLICATE_SAVED_DEPLOYMENT", index)
		if saved.has("deploymentIndex") and saved["deploymentIndex"] != index:
			return _failure("INVALID_SAVED_DEPLOYMENT_INDEX", index)
		bindings[index] = identity
		identities[identity] = true
		if saved["formal"]:
			classes[index] = int(saved["classId"])
	var verified: Dictionary = _resolve(records, party, bindings, classes, replaced_indices)
	if not verified["ok"]:
		return verified
	return {"ok": true, "bindings": bindings, "classes": classes}


static func _resolve(
	records: Array,
	party: Array,
	identity_bindings: Dictionary = {},
	class_bindings: Dictionary = {},
	replaced_indices: Array = []
) -> Dictionary:
	if records.is_empty() or not _party_valid(party):
		return _failure("INVALID_DEPLOYMENT_PARTY", -1)
	if not identity_bindings.is_empty() and not _index_map_valid(identity_bindings, records.size()):
		return _failure("INVALID_DEPLOYMENT_BINDINGS", -1)
	if not _index_map_valid(class_bindings, records.size(), false):
		return _failure("INVALID_DEPLOYMENT_CLASSES", -1)
	var result: Array[Dictionary] = []
	var identities: Dictionary = {}
	var slots: Dictionary = {}
	var references: Array[int] = []
	var next_temporary: int = 95
	for index: int in range(records.size()):
		if not _record_valid(records[index]):
			return _failure("INVALID_DEPLOYMENT_RECORD", index)
		var record: Dictionary = records[index]
		var descriptor: Dictionary = _identity(record, party)
		var slot: int = descriptor["slot"]
		if slot >= 0 and slots.has(slot):
			return _failure("INVALID_DEPLOYMENT_SLOT", index)
		if slot < 0:
			references.append(int(descriptor["id"]))
		var identity: int = next_temporary if descriptor["temporary"] else descriptor["id"]
		if not identity_bindings.is_empty():
			var supplied: Variant = _index_value(identity_bindings, index)
			if not _integer_in(supplied, -1, MAX_ID):
				return _failure("INVALID_DEPLOYMENT_BINDINGS", index)
			if int(supplied) == -1:
				if not record.has("deploymentRegions") and index not in replaced_indices:
					return _failure("MISSING_FIXED_DEPLOYMENT", index)
				identity = -1
			elif int(supplied) != identity:
				return _failure("INVALID_DEPLOYMENT_BINDINGS", index)
		if identity >= 0:
			if identities.has(identity):
				return _failure("DUPLICATE_DEPLOYMENT_IDENTITY", index)
			identities[identity] = true
			if descriptor["temporary"]:
				if identity > 104:
					return _failure("TEMPORARY_DEPLOYMENT_EXHAUSTED", index)
				next_temporary += 1
		if slot >= 0:
			# Omitted slots still count as declared slots during validation.
			slots[slot] = identity
		if class_bindings.has(index) or class_bindings.has(str(index)):
			var current_class: Variant = _index_value(class_bindings, index)
			if (
				not _integer_in(current_class, 0, 40)
				or not descriptor["formal"]
				or (slot >= 0 and current_class != descriptor["classId"])
			):
				return _failure("INVALID_DEPLOYMENT_CLASSES", index)
			descriptor["classId"] = int(current_class)
		descriptor["id"] = identity
		descriptor["deploymentIndex"] = index
		descriptor["recipe"] = (
			"%s_%d_job_%d_faction_%d"
			% [
				"slot" if descriptor["temporary"] else "source",
				descriptor["sourceId"],
				descriptor["classId"],
				record["faction"]
			]
		)
		result.append(descriptor)
	if party.size() > slots.size():
		return _failure("DEPLOYMENT_PARTY_EXCEEDS_SLOTS", -1)
	for slot: int in range(party.size()):
		if not slots.has(slot):
			return _failure("INVALID_DEPLOYMENT_SLOT", -1)
	for slot: int in slots.keys():
		if slots[slot] < 0:
			slots.erase(slot)
	return {"ok": true, "records": result, "slots": slots, "referenceIds": references}


static func _identity(record: Dictionary, party: Array) -> Dictionary:
	var source: int = int(record["sourceId"])
	var identity: int = int(record.get("id", source))
	var class_id: int = int(record["classId"])
	var slot: int = int(record.get("deploymentSlot", -1))
	var temporary: bool = slot >= party.size() and slot >= 0
	if slot >= 0 and not temporary:
		identity = int(party[slot]["id"])
		source = int(party[slot].get("sourceId", identity))
		class_id = int(party[slot]["classId"])
	return {
		"id": identity,
		"sourceId": source,
		"classId": class_id,
		"faction": int(record["faction"]),
		"slot": slot,
		"temporary": temporary,
		"formal":
		(
			true
			if slot >= 0 and not temporary
			else record.get("formal", record["faction"] == 0 and not temporary and source < 10)
		)
	}


static func _spawn(record: Dictionary, descriptor: Dictionary) -> Dictionary:
	var spawn: Dictionary = record.duplicate(true)
	spawn.erase("kind")
	for key: String in ["id", "sourceId", "classId", "formal", "temporary", "deploymentIndex"]:
		spawn[key] = descriptor[key]
	spawn["visible"] = (int(record["flags"]) & 1) == 0
	spawn["policy"] = 0 if record["faction"] == 0 else int(record["policy"])
	var class_id: int = descriptor["classId"]
	var source_id: int = descriptor["sourceId"]
	spawn["growthTemplateId"] = int(
		record.get(
			"growthTemplateId", source_id if descriptor["formal"] else 10 + int(class_id / 4)
		)
	)
	if int(record["kind"]) == 1 or (descriptor["slot"] >= 0 and not descriptor["temporary"]):
		spawn.erase("explicitStats")
		# Native growth uses the source template before assigning a temporary ID.
		spawn["baseTemplateId"] = int(
			record.get("baseTemplateId", source_id if source_id < 10 else 10 + class_id)
		)
		spawn["initialGrowthTemplateId"] = int(
			record.get(
				"initialGrowthTemplateId", source_id if source_id < 10 else 10 + int(class_id / 4)
			)
		)
	if record.has("deploymentRegions"):
		spawn["position"] = [record["deploymentRegions"][0][0], record["deploymentRegions"][0][1]]
	return spawn


static func _prototype(profile: Dictionary, spawn: Dictionary) -> Dictionary:
	var unit: Dictionary = profile.duplicate(true)
	unit.merge(spawn, true)
	for key: String in [
		"itemChoices", "randomEquipment", "position", "deploymentRegions", "explicitStats"
	]:
		unit.erase(key)
	unit.merge(
		{
			"visible": spawn["visible"] and not spawn.has("deploymentRegions"),
			"x": int(spawn["position"][0]),
			"y": int(spawn["position"][1]),
			"hp": 1,
			"maxHp": 1,
			"move": 0,
			"experience": 0,
			"proficiency": 0,
			"action": 0,
			"attributes":
			{"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
			"inventory": [],
			"equippedInstanceId": ""
		},
		true
	)
	if spawn.has("explicitStats"):
		unit["attributes"] = spawn["explicitStats"].duplicate(true)
		for field: String in ["maxHp", "move"]:
			unit[field] = int(unit["attributes"][field])
			unit["attributes"].erase(field)
		unit["hp"] = unit["maxHp"]
	return unit


static func _record_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var record: Dictionary = value
	if (
		not _integer_in(record.get("kind"), 0, 1)
		or not _integer_in(record.get("sourceId"), 0, 255)
		or not _integer_in(record.get("classId"), 0, 40)
		or not _integer_in(record.get("faction"), 0, 2)
		or not _integer_in(record.get("level"), 1, 20)
		or not _integer_in(record.get("flags"), 0, 255)
		or not _integer_in(record.get("policy"), 0, 255)
		or not record.get("randomEquipment") is bool
		or not _integer_in(record.get("dropTemplateId"), 0, MAX_ID)
		or not record.get("itemChoices") is Array
		or record["itemChoices"].size() != 3
	):
		return false
	for field: String in ["id", "growthTemplateId", "baseTemplateId", "initialGrowthTemplateId"]:
		if record.has(field) and not _integer_in(record[field], 0, MAX_ID):
			return false
	if (
		record.has("formal")
		and (not record["formal"] is bool or (record["formal"] and record["faction"] != 0))
	):
		return false
	for item: Variant in record["itemChoices"]:
		if not _integer_in(item, 0, MAX_ID):
			return false
	if record.has("deploymentSlot"):
		if (
			not _integer_in(record["deploymentSlot"], 0, 9)
			or record["faction"] != 0
			or record["deploymentSlot"] != record["sourceId"]
			or (int(record["policy"]) & 32) == 0
			or record.get("formal", false)
		):
			return false
	elif record["faction"] == 0 and (int(record["policy"]) & 32) != 0:
		return false
	if record["kind"] == 0:
		if not record.get("explicitStats") is Dictionary:
			return false
		for field: String in STAT_FIELDS:
			if not _integer_in(record["explicitStats"].get(field), 0, 32767):
				return false
		if record["explicitStats"]["maxHp"] < 1:
			return false
	if record.has("deploymentRegions"):
		if record.has("position") or not record["deploymentRegions"] is Array:
			return false
		if record["deploymentRegions"].is_empty():
			return false
		for region: Variant in record["deploymentRegions"]:
			if not region is Array or region.size() != 4:
				return false
			for coordinate: Variant in region:
				if not _integer_in(coordinate, 0, 32767):
					return false
			if region[0] > region[2] or region[1] > region[3]:
				return false
		return true
	var point: Variant = record.get("position")
	return (
		point is Array
		and point.size() == 2
		and _integer_in(point[0], 0, 32767)
		and _integer_in(point[1], 0, 32767)
	)


static func _party_valid(party: Array) -> bool:
	var identities: Dictionary = {}
	for member: Variant in party:
		if (
			not member is Dictionary
			or not _integer_in(member.get("id"), 0, MAX_ID)
			or not _integer_in(member.get("classId"), 0, 40)
			or not _integer_in(member.get("sourceId", member.get("id")), 0, 255)
			or (member.has("formal") and member["formal"] != true)
			or (member.has("faction") and member["faction"] != 0)
			or identities.has(int(member["id"]))
		):
			return false
		identities[int(member["id"])] = true
	return true


static func _saved_identity_valid(saved: Dictionary) -> bool:
	return (
		_integer_in(saved.get("id"), 0, MAX_ID)
		and _integer_in(saved.get("sourceId"), 0, 255)
		and _integer_in(saved.get("classId"), 0, 40)
		and _integer_in(saved.get("faction"), 0, 2)
		and saved.get("formal") is bool
		and (not saved.has("temporary") or saved["temporary"] is bool)
		and (not saved.has("deploymentSlot") or _integer_in(saved["deploymentSlot"], 0, 9))
		and (not saved.has("deploymentIndex") or _integer_in(saved["deploymentIndex"], 0, 32767))
	)


static func _matches_saved(descriptor: Dictionary, saved: Dictionary) -> bool:
	var identity_matches: bool = (
		_integer_in(saved["id"], 95, 104)
		if descriptor["temporary"]
		else descriptor["id"] == saved["id"]
	)
	return (
		identity_matches
		and descriptor["sourceId"] == saved["sourceId"]
		and descriptor["faction"] == saved["faction"]
		and descriptor["formal"] == saved["formal"]
		and (descriptor["formal"] or descriptor["classId"] == saved["classId"])
		and (not saved.has("temporary") or saved["temporary"] == descriptor["temporary"])
		and (not saved.has("deploymentSlot") or saved["deploymentSlot"] == descriptor["slot"])
	)


static func _index_map_valid(values: Dictionary, size: int, complete: bool = true) -> bool:
	var indices: Dictionary = {}
	for key: Variant in values:
		var index: int = -1
		if key is String and key.is_valid_int():
			index = key.to_int()
		elif _integer_in(key, 0, size - 1):
			index = int(key)
		if index < 0 or index >= size or indices.has(index):
			return false
		indices[index] = true
	return not complete or values.size() == size


static func _index_value(values: Dictionary, index: int) -> Variant:
	return values.get(index, values.get(str(index)))


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)


static func _failure(code: String, record: int) -> Dictionary:
	return {"ok": false, "error": code, "record": record}
