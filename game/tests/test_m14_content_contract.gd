extends SceneTree

const Contract = preload("res://app/chapter_story_contract.gd")
const Content = preload("res://app/chapter_content.gd")
var failed: bool = false


func _initialize() -> void:
	_wait_pickup()
	_animation_flag()
	if not failed:
		print("PASS m14 content contracts: fixed wait pickup and animation flag")
	quit(1 if failed else 0)


func _wait_pickup() -> void:
	var map: Dictionary = {
		"width": 1,
		"height": 1,
		"tiles": [[39]],
		"terrain": [[3]],
		"movementCosts": {},
		"locations":
		[
			{
				"id": "wait_0",
				"sourceIndex": 0,
				"kind": "waitPickup",
				"position": [0, 0],
				"tileId": 39,
				"reward": {"kind": "item", "templateId": 26}
			}
		]
	}
	var rules: Dictionary = {"itemTemplates": [{"id": 26}]}
	_check(
		Contract.validate_locations(map, rules, {}), "A terrain3 fixed item is a valid wait pickup"
	)
	for invalid: String in [
		"extra",
		"opened",
		"terrain",
		"reward_kind",
		"reward_extra",
		"template",
		"source",
		"tile",
		"position",
		"id"
	]:
		var bad: Dictionary = map.duplicate(true)
		var location: Dictionary = bad["locations"][0]
		match invalid:
			"extra":
				location["weightedChoices"] = []
			"opened":
				location["openedVariant"] = "opened"
			"terrain":
				bad["terrain"][0][0] = 6
			"reward_kind":
				location["reward"] = {"kind": "goldRange", "minimum": 1, "maximum": 2}
			"reward_extra":
				location["reward"]["weightedChoices"] = []
			"template":
				location["reward"]["templateId"] = 999
			"source":
				location["sourceIndex"] = 1
			"tile":
				location["tileId"] = 44
			"position":
				location["position"] = [1, 0]
			"id":
				location["id"] = ""
		_check(
			not Contract.validate_locations(bad, rules, {}),
			"Reject invalid wait pickup: " + invalid
		)
	var duplicate: Dictionary = map.duplicate(true)
	duplicate["locations"].append(duplicate["locations"][0].duplicate(true))
	_check(
		not Contract.validate_locations(duplicate, rules, {}),
		"Reject duplicate location identity and position"
	)


func _animation_flag() -> void:
	var loader := Content.new()
	var content: Dictionary = loader.load_chapter("res://content/chapter_1/chapter.json")
	_check(content["ok"], "Existing chapter loads before checking animation definitions")
	if not content["ok"]:
		return
	var id: String = str(int(content["units"][0]["id"]))
	for value: Variant in [true, false]:
		var candidate: Dictionary = content.duplicate(true)
		candidate["mapAnimations"]["units"][id]["completedUsesActiveCycle"] = value
		_check(
			loader._validate(candidate)["ok"], "A boolean completed animation setting is accepted"
		)
	for value: Variant in [0, 1, "true", null, []]:
		var candidate: Dictionary = content.duplicate(true)
		candidate["mapAnimations"]["units"][id]["completedUsesActiveCycle"] = value
		_check(
			not loader._validate(candidate)["ok"],
			"A non-boolean completed animation setting is rejected"
		)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
