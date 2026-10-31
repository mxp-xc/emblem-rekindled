extends SceneTree


func _initialize() -> void:
	var path: String = "res://features/battle/reward_timeline.gd"
	if not FileAccess.file_exists(path):
		fail("The source postbattle display clock must be implemented")
		return
	var script: Script = load(path)
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_postbattle.json")
	)
	for sample: Dictionary in oracle["cases"] + oracle["messages"]:
		var before: Dictionary = sample.duplicate(true)
		var model: RefCounted = script.new(sample)
		var changed: Array[int] = []
		for tick: int in range(300):
			model.advance()
			if model.changed_index >= 0:
				changed.append(model.changed_index)
			if model.finished:
				break
		if not model.finished or model.tick != int(sample["sourceUpdates"]):
			fail("Postbattle departure must match original c.d plus drawing: " + str(sample))
			return
		if (
			sample["kind"] == "experience"
			and model.experience != int(sample["before"] + sample["amount"])
		):
			fail("Experience display must reach the committed target across the level boundary")
			return
		if sample["kind"] == "growth":
			var expected: Array = sample["after"].map(
				func(value: Variant) -> int: return int(value)
			)
			if model.values != expected or changed != [0, 6]:
				fail("Growth must reveal the original nonzero attributes in native order")
				return
		if sample != before:
			fail("Presentation timing must never modify committed reward input")
			return
	print(
		"PASS reward timeline: source message/XP/growth departures, level boundary, immutable input"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
