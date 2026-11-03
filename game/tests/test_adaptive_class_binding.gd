extends SceneTree

const Deployment = preload("res://app/chapter_deployment.gd")
const Clones = preload("res://gameplay/battle_clones.gd")


func _initialize() -> void:
	var records: Array = [
		{
			"kind": 1,
			"sourceId": 80,
			"classId": 8,
			"faction": 2,
			"level": 1,
			"flags": 0,
			"policy": 0,
			"position": [0, 0],
			"randomEquipment": false,
			"itemChoices": [0, 0, 0],
			"dropTemplateId": 0
		}
	]
	var profiles: Dictionary = {
		"base": {"unit": {"classId": 8}}, "selected": {"unit": {"classId": 9}}
	}
	var recipes: Dictionary = {
		"source_80_job_8_faction_2": "base", "source_80_job_9_faction_2": "selected"
	}
	var initial: Dictionary = Deployment.bind(records, profiles, recipes, [])
	if not initial["ok"] or initial["units"][0]["classId"] != 8:
		fail("A null context retains the raw deployment class")
		return
	var saved: Array = initial["units"].duplicate(true)
	saved[0]["classId"] = 9
	var inferred: Dictionary = Deployment.infer_bindings(records, [], saved)
	if not inferred["ok"] or inferred["classes"] != {0: 9}:
		fail("A saved kind1 enemy may retain its selected same-group class")
		return
	var rebound: Dictionary = Deployment.bind(
		records, profiles, recipes, [], inferred["bindings"], inferred["classes"]
	)
	if not rebound["ok"] or rebound["units"][0]["classId"] != 9:
		fail("The selected class must bind its own declared presentation profile")
		return
	saved[0]["classId"] = 10
	if Deployment.infer_bindings(records, [], saved)["ok"]:
		fail("A save cannot select an unrelated class")
		return
	var policy: Dictionary = {
		"id": "fixture",
		"pool": [105, 127],
		"throughRound": 3,
		"branches": [{"period": 3, "templateUnitIds": [80]}]
	}
	var root: Dictionary = rebound["units"][0].duplicate(true)
	var clone: Dictionary = root.duplicate(true)
	clone["id"] = 105
	for key: String in ["deploymentIndex", "deploymentSlot", "temporary"]:
		clone.erase(key)
	var bindings: Dictionary = {
		"nextGeneration": 2,
		"bindings": [{"unitId": 105, "generation": 1, "templateDeploymentIndex": 0}]
	}
	if not Clones.current_bindings(policy, records, [root, clone], bindings)["ok"]:
		fail("A clone may preserve its selected root class")
		return
	root["classId"] = 8
	if Clones.current_bindings(policy, records, [root, clone], bindings)["ok"]:
		fail("A clone cannot choose another tier while its original root is present")
		return
	root["classId"] = 9
	clone["classId"] = 10
	if Clones.current_bindings(policy, records, [root, clone], bindings)["ok"]:
		fail("A clone cannot forge an unrelated root class")
		return
	if not check_new_classes(records[0]):
		return
	print("PASS adaptive class binding: trusted static and clone identities")
	quit(0)


func check_new_classes(template: Dictionary) -> bool:
	var profiles: Dictionary = {"base": {"unit": {"classId": 8}}, "tier": {"unit": {"classId": 9}}}
	var context: Dictionary = {
		"attributes": {"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
		"maxHp": 0,
		"maxInternalLevel": 9,
		"averageInternalLevel": 8,
		"maxProficiency": 0
	}
	for faction: int in [1, 2]:
		var record: Dictionary = template.duplicate(true)
		record["faction"] = faction
		var recipes: Dictionary = {
			"source_80_job_8_faction_%d" % faction: "base",
			"source_80_job_9_faction_%d" % faction: "tier"
		}
		var bound: Dictionary = Deployment.bind(
			[record], profiles, recipes, [], {}, {}, [], {}, context
		)
		var expected_level: int = 9 if faction == 1 else 10
		var expected_class: int = 8 if faction == 1 else 9
		if (
			not bound["ok"]
			or bound["spawns"][0]["level"] != expected_level
			or bound["units"][0]["classId"] != expected_class
		):
			fail("C1 must use average level and C2 maximum; internal level 9 selects tier +1")
			return false
	var fixed: Dictionary = template.duplicate(true)
	fixed["kind"] = 0
	fixed["explicitStats"] = {
		"strength": 5,
		"skill": 5,
		"speed": 5,
		"defense": 5,
		"magic": 5,
		"luck": 5,
		"maxHp": 20,
		"move": 3
	}
	var recipes: Dictionary = {"source_80_job_8_faction_2": "base"}
	var bound: Dictionary = Deployment.bind([fixed], profiles, recipes, [], {}, {}, [], {}, context)
	if not bound["ok"] or bound["spawns"][0]["level"] != 1 or bound["units"][0]["classId"] != 8:
		fail("Explicit-stat kind0 keeps its declared level and class")
		return false
	var player: Dictionary = template.duplicate(true)
	player["faction"] = 0
	recipes = {"source_80_job_8_faction_0": "base"}
	bound = Deployment.bind([player], profiles, recipes, [], {}, {}, [], {}, context)
	if not bound["ok"] or bound["spawns"][0]["level"] != 9 or bound["units"][0]["classId"] != 8:
		fail("A newly generated C0 uses the average level without changing class")
		return false
	player["deploymentSlot"] = 0
	player["sourceId"] = 0
	player["policy"] = 32
	recipes = {"slot_0_job_8_faction_0": "base", "source_0_job_8_faction_0": "base"}
	bound = Deployment.bind([player], profiles, recipes, [], {}, {}, [], {}, context)
	if not bound["ok"] or bound["spawns"][0]["id"] != 95 or bound["spawns"][0]["level"] != 9:
		fail("An unoccupied C0 slot generates a temporary unit at the average level")
		return false
	var unchanged: Dictionary = template.duplicate(true)
	unchanged["classId"] = 9
	recipes = {"source_80_job_9_faction_2": "tier"}
	bound = Deployment.bind([unchanged], profiles, recipes, [], {}, {}, [], {}, context)
	if not bound["ok"] or bound["spawns"][0]["level"] != 10 or bound["units"][0]["classId"] != 9:
		fail("A kind1 class not divisible by four keeps its class at the selected level")
		return false
	recipes = {"source_80_job_8_faction_2": "base"}
	bound = Deployment.bind([template], profiles, recipes, [], {}, {}, [], {}, context)
	if bound["ok"] or bound.get("error") != "MISSING_PRESENTATION_PROFILE":
		fail("A selected tier without its declared profile must fail instead of falling back")
		return false
	return true


func fail(message: String) -> void:
	push_error(message)
	quit(1)
