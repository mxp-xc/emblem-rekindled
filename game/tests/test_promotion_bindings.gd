extends SceneTree

const Promotions = preload("res://app/chapter_promotions.gd")
const Deployment = preload("res://app/chapter_deployment.gd")
const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _draws: int = 0


func _initialize() -> void:
	if not _source_contract() or not _session_contract():
		return
	print(
		"PASS promotion bindings: trusted families, temporary cold restore and formal inheritance"
	)
	quit(0)


func _source_contract() -> bool:
	var profiles: Dictionary = {}
	var recipes: Dictionary = {}
	for specification: Array in [
		["source", 0, 0, true],
		["source", 0, 1, true],
		["source", 9, 4, true],
		["slot", 2, 8, false],
		["slot", 2, 9, false],
		["slot", 7, 13, false]
	]:
		var key: String = "%s_%d_job_%d_faction_0" % specification.slice(0, 3)
		recipes[key] = key
		profiles[key] = {
			"unit":
			{
				"sourceId": specification[1],
				"classId": specification[2],
				"formal": specification[3],
				"faction": 0
			}
		}
	var rules: Dictionary = {"promotions": []}
	for pair: Array in [[0, 1], [4, 5], [8, 9], [12, 13]]:
		var gains: Dictionary = {}
		for stat: String in Promotions.STATS:
			gains[stat] = 1
		rules["promotions"].append(
			{"fromClassId": pair[0], "toClassId": pair[1], "minimumLevel": 10, "gains": gains}
		)
	var policy: Dictionary = Promotions.context(rules, profiles)
	if not _expect(policy["ok"], "Native source profiles establish unambiguous original classes"):
		return false
	var records: Array = [_record(0, 0), _record(1, 4), _record(2, 8), _record(7, 13)]
	var party: Array = [{"id": 0, "classId": 0}, {"id": 9, "classId": 4}]
	var bound: Dictionary = Deployment.bind(records, profiles, recipes, party, {}, {}, [], policy)
	if not _expect(bound["ok"], "Current formal and temporary families bind"):
		return false
	var saved: Array = bound["units"].duplicate(true)
	saved[2]["classId"] = 9
	saved[2]["promotionBaseClassId"] = 20
	var cold: Dictionary = Deployment.infer_bindings(records, party, saved, [], policy)
	if not _expect(
		cold["ok"] and cold["classes"][2] == 9,
		"A blue temporary may restore only its source promotion"
	):
		return false
	var promoted: Dictionary = Deployment.bind(
		records, profiles, recipes, party, cold["bindings"], cold["classes"], [], policy
	)
	if not _expect(
		promoted["ok"] and promoted["units"][2]["promotionBaseClassId"] == 8,
		"Saved provenance cannot replace the original slot class"
	):
		return false
	for index: int in [2, 3]:
		var invalid: Array = saved.duplicate(true)
		invalid[index]["classId"] = 13 if index == 2 else 14
		if not _expect(
			not Deployment.infer_bindings(records, party, invalid, [], policy)["ok"],
			"Cross-family and already-stage1 temporary changes are rejected"
		):
			return false
	var wrong_party: Array = party.duplicate(true)
	wrong_party[0]["classId"] = 9
	if not _expect(
		not Deployment.bind(records, profiles, recipes, wrong_party, {}, {}, [], policy)["ok"],
		"Formal identity cannot acquire another character family"
	):
		return false
	wrong_party = party.duplicate(true)
	wrong_party[0]["sourceId"] = 9
	wrong_party[0]["classId"] = 4
	if not _expect(
		not Deployment.bind(records, profiles, recipes, wrong_party, {}, {}, [], policy)["ok"],
		"Changing both saved source and class cannot impersonate another formal member"
	):
		return false
	var missing: Dictionary = recipes.duplicate()
	missing.erase("slot_2_job_9_faction_0")
	if not _expect(
		not (
			Deployment
			. bind(records, profiles, missing, party, cold["bindings"], cold["classes"], [], policy)["ok"]
		),
		"Missing target profile is an explicit binding failure"
	):
		return false
	var malformed: Dictionary = rules.duplicate(true)
	malformed["promotions"].append(malformed["promotions"][0].duplicate(true))
	return _expect(
		not Promotions.context(malformed, profiles)["ok"], "Promotion pairs cannot be ambiguous"
	)


func _session_contract() -> bool:
	var session := Session.new()
	var first: Dictionary = session.open(CHAPTER, "m0", {"new": true}, _roll)
	if not _expect(first["ok"], "Open the genuine first-map content"):
		return false
	# No emblem is obtainable before m1. m0 deliberately binds no future recipes,
	# even when a matching profile exists in the shared bank for later maps.
	if not _expect(
		(
			first["content"]["promotionTargets"].is_empty()
			and first["content"]["promotionErrors"].has(0)
			and first["content"]["promotionErrors"].has(9)
		),
		"A global future profile does not expand m0's declared map capability"
	):
		return false
	var silque_slot: int = -1
	for actor: Dictionary in first["battle"].snapshot()["units"]:
		if actor.get("temporary", false) and actor.get("deploymentSlot") == 1:
			silque_slot = int(actor["id"])
	if not _expect(
		silque_slot >= 0 and first["content"]["promotionErrors"].has(silque_slot),
		"A controlled m0 temporary cannot silently use an unprepared future family"
	):
		return false
	first["battle"].win_with_assistance()
	var progress: Dictionary = first["battle"].complete_victory(0)["progress"]
	var eligible_map: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _roll)
	if not _expect(eligible_map["ok"], "Open the first map with a natural emblem source"):
		return false
	for pair: Array in [[0, 1], [9, 5], [6, 21]]:
		var future: Dictionary = eligible_map["content"]["promotionTargets"].get(pair[0], {})
		if not _expect(
			(
				not future.is_empty()
				and future["classId"] == pair[1]
				and not eligible_map["content"]["promotionErrors"].has(pair[0])
			),
			"m1's existing and newly recruited formal members have validated future families"
		):
			return false
	var job: Dictionary = {}
	for row: Dictionary in first["content"]["rules"]["jobTemplates"]:
		if row["id"] == 1:
			job = row
	for actor: Dictionary in progress["party"]:
		if actor["id"] == 0:
			actor["classId"] = 1
			actor["classGroup"] = job["classGroup"]
			actor["equipMask"] = job["equipMask"]
			actor["level"] = 10
	var second: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _roll)
	if not _expect(
		second["ok"] and second["battle"].unit(0)["classId"] == 1,
		"A legal promoted formal member enters using its saved class"
	):
		return false
	var snapshot: Dictionary = second["battle"].snapshot()
	var temporary: int = -1
	for actor: Dictionary in snapshot["units"]:
		if actor.get("temporary", false) and actor.get("deploymentSlot") == 2:
			temporary = int(actor["id"])
			actor["classId"] = 9
			actor["level"] = 10
			actor["equipMask"] = 5
			actor["promotionBaseClassId"] = 36
	_draws = 0
	var restored: Dictionary = session.open(CHAPTER, "m1", {"snapshot": snapshot}, _roll)
	if not _expect(
		restored["ok"] and _draws == 0 and temporary >= 0,
		"Promoted blue temporary cold entry does not initialize or reroll"
	):
		return false
	if not _expect(
		(
			restored["battle"].unit(temporary)["classId"] == 9
			and restored["battle"].unit(temporary)["promotionBaseClassId"] == 8
		),
		"Cold metadata comes from slot2 rather than the saved forged base"
	):
		return false
	var encoded: Dictionary = Store.new(restored["content"]).encode(restored["battle"])
	if not _expect(encoded["ok"], "Promoted state encodes through the real Store"):
		return false
	_draws = 0
	var decoded: Dictionary = Store.new(restored["content"]).decode(encoded["record"], _roll)
	if not _expect(
		(
			decoded["ok"]
			and _draws == 0
			and decoded["battle"].snapshot() == restored["battle"].snapshot()
		),
		"Full promoted state cold roundtrip is exact and consumes no RNG"
	):
		return false
	var invalid: Dictionary = snapshot.duplicate(true)
	for actor: Dictionary in invalid["units"]:
		if actor["id"] == temporary:
			actor["attributes"]["strength"] = 32767
	return _expect(
		not session.open(CHAPTER, "m1", {"snapshot": invalid}, _roll)["ok"],
		"Promotion provenance does not permit arbitrary attributes above its finite bound"
	)


func _record(slot: int, class_id: int) -> Dictionary:
	return {
		"kind": 1,
		"sourceId": slot,
		"classId": class_id,
		"faction": 0,
		"deploymentSlot": slot,
		"level": 1,
		"flags": 0,
		"policy": 32,
		"randomEquipment": false,
		"itemChoices": [0, 0, 0],
		"dropTemplateId": 0,
		"position": [slot, 0]
	}


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(1)
	return value
