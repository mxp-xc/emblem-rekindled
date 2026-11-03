extends SceneTree

const Terrain = preload("res://features/battle/native_terrain_placement.gd")


func _initialize() -> void:
	var stage := {"viewport": {"width": 240}, "stage": {"top": 125, "height": 70}}
	var background := {
		"virtualWidth": 24, "frames": [{"bodyHeight": 24}, {"bodyHeight": 24}, {"bodyHeight": 24}]
	}
	var left: Dictionary = Terrain.calculate({"I": 0}, background, stage)
	var right: Dictionary = Terrain.calculate({"I": 1}, background, stage)
	if (
		left
		!= {
			"x": 48,
			"y": 171,
			"clipWidth": 120,
			"clipHeight": 24,
			"tileCount": 3,
			"tileWidth": 24,
			"offsetX": 0,
			"markedTile": 2
		}
	):
		fail("Native left terrain geometry differs")
		return
	if (
		right
		!= {
			"x": 120,
			"y": 171,
			"clipWidth": 120,
			"clipHeight": 24,
			"tileCount": 3,
			"tileWidth": 24,
			"offsetX": 0,
			"markedTile": 0
		}
	):
		fail("Native right terrain geometry differs")
		return
	background["virtualWidth"] = 32
	background["frames"].append({"bodyHeight": 24})
	var clipped: Dictionary = Terrain.calculate({"I": 1}, background, stage)
	if clipped["tileCount"] != 4 or clipped["offsetX"] != -8 or clipped["clipWidth"] != 120:
		fail("Native right terrain clipping differs")
		return
	print("PASS: native terrain placement and clipping")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
