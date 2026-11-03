extends SceneTree

const Clock = preload("res://features/battle/native_motion_clock.gd")
const DefenderMotion = preload("res://features/battle/native_defender_motion.gd")


func _initialize() -> void:
	var cases: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_motion_clock.json")
	)
	for name: String in cases:
		var sample: Dictionary = cases[name]
		if not Clock.supports(sample["action"]):
			fail("Native motion should be supported: " + name)
			return
		var clock: RefCounted = Clock.new(sample["action"], sample["outcome"], sample["defender"])
		var defense: RefCounted = null
		if sample["outcome"] == "miss":
			defense = DefenderMotion.new(sample["defender"])
		for index: int in range(sample["expected"].size()):
			clock.advance()
			if defense != null:
				defense.advance(clock)
			if (
				clock.impact_started != (index == int(sample["impactTick"]))
				or clock.settled != (index == int(sample["settleTick"]))
			):
				fail("Native hit or settlement timing mismatch %s tick %d" % [name, index])
				return
			var expected: Array = sample["expected"][index]
			if (
				clock.state != int(expected[0])
				or clock.step != int(expected[1])
				or clock.frame != int(expected[2])
				or not clock.position_supported
				or clock.position != Vector2i(int(expected[3]), int(expected[4]))
			):
				fail("Native motion mismatch %s tick %d" % [name, index])
				return
			if defense != null:
				if (
					defense.frame != int(expected[5])
					or defense.position != Vector2i(int(expected[6]), int(expected[7]))
				):
					fail("Native dodge mismatch %s tick %d" % [name, index])
					return
	if Clock.supports({"R": 3, "effectKind": 2}):
		fail("Unimplemented motion must not be advertised as supported")
		return
	print("PASS: native motion state and sprite sequence")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
