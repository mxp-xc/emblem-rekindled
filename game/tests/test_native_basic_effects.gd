extends SceneTree

const Clock = preload("res://features/battle/native_motion_clock.gd")
const Effects = preload("res://features/battle/native_basic_effects.gd")


func _initialize() -> void:
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_basic_effects.json")
	)
	for name: String in oracle["cases"]:
		var sample: Dictionary = oracle["cases"][name]
		var clock: RefCounted = Clock.new(sample["action"], sample["outcome"], sample["defender"])
		var effects: RefCounted = Effects.new(
			sample["action"],
			sample["defender"],
			sample["outcome"],
			oracle["effects"],
			sample.get("projectile", {})
		)
		for tick: int in range(sample["expected"].size()):
			clock.advance()
			effects.advance(clock)
			var expected: Array = sample["expected"][tick]
			if effects.layers.size() != expected.size():
				fail("Effect count differs %s tick %d" % [name, tick])
				return
			for index: int in range(expected.size()):
				var actual: Dictionary = effects.layers[index]
				var row: Array = expected[index]
				if (
					not same_raster(actual, row)
					or int(actual["instance"]) != int(row[3])
					or actual["foreground"] != row[4]
				):
					fail("Effect differs %s tick %d layer %d" % [name, tick, index])
					return
	print("PASS: native melee effects and tails")
	quit(0)


func same_raster(actual: Dictionary, expected: Array) -> bool:
	var expected_position := Vector2i(int(expected[1]), int(expected[2]))
	if (
		actual["texture"] is String
		and actual["texture"] == expected[0]
		and actual["position"] == expected_position
	):
		return true
	var image: Image = (
		actual["texture"].get_image()
		if actual["texture"] is Texture2D
		else Image.load_from_file(ProjectSettings.globalize_path(actual["texture"]))
	)
	var oracle: Image = Image.load_from_file(ProjectSettings.globalize_path(expected[0]))
	if image == null or oracle == null:
		return false
	var clipped: Rect2i = Rect2i(actual["position"], image.get_size()).intersection(
		Rect2i(0, 0, 240, 320)
	)
	if not clipped.has_area():
		return false
	var region: Image = image.get_region(
		Rect2i(clipped.position - actual["position"], clipped.size)
	)
	var used: Rect2i = region.get_used_rect()
	if clipped.position + used.position != expected_position:
		return false
	region = region.get_region(used)
	region.convert(Image.FORMAT_RGBA8)
	oracle.convert(Image.FORMAT_RGBA8)
	return region.get_size() == oracle.get_size() and region.get_data() == oracle.get_data()


func fail(message: String) -> void:
	push_error(message)
	quit(1)
