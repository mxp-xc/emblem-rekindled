extends SceneTree

const Motion = preload("res://features/battle/native_motion_clock.gd")
const SceneClock = preload("res://features/battle/native_scene_clock.gd")
const NativeRandom = preload("res://features/battle/native_random.gd")
const Defender = preload("res://features/battle/native_defender_motion.gd")


func _initialize() -> void:
	var cases: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_hit_scene.json")
	)
	for name: String in cases:
		var sample: Dictionary = cases[name]
		var motion: RefCounted = Motion.new(sample["action"], "hit", sample["defender"])
		var scene: RefCounted = SceneClock.new(
			sample["action"], NativeRandom.new(0), int(sample.get("slot", 0))
		)
		var defense: RefCounted = Defender.new(sample["defender"])
		for index: int in range(sample["expected"].size()):
			motion.advance()
			defense.advance(motion)
			scene.advance(motion, index)
			defense.draw_jitter(scene)
			var row: Array = sample["expected"][index]
			if (
				scene.offset != Vector2i(int(row[0]), int(row[1]))
				or defense.frame != int(row[2])
				or defense.position != Vector2i(int(row[3]), int(row[4]))
			):
				push_error("Native hit scene differs %s tick %d" % [name, index])
				quit(1)
				return
			if row.size() > 5:
				var expected_color: Variant = null if int(row[5]) == -1 else int(row[5])
				if scene.sky_color != expected_color:
					push_error("Native light flash differs %s tick %d" % [name, index])
					quit(1)
					return
	print("PASS: native hit shake and defender jitter")
	quit(0)
