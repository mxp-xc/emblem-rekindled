extends SceneTree

const Contract = preload("res://app/chapter_story_contract.gd")
var failed: bool = false


func _initialize() -> void:
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
				"reward":
				{
					"kind": "weightedItem",
					"weightedChoices":
					[{"templateId": 72, "weight": 20}, {"templateId": 73, "weight": 20}]
				}
			}
		]
	}
	var rules: Dictionary = {"itemTemplates": [{"id": 72}, {"id": 73}]}
	_check(
		Contract.validate_locations(map, rules, {}),
		"Weighted wait pickup with empty remainder accepted"
	)
	var terrain_four: Dictionary = map.duplicate(true)
	terrain_four["terrain"] = [[4]]
	_check(Contract.validate_locations(terrain_four, rules, {}), "Terrain 4 wait pickup accepted")
	for bad_choices: Array in [
		[],
		[{"templateId": 72, "weight": 101}],
		[{"templateId": 999, "weight": 20}],
		[{"templateId": 72, "weight": 0}]
	]:
		var invalid: Dictionary = map.duplicate(true)
		invalid["locations"][0]["reward"]["weightedChoices"] = bad_choices
		_check(
			not Contract.validate_locations(invalid, rules, {}),
			"Invalid weighted wait pickup rejected"
		)
	var invalid: Dictionary = map.duplicate(true)
	invalid["locations"][0]["reward"] = {"kind": "goldRange", "minimum": 1, "maximum": 2}
	_check(not Contract.validate_locations(invalid, rules, {}), "Gold is not a wait pickup")
	var visit: Dictionary = map.duplicate(true)
	visit["tiles"] = [[59]]
	visit["terrain"] = [[6]]
	visit["locations"][0]["kind"] = "visit"
	visit["locations"][0]["tileId"] = 59
	visit["locations"][0]["reward"] = {"kind": "gold", "amount": 1000}
	_check(Contract.validate_locations(visit, rules, {}), "Fixed gold visit is accepted")
	for amount: Variant in [0, -1, 10000000, 1.5, "1000"]:
		visit["locations"][0]["reward"]["amount"] = amount
		_check(not Contract.validate_locations(visit, rules, {}), "Invalid fixed gold is rejected")
	_fixed_chest()
	if not failed:
		print("PASS m15 weighted wait pickup content contract")
	quit(1 if failed else 0)


func _fixed_chest() -> void:
	var map: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/generated/battles/m15/map.json")
	)
	var rules: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/generated/rules.json")
	)
	var chest: Dictionary = map["locations"][0]
	chest.erase("weightedChoices")
	chest["reward"] = {"kind": "item", "templateId": 9}
	_check(Contract.validate_locations(map, rules, {}), "Fixed item chest is accepted")
	chest["weightedChoices"] = [{"templateId": 9, "weight": 1}]
	_check(not Contract.validate_locations(map, rules, {}), "Chest rewards are mutually exclusive")
	chest.erase("weightedChoices")
	chest["reward"] = {"kind": "item", "templateId": 999}
	_check(not Contract.validate_locations(map, rules, {}), "Unknown fixed chest item rejected")
	chest["reward"] = {"kind": "gold", "amount": 1000}
	_check(not Contract.validate_locations(map, rules, {}), "Fixed gold is not a chest reward")
	chest["reward"] = {"kind": "goldRange", "minimum": 1, "maximum": 2000}
	_check(Contract.validate_locations(map, rules, {}), "A gold range is a valid chest reward")
	chest["reward"]["minimum"] = 2001
	_check(not Contract.validate_locations(map, rules, {}), "Reversed chest gold range is rejected")
	chest.erase("reward")
	chest["weightedChoices"] = [{"templateId": 9, "weight": 90}]
	chest["emptyWeight"] = 10
	_check(Contract.validate_locations(map, rules, {}), "Weighted chest can have an empty outcome")
	for weight: Variant in [0, 9, 11, 100, 1.5, "10"]:
		chest["emptyWeight"] = weight
		_check(not Contract.validate_locations(map, rules, {}), "Invalid empty weight rejected")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
