extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")


class RecordingHud:
	extends "res://features/battle/combat_hud.gd"
	var icons: Array[Dictionary] = []
	var bars: Array[Rect2] = []

	func _draw() -> void:
		icons.clear()
		bars.clear()
		super._draw()

	func _draw_icon(key: String, position: Vector2, factor: float) -> void:
		var texture: Texture2D = _textures[key]
		var offset: Array = _interface["textures"][key].get("originalOffset", [0, 0])
		icons.append(
			{
				"key": key,
				"rect":
				Rect2(
					position + Vector2(offset[0], offset[1]) * factor, texture.get_size() * factor
				)
			}
		)
		super._draw_icon(key, position, factor)

	func _draw_segments(
		side: int, current: int, maximum: int, origin: Vector2, factor: float
	) -> void:
		var point: Array = _metadata["segmentedHpBar"]["topOrigin" if side == 0 else "bottomOrigin"]
		# The largest legal bar occupies no more than 118 native pixels from its origin.
		bars.append(
			Rect2(
				origin + (Vector2(point[0], point[1]) + shake) * factor, Vector2(118, 14) * factor
			)
		)
		super._draw_segments(side, current, maximum, origin, factor)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var opened: Dictionary = Session.new().open("res://content/chapter_1/chapter.json")
	if not opened["ok"]:
		fail("Actual chapter content must open for HUD geometry")
		return
	var hud := RecordingHud.new()
	root.add_child(hud)
	hud.setup(opened["content"])
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var preview: Dictionary = {
		"participants":
		[
			{"id": 0, "faction": 0, "hp": 58, "maxHp": 99},
			{"id": 80, "faction": 2, "hp": 0, "maxHp": 99}
		],
		"forecasts":
		{
			"0":
			{
				"damage": 40,
				"hit": 100,
				"critical": 99,
				"canAttack": true,
				"weapon": 0,
				"advantage": 0,
				"double": false
			},
			"80":
			{
				"damage": 40,
				"hit": 100,
				"critical": 99,
				"canAttack": true,
				"weapon": 0,
				"advantage": 0,
				"double": false
			}
		}
	}
	for dimensions: Vector2i in [Vector2i(540, 960), Vector2i(960, 540)]:
		root.size = dimensions
		hud.size = dimensions
		await process_frame
		for offset: int in [-9, 0, 9]:
			for pair: Array in [[58, 0], [0, 58], [99, 99]]:
				hud.present(preview, true)
				hud.set_display({"hp": {0: pair[0], 80: pair[1]}, "backgroundOffset": [offset, 0]})
				await process_frame
				await process_frame
				var area: Rect2 = PixelTheme.portrait_area(hud.size)
				if hud.icons.is_empty() or hud.bars.size() != 2:
					fail("Both independent panels must draw their text, icons and HP bars")
					return
				var expected_keys: Array[String] = []
				for current: int in pair:
					expected_keys.append_array(
						[
							"attribute_8",
							"number_4",
							"number_0",
							"attribute_10",
							"number_1",
							"number_0",
							"number_0",
							"attribute_9",
							"number_9",
							"number_9"
						]
					)
					for digit: String in str(current):
						expected_keys.append("number_" + digit)
				var actual_keys: Array[String] = []
				for item: Dictionary in hud.icons:
					actual_keys.append(item["key"])
				if actual_keys != expected_keys:
					fail("Both panels must draw every forecast and current HP digit")
					return
				var first_icon: Rect2 = hud.icons[0]["rect"]
				var expected_x: float = area.position.x + (9 + offset) * area.size.x / 240.0
				if not is_equal_approx(first_icon.position.x, expected_x):
					fail("The inset must retain the full native horizontal shake")
					return
				for item: Dictionary in hud.icons:
					var rect: Rect2 = item["rect"]
					if rect.position.x < area.position.x - 0.01 or rect.end.x > area.end.x + 0.01:
						fail("Clipped HUD glyph: %s %s %s" % [dimensions, offset, item])
						return
				for bar: Rect2 in hud.bars:
					if bar.position.x < area.position.x - 0.01 or bar.end.x > area.end.x + 0.01:
						fail("Both 99 HP segmented bars must remain inside the portrait area")
						return
		hud.present(preview, false)
		await process_frame
		await process_frame
		var first: Dictionary = hud.icons[0]
		var forecast_area: Rect2 = PixelTheme.portrait_area(hud.size)
		if (
			first["key"] != "attribute_8"
			or not is_equal_approx(first["rect"].position.x, forecast_area.position.x)
		):
			fail("Forecast HUD must retain its original horizontal layout")
			return
	hud.queue_free()
	print("PASS combat HUD: shake, labels, HP and bars in both orientations")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
