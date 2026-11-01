extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://gameplay/combat_rules.gd")
	if script == null:
		quit(1)
		return
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	# These are the formula oracle's recorded native inputs, exported after
	# ImportChapter1.java prepared the original map with Java Random(0).
	# Formula tests fix those inputs; initial-growth randomness is tested separately.
	var sampled_stats: Dictionary = {
		10:
		{
			"strength": 7,
			"skill": 5,
			"speed": 3,
			"defense": 8,
			"magic": 3,
			"luck": 7,
			"maxHp": 27,
			"move": 4
		},
		67:
		{
			"strength": 1,
			"skill": 3,
			"speed": 5,
			"defense": 3,
			"magic": 5,
			"luck": 11,
			"maxHp": 21,
			"move": 4
		}
	}
	for spawn: Dictionary in content["spawns"]:
		if sampled_stats.has(int(spawn["id"])):
			spawn["explicitStats"] = sampled_stats[int(spawn["id"])].duplicate(true)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(limit: int) -> int: return 1 % limit
	)
	var rules: RefCounted = script.new(content["rules"], content["map"]["terrain"])
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_combat.json")
	)
	var units: Dictionary = {}
	for unit: Dictionary in battle.snapshot()["units"]:
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
