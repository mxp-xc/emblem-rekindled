extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _owned: String = ""
var _draws: int = 0


func _initialize() -> void:
	_owned = "user://clone_bindings_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim owned clone binding fixture")
		return
	var entry: Dictionary = _json(CHAPTER)
	var definition: Dictionary = _json(entry["battles"]["m0"])
	var records: Array = _json(definition["deployments"])
	var story: Dictionary = _json(definition["story"])
	# Keep real m0 recipes/resources, with two declared enemy identities in the
	# fixture's clone pool. No production registration or world record is changed.
	records[1]["id"] = 107
	records[2]["id"] = 108
	story["periodicClones"] = {
		"id": "fixture_clones",
		"pool": [105, 127],
		"throughRound": 10,
		"branches": [{"period": 3, "templateUnitIds": [107, 108]}]
	}
	definition["deployments"] = _owned.path_join("deployments.json")
	definition["story"] = _owned.path_join("story.json")
	entry["battles"]["m0"] = _owned.path_join("battle.json")
	for row: Array in [
		[definition["deployments"], records],
		[definition["story"], story],
		[entry["battles"]["m0"], definition],
		[_owned.path_join("chapter.json"), entry]
	]:
		var file := FileAccess.open(row[0], FileAccess.WRITE)
		if file == null:
			_fail("Cannot write owned fixture")
			return
		file.store_string(JSON.stringify(row[1]))
	var opened: Dictionary = Session.new().open(
		_owned.path_join("chapter.json"), "m0", {"new": true}, _roll
	)
	if not _expect(
		opened["ok"], "Open clone fixture with real m0 library: " + str(opened.get("error"))
	):
		return
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 7
	state["events"]["fixture_clones:round_3"] = true
	state["events"]["fixture_clones:round_6"] = true
	state["cloneState"] = {
		"nextGeneration": 4,
		"bindings":
		[
			{"unitId": 105, "generation": 1, "templateDeploymentIndex": 1},
			{"unitId": 106, "generation": 2, "templateDeploymentIndex": 2},
			{"unitId": 107, "generation": 3, "templateDeploymentIndex": 2}
		]
	}
	var actors: Array = []
	for actor: Dictionary in state["units"]:
		if actor["id"] != 107:
			actors.append(actor)
	for pair: Array in [[105, 107], [106, 108], [107, 108]]:
		var actor: Dictionary = battle.unit(pair[1])
		actor["id"] = pair[0]
		actor["visible"] = false
		actor["flags"] = 1
		actor["hp"] = 0 if pair[0] == 106 else actor["maxHp"]
		actor["sprite"] = "save-cannot-select-an-image.png"
		actor["name"] = "save-cannot-select-a-name"
		for key: String in ["deploymentIndex", "deploymentSlot", "temporary"]:
			actor.erase(key)
		for index: int in range(actor["inventory"].size()):
			var item: Dictionary = actor["inventory"][index]
			var old: String = item["id"]
			item["id"] = "arbitrary opaque item %d/%d" % [pair[0], index]
			if actor["equippedInstanceId"] == old:
				actor["equippedInstanceId"] = item["id"]
		actors.append(actor)
	state["units"] = actors
	state["warehouse"] = [{"id": "opaque warehouse", "templateId": 60, "durability": 2}]
	state = JSON.parse_string(JSON.stringify(state))
	if not _restore_and_project(opened["content"], state):
		return
	for change: String in ["actor", "family", "generation", "missing", "static", "event", "item"]:
		var invalid: Dictionary = state.duplicate(true)
		match change:
			"actor":
				invalid["cloneState"]["bindings"][0]["unitId"] = 128
			"family":
				invalid["cloneState"]["bindings"][0]["templateDeploymentIndex"] = 0
			"generation":
				invalid["cloneState"]["nextGeneration"] = 3
			"missing":
				invalid["cloneState"]["bindings"].remove_at(0)
			"static":
				invalid["units"][-1]["deploymentIndex"] = 1
			"event":
				invalid["events"].erase("fixture_clones:round_3")
			"item":
				invalid["warehouse"][0]["id"] = invalid["units"][-1]["inventory"][0]["id"]
		_draws = 0
		var rejected: Dictionary = Session.new().open(
			_owned.path_join("chapter.json"), "m0", {"snapshot": invalid}, _roll
		)
		if not _expect(not rejected["ok"] and _draws == 0, "Reject invalid clone " + change):
			return
	_cleanup()
	print("PASS clone bindings: root families, generations, opaque items and JSON actor rejection")
	quit(0)


func _restore_and_project(content: Dictionary, state: Dictionary) -> bool:
	var before: Dictionary = state.duplicate(true)
	_draws = 0
	var restored: Dictionary = Session.new().open(
		_owned.path_join("chapter.json"), "m0", {"snapshot": state}, _roll
	)
	if not _expect(restored["ok"], "Restore clone fixture: " + str(restored.get("error"))):
		return false
	var projected: Dictionary = restored["content"]
	var original: Array = content["unitOrder"].duplicate()
	original.erase(107)
	original.append_array([105, 106, 107])
	if not _expect(
		(
			_draws == 0
			and state == before
			and projected["unitOrder"] == original
			and projected["profiles"][105] == content["profiles"][107]
			and projected["profiles"][107] == content["profiles"][108]
			and not restored["battle"].unit(106)["visible"]
			and restored["battle"].unit(106)["hp"] == 0
			and restored["battle"].unit(105)["name"] != "save-cannot-select-a-name"
		),
		"Restore uses declared root recipes after the original root was recycled, with no RNG"
	):
		return false
	var swapped: Dictionary = state.duplicate(true)
	swapped["units"].reverse()
	swapped["cloneState"]["bindings"].reverse()
	var again: Dictionary = Session.new().open(
		_owned.path_join("chapter.json"), "m0", {"snapshot": swapped}, _roll
	)
	if not _expect(
		(
			again["ok"]
			and again["battle"].snapshot() == restored["battle"].snapshot()
			and again["content"]["unitOrder"] == original
			and _draws == 0
		),
		"JSON array order cannot alter static native order or generation order"
	):
		return false
	# Rebinding from a previous projection must remove every old weapon alias.
	var current: Dictionary = Content.new().reproject(
		projected, state["units"], state["cloneState"]
	)
	if not _expect(current["ok"], "Pure runtime clone reproject"):
		return false
	for identity: int in [105, 106, 107]:
		var profile: Dictionary = current["_library"]["profiles"][current["profiles"][identity]]
		if not _expect(
			(
				current["mapAnimations"]["units"].has(str(identity))
				and current["interface"]["portraitByUnitId"].has(str(identity))
			),
			"Every dynamic identity has map animation and portrait aliases"
		):
			return false
		for catalog: String in ["battleArt", "battleClips"]:
			var actual: Array = []
			for alias: String in current[catalog]["appearances"]:
				if alias.begins_with("%d:" % identity):
					actual.append(alias.get_slice(":", 1))
			var expected: Array = profile["appearances"].keys()
			actual.sort()
			expected.sort()
			if not _expect(
				actual == expected, "Dynamic weapon aliases match only its current family"
			):
				return false
	return true


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _cleanup() -> void:
	if _owned.is_empty():
		return
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	_cleanup()
	push_error(message)
	quit(1)
