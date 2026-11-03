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
	for sample: Dictionary in oracle["messages"]:
		var before: Dictionary = sample.duplicate(true)
		var model: RefCounted = script.new(sample)
		for tick: int in range(300):
			model.advance()
			if model.finished:
				break
		if not model.finished or model.tick != int(sample["sourceUpdates"]):
			fail("Timed item messages must retain original departure: " + str(sample))
			return
		if sample != before:
			fail("Presentation timing must never modify committed reward input")
			return
	print("PASS reward timeline: source message departures and immutable input")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
