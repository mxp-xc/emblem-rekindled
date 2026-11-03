extends SceneTree

const CriticalSky = preload("res://features/battle/native_critical_sky.gd")


func _initialize() -> void:
	for index: int in range(3):
		var expected := Image.load_from_file(
			ProjectSettings.globalize_path("res://tests/fixtures/critical_sky_%d.png" % index)
		)
		var actual := Image.create(240, 70, false, Image.FORMAT_RGBA8)
		for rect: Array in CriticalSky.rectangles(240, 70, 11 - index * 2, Vector2i.ZERO):
			actual.fill_rect(
				Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])),
				Color.hex((int(rect[4]) << 8) | 255)
			)
		expected.convert(Image.FORMAT_RGBA8)
		if actual.get_data() != expected.get_data():
			push_error("Critical sky differs from original at phase %d" % index)
			quit(1)
			return
	print("PASS: original critical wind-up sky pixels")
	quit(0)
