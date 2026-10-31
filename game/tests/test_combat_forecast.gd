extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://gameplay/combat_rules.gd")
	if script == null:
		quit(1)
		return
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var rules: RefCounted = script.new(content["rules"], content["map"]["terrain"])
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_combat.json")
	)
	var units: Dictionary = {}
	for unit: Dictionary in content["units"]:
		units[int(unit["id"])] = unit
	for sample: Dictionary in oracle["formulaCases"]:
		var actual: Dictionary = rules.forecast(
			units[int(sample["pair"][0])], units[int(sample["pair"][1])]
		)
		for key: String in [
			"weapon", "damage", "criticalDamage", "hit", "critical", "speed", "double"
		]:
			if actual[key] != sample[key]:
				push_error(
					(
						"Forecast %s for %s: expected %s, got %s"
						% [key, sample["pair"], sample[key], actual[key]]
					)
				)
				quit(1)
				return
	print("PASS combat forecast: six independent original method samples")
	quit(0)
