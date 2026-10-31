extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var rules: RefCounted = load("res://gameplay/combat_rules.gd").new(
		content["rules"], content["map"]["terrain"]
	)
	var fixture: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_rewards.json")
	)
	for sample: Dictionary in fixture["powers"]:
		if rules.power(sample["unit"]) != sample["power"]:
			fail(
				(
					"Power mismatch for original unit %s: %s != %s"
					% [sample["unit"]["id"], rules.power(sample["unit"]), sample["power"]]
				)
			)
			return
	if not rules.has_method("experience_gain"):
		fail("Experience calculation is missing")
		return
	for sample: Dictionary in fixture["experienceCases"]:
		var actual: int = rules.experience_gain(
			sample["actor"], sample["target"], sample["killed"], sample["hit"], sample["borrowed"]
		)
		if actual != sample["experience"]:
			fail("Original experience mismatch: %s != %s" % [actual, sample["experience"]])
			return
	print("PASS rewards: original power for 32 units and eleven experience branches")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
