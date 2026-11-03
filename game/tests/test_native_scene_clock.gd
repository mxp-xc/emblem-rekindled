extends SceneTree

const Motion = preload("res://features/battle/native_motion_clock.gd")
const SceneClock = preload("res://features/battle/native_scene_clock.gd")
const NativeRandom = preload("res://features/battle/native_random.gd")


func _initialize() -> void:
	var cases: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_scene_clock.json")
	)
	for name: String in cases:
		var sample: Dictionary = cases[name]
		if not SceneClock.supports(sample["action"], "miss"):
			fail("Unsupported native scene: " + name)
			return
		var motion: RefCounted = Motion.new(sample["action"], "miss", sample["defender"])
		var scene: RefCounted = SceneClock.new(sample["action"], NativeRandom.new(0))
		for index: int in range(sample["offsets"].size()):
			motion.advance()
			scene.advance(motion, index)
			var expected: Array = sample["offsets"][index]
			if scene.offset != Vector2i(int(expected[0]), int(expected[1])):
				fail("Native screen shake differs %s tick %d" % [name, index])
				return
	print("PASS: native screen shake and random ordering")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
