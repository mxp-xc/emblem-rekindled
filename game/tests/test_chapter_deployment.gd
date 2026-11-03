extends SceneTree

const Deployment = preload("res://app/chapter_deployment.gd")


func _initialize() -> void:
	var records: Array = []
	var profiles: Dictionary = {}
	var recipes: Dictionary = {}
	for slot: int in range(7):
		records.append(
			{
				"kind": 1,
				"sourceId": slot,
				"deploymentSlot": slot,
				"classId": 8,
				"faction": 0,
				"level": 1,
				"flags": 1,
				"policy": 32,
				"randomEquipment": false,
				"itemChoices": [0, 0, 0],
				"dropTemplateId": 0,
				"position": [slot, 1]
			}
		)
		add_profile(profiles, recipes, "slot_%d_job_8_faction_0" % slot, 8)
	for identity: int in range(10):
		add_profile(profiles, recipes, "source_%d_job_0_faction_0" % identity, 0)
	records.append(
		{
			"kind": 1,
			"sourceId": 7,
			"classId": 0,
			"faction": 0,
			"level": 1,
			"flags": 0,
			"policy": 0,
			"randomEquipment": false,
			"itemChoices": [0, 0, 0],
			"dropTemplateId": 0,
			"position": [17, 9]
		}
	)
	var party: Array = [{"id": 0, "classId": 0}, {"id": 9, "classId": 0}, {"id": 6, "classId": 0}]
	var original: Array = party.duplicate(true)
	var early: Dictionary = Deployment.bind(records, profiles, recipes, party)
	if (
		not early["ok"]
		or party != original
		or early["slots"] != {0: 0, 1: 9, 2: 6, 3: 95, 4: 96, 5: 97, 6: 98}
	):
		fail("One deployment must bind recruit order and fill only unoccupied slots")
		return
	if early["spawns"][2]["policy"] != 0 or early["spawns"][2]["deploymentSlot"] != 2:
		fail("A recruit slot must not become an AI policy bitmask")
		return
	var encounter: Dictionary = Deployment.bind(
		records, profiles, recipes, party, {}, {}, [], {}, null, true
	)
	if (
		not encounter["ok"]
		or encounter["slots"] != {0: 0, 1: 9, 2: 6}
		or encounter["units"].size() != 4
	):
		fail("An encounter must leave unused slots empty and keep fixed deployments")
		return
	var restored: Dictionary = Deployment.infer_bindings(
		records, party, encounter["units"], [], {}, true
	)
	if not restored["ok"] or restored["bindings"][3] != -1:
		fail("Encounter snapshots must preserve vacant deployment slots")
		return
	var rebound: Dictionary = Deployment.bind(
		records,
		profiles,
		recipes,
		party,
		restored["bindings"],
		restored["classes"],
		[],
		{},
		null,
		true
	)
	if not rebound["ok"] or rebound["units"] != encounter["units"]:
		fail("Restoring an encounter must recover the same units without filling vacant slots")
		return
	var missing_fixed: Array = encounter["units"].duplicate(true)
	missing_fixed.pop_back()
	if Deployment.infer_bindings(records, party, missing_fixed, [], {}, true)["ok"]:
		fail("Allowing vacant encounter slots must not permit missing fixed units")
		return
	party = []
	for identity: int in [0, 9, 2, 4, 5, 1, 6]:
		party.append({"id": identity, "classId": 0})
	var late: Dictionary = Deployment.bind(records, profiles, recipes, party)
	if not late["ok"] or late["slots"].values().has(95) or late["units"].size() != 8:
		fail("Seven inherited members and the new recruit must share the same configuration")
		return
	var recruits: Dictionary = {
		"0": 9, "1": 6, "2": 7, "3": 3, "4": 8, "5": 2, "6": 4, "7": 5, "8": 1
	}
	if Deployment.recruit_order([0, 5, 6, 7, 8, 12, 1, 2], recruits, 7) != [0, 9, 2, 4, 5, 1, 6]:
		fail("Route prefixes must reconstruct recruit order independently of saved array ordering")
		return
	var invalid: Array = records.duplicate(true)
	invalid[1]["deploymentSlot"] = 0
	if Deployment.bind(invalid, profiles, recipes, original)["ok"]:
		fail("Duplicate slots must reject before any result is published")
		return
	var missing: Dictionary = recipes.duplicate()
	missing.erase("source_6_job_0_faction_0")
	var rejected: Dictionary = Deployment.bind(records, profiles, missing, original)
	if rejected["ok"] or rejected["error"] != "MISSING_PRESENTATION_PROFILE":
		fail(
			"Missing visual coverage must report the requested profile rather than use another actor"
		)
		return
	if not check_routes(records, profiles, recipes, recruits):
		return
	if not check_rebinding():
		return
	if not check_saved_classes():
		return
	if not check_declared_identities():
		return
	if not check_first_battle_slots():
		return
	print("PASS chapter deployment: route order, dynamic slots, profile identity and failures")
	quit(0)


func add_profile(profiles: Dictionary, recipes: Dictionary, key: String, class_id: int) -> void:
	recipes[key] = key
	profiles[key] = {"unit": {"classId": class_id}}


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func check_routes(
	records: Array, profiles: Dictionary, recipes: Dictionary, recruits: Dictionary
) -> bool:
	var contexts: Array = [
		[[0, 1, 2], 2, [0, 9, 6]],
		[[0, 3, 2], 2, [0, 9, 3]],
		[[0, 5, 6, 7, 8, 12, 1, 2], 7, [0, 9, 2, 4, 5, 1, 6]],
		[[0, 5, 4, 3, 2], 4, [0, 9, 2, 8, 3]],
		[[0, 7, 8, 1, 2], 4, [0, 9, 5, 1, 6]],
		[[0, 7, 6, 5, 4, 10, 3, 2], 7, [0, 9, 5, 4, 2, 8, 3]]
	]
	for context: Array in contexts:
		var order: Array = Deployment.recruit_order(context[0], recruits, context[1])
		if order != context[2]:
			fail("Each reachable m2 route must reconstruct its actual recruit sequence")
			return false
		var party: Array = []
		for identity: int in order:
			party.append({"id": identity, "classId": 0})
		var bound: Dictionary = Deployment.bind(records, profiles, recipes, party)
		if not bound["ok"] or bound["units"].size() != 8:
			fail("All six m2 contexts must bind the same deployment definition")
			return false
		for slot: int in range(order.size()):
			if bound["slots"][slot] != order[slot]:
				fail("Inherited deployment identity must follow recruit order")
				return false
	if not Deployment.recruit_order([0], recruits, 2).is_empty():
		fail("Invalid route prefix must reject without reading beyond the route")
		return false
	if (
		Deployment.recruit_order([0], recruits, 0, [2, 4]) != [2, 4]
		or not Deployment.recruit_order([], recruits, 0, [2, 2]).is_empty()
	):
		fail("Chapter-defined initial members must preserve order and reject duplicate identities")
		return false
	return true


func check_rebinding() -> bool:
	var records: Array = [record(0, 8, 0), record(1, 8, 0), record(107, 8, 2)]
	for index: int in range(2):
		records[index]["deploymentSlot"] = index
		records[index]["policy"] = 32
	records[0].erase("position")
	records[0]["deploymentRegions"] = [[0, 0, 1, 1], [1, 1, 2, 2]]
	var profiles: Dictionary = {}
	var recipes: Dictionary = {}
	for recipe: String in [
		"slot_0_job_8_faction_0", "slot_1_job_8_faction_0", "source_107_job_8_faction_2"
	]:
		add_profile(profiles, recipes, recipe, 8)
	var initial: Dictionary = Deployment.bind(records, profiles, recipes, [])
	if not initial["ok"] or initial["slots"] != {0: 95, 1: 96}:
		fail("Initial identities must be allocated in deployment order")
		return false
	var bindings: Dictionary = {0: -1, 1: 95, 2: 107}
	var rebound: Dictionary = Deployment.bind(records, profiles, recipes, [], bindings)
	if (
		not rebound["ok"]
		or rebound["slots"] != {1: 95}
		or rebound["units"].size() != 2
		or rebound["spawns"][0]["deploymentIndex"] != 1
		or not rebound["spawns"][0]["temporary"]
		or rebound["spawns"][0]["baseTemplateId"] != 1
	):
		fail(
			"A skipped regional record must not consume a temporary identity or change source growth"
		)
		return false
	var saved: Array = rebound["units"].duplicate(true)
	var inferred: Dictionary = Deployment.infer_bindings(records, [], saved)
	if not inferred["ok"] or inferred["bindings"] != bindings:
		fail("Save restore must recover actual identities without reselecting random deployment")
		return false
	for unit: Dictionary in saved:
		unit.erase("deploymentIndex")
	if not Deployment.infer_bindings(records, [], saved)["ok"]:
		fail("Existing unindexed records must match unique source identities")
		return false
	saved[0]["deploymentIndex"] = 0
	if Deployment.infer_bindings(records, [], saved)["ok"]:
		fail("A forged record index must not change a temporary actor's source slot")
		return false
	if Deployment.bind(records, profiles, recipes, [], {0: -1, 1: -1, 2: 107})["ok"]:
		fail("A fixed deployment must not be omitted")
		return false
	if Deployment.bind(records, profiles, recipes, [], {0: -1, 1: 96, 2: 107})["ok"]:
		fail("Temporary identities must remain contiguous after omitted deployments")
		return false
	if Deployment.infer_bindings(records, [], [rebound["units"][0]])["ok"]:
		fail("Missing fixed saved actors must reject")
		return false
	var invalid: Array = records.duplicate(true)
	invalid[0]["deploymentRegions"][1] = [2, 2, 1, 1]
	if Deployment.bind(invalid, profiles, recipes, [])["ok"]:
		fail("Every region, including later rectangles, must be valid")
		return false
	return true


func check_saved_classes() -> bool:
	var records: Array = [record(7, 0, 0), record(82, 8, 2)]
	records[0]["kind"] = 0
	records[0]["explicitStats"] = {
		"strength": 5,
		"skill": 4,
		"speed": 3,
		"defense": 2,
		"magic": 1,
		"luck": 0,
		"maxHp": 30,
		"move": 6
	}
	records[1].erase("position")
	records[1]["deploymentRegions"] = [[0, 0, 0, 0]]
	var profiles: Dictionary = {}
	var recipes: Dictionary = {}
	add_profile(profiles, recipes, "source_7_job_0_faction_0", 0)
	add_profile(profiles, recipes, "source_7_job_4_faction_0", 4)
	add_profile(profiles, recipes, "source_82_job_8_faction_2", 8)
	var bound: Dictionary = Deployment.bind(records, profiles, recipes, [])
	if not bound["ok"] or bound["units"][0]["hp"] != 30 or bound["units"][0]["move"] != 6:
		fail("Explicit source stats must be reflected in the static prototype")
		return false
	var saved: Array = bound["units"].duplicate(true)
	saved.remove_at(1)
	saved[0]["classId"] = 4
	saved[0]["x"] = 99
	var inferred: Dictionary = Deployment.infer_bindings(records, [], saved)
	if not inferred["ok"] or inferred["classes"] != {0: 4}:
		fail(
			"A directly recruited formal actor must restore its current class independently of position"
		)
		return false
	var restored: Dictionary = Deployment.bind(
		records, profiles, recipes, [], inferred["bindings"], inferred["classes"]
	)
	if (
		not restored["ok"]
		or restored["units"][0]["classId"] != 4
		or 82 not in restored["referenceIds"]
	):
		fail("Restored profiles must follow the saved class and preserve omitted source references")
		return false
	if Deployment.bind(records, profiles, recipes, [], {}, {1: 4})["ok"]:
		fail("Nonformal classes cannot be replaced from saved data")
		return false
	return true


func record(source_id: int, class_id: int, faction: int) -> Dictionary:
	return {
		"kind": 1,
		"sourceId": source_id,
		"classId": class_id,
		"faction": faction,
		"level": 1,
		"flags": 0,
		"policy": 0,
		"position": [source_id, 0],
		"randomEquipment": false,
		"itemChoices": [0, 0, 0],
		"dropTemplateId": 0
	}


func check_declared_identities() -> bool:
	var custom: Dictionary = record(9, 0, 0)
	custom["id"] = 300
	custom["formal"] = true
	custom["position"] = [0, 0]
	custom["itemChoices"] = [200, 60, 0]
	var profiles: Dictionary = {}
	var recipes: Dictionary = {}
	add_profile(profiles, recipes, "source_9_job_0_faction_0", 0)
	var bound: Dictionary = Deployment.bind([custom], profiles, recipes, [])
	if (
		not bound["ok"]
		or bound["units"][0]["id"] != 300
		or bound["units"][0]["sourceId"] != 9
		or not bound["units"][0]["formal"]
		or bound["spawns"][0]["growthTemplateId"] != 9
		or bound["spawns"][0]["baseTemplateId"] != 9
		or bound["spawns"][0]["itemChoices"] != [200, 60, 0]
		or bound["referenceIds"] != [300]
	):
		fail(
			"Declared actor identities and item templates must be independent from source protocol IDs"
		)
		return false
	custom.erase("formal")
	bound = Deployment.bind([custom], profiles, recipes, [])
	if (
		not bound["ok"]
		or not bound["units"][0]["formal"]
		or bound["spawns"][0]["growthTemplateId"] != 9
	):
		fail(
			"Default formal identity and growth must follow the source rather than actual declared ID"
		)
		return false
	custom["formal"] = true
	custom["dropTemplateId"] = 300
	var custom_drop: Dictionary = Deployment.bind([custom], profiles, recipes, [])
	if not custom_drop["ok"] or custom_drop["spawns"][0]["dropTemplateId"] != 300:
		fail("Normalized drops must allow declared item identities beyond the native byte protocol")
		return false
	for invalid_drop: Variant in [-1, 0.5]:
		custom["dropTemplateId"] = invalid_drop
		if Deployment.bind([custom], profiles, recipes, [])["ok"]:
			fail("Drop references must reject negative or fractional item identities")
			return false
	custom["dropTemplateId"] = 0
	var saved: Array = JSON.parse_string(JSON.stringify(bound["units"]))
	var inferred: Dictionary = Deployment.infer_bindings([custom], [], saved)
	if not inferred["ok"] or inferred["bindings"] != {0: 300}:
		fail("A declared actor above 255 must preserve its fixed identity across JSON restore")
		return false
	saved[0]["id"] = 301
	if Deployment.infer_bindings([custom], [], saved)["ok"]:
		fail("High identities still require an exact declared actor")
		return false
	custom["growthTemplateId"] = 205
	custom["baseTemplateId"] = 206
	custom["initialGrowthTemplateId"] = 207
	bound = Deployment.bind([custom], profiles, recipes, [])
	if (
		not bound["ok"]
		or bound["spawns"][0]["growthTemplateId"] != 205
		or bound["spawns"][0]["baseTemplateId"] != 206
		or bound["spawns"][0]["initialGrowthTemplateId"] != 207
	):
		fail("Explicit chapter template references must survive binding")
		return false
	var slot: Dictionary = record(0, 8, 0)
	slot["deploymentSlot"] = 0
	slot["policy"] = 32
	var party: Array = [{"id": 300, "sourceId": 9, "classId": 0, "formal": true}]
	bound = Deployment.bind([slot], profiles, recipes, party)
	if not bound["ok"] or bound["slots"] != {0: 300} or bound["spawns"][0]["sourceId"] != 9:
		fail("Inherited high identities must bind their declared source profile")
		return false
	if Deployment.recruit_order([0], {"0": 301}, 1, [300]) != [300, 301]:
		fail("Chapter initial party and recruits may declare high identities")
		return false
	if not Deployment.recruit_order([], {}, 0, [300, 300]).is_empty():
		fail("Duplicate initial identities must reject")
		return false
	for invalid_source: Variant in [256, -1, 9.5]:
		custom["sourceId"] = invalid_source
		if Deployment.bind([custom], profiles, recipes, [])["ok"]:
			fail("High declared identities must not widen source protocol bounds")
			return false
	return true


func check_first_battle_slots() -> bool:
	var records: Array = []
	var profiles: Dictionary = {}
	var recipes: Dictionary = {}
	for slot: int in [2, 5, 3, 4, 1]:
		var raw: Dictionary = record(slot, 8, 0)
		raw["deploymentSlot"] = slot
		raw["policy"] = 32
		records.append(raw)
		add_profile(profiles, recipes, "slot_%d_job_8_faction_0" % slot, 8)
	var result: Dictionary = Deployment.bind(records, profiles, recipes, [])
	if not result["ok"] or result["slots"] != {2: 95, 5: 96, 3: 97, 4: 98, 1: 99}:
		fail("The first battle's unoccupied source slots need not start at zero or be contiguous")
		return false
	add_profile(profiles, recipes, "source_0_job_0_faction_0", 0)
	if Deployment.bind(records, profiles, recipes, [{"id": 0, "classId": 0}])["ok"]:
		fail("Every actual inherited member still requires its corresponding slot")
		return false
	return true
