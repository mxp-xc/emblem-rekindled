extends Control

const PixelTheme = preload("res://ui/pixel_theme.gd")
var independent: bool = false
var hp: Dictionary = {}
var shake := Vector2.ZERO
var _units: Array = []
var _forecasts: Dictionary = {}
var _interface: Dictionary
var _metadata: Dictionary
var _textures: Dictionary = {}


func setup(content: Dictionary) -> void:
	_interface = content["interface"]
	_metadata = _interface["battleHud"]
	var directory: String = content["entry"]["interface"].get_base_dir()
	for key: String in _interface["textures"]:
		_textures[key] = load(directory.path_join(_interface["textures"][key]["texture"]))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func present(preview: Dictionary, battle_mode: bool) -> void:
	_units = preview["participants"].duplicate()
	if _units[0]["faction"] == 2:
		_units.reverse()
	_forecasts = preview["forecasts"]
	independent = battle_mode
	hp.clear()
	for actor: Dictionary in _units:
		hp[int(actor["id"])] = int(actor["hp"])
	shake = Vector2.ZERO
	queue_redraw()


func set_display(state: Dictionary) -> void:
	hp = state["hp"]
	shake = Vector2(state["backgroundOffset"][0], state["backgroundOffset"][1])
	queue_redraw()


func _draw() -> void:
	if _units.is_empty():
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	var reference: Dictionary = (
		_metadata["nativeReferenceLayout"]
		if independent
		else _metadata["forecast"]["nativeReferenceLayout"]
	)
	var origin := Vector2(area.position.x, (size.y - 320 * factor) / 2 if independent else 0)
	for side: int in range(2):
		var actor: Dictionary = _units[side]
		var position: Array = reference["topRect" if side == 0 else "bottomRect"]
		var rect := Rect2(Vector2(position[0], position[1]), Vector2(position[2], position[3]))
		if not independent and side == 1:
			rect.position.y = size.y / factor - rect.size.y
		var style: String = (
			("battle_hud_" if independent else "forecast_hud_") + ("top" if side == 0 else "bottom")
		)
		draw_texture_rect(
			_textures[style], Rect2(origin + rect.position * factor, rect.size * factor), false
		)
		var prediction_y: float
		if independent:
			prediction_y = float(_metadata["predictionRow"]["topY" if side == 0 else "bottomY"])
		else:
			prediction_y = 0 if side == 0 else rect.position.y + 5
		var forecast: Dictionary = _forecasts[str(int(actor["id"]))]
		for column: Dictionary in _metadata["forecastColumns"]:
			var start := Vector2(column["nativeX"], prediction_y) + shake
			_draw_icon(column["icon"], origin + start * factor, factor)
			var field: String = "damage" if column["id"] == "attack" else column["id"]
			var value: String = str(int(forecast[field])) if forecast["canAttack"] else "--"
			_draw_number(value, origin + (start + Vector2(26, 6)) * factor, factor, true)
		var current: int = int(hp[int(actor["id"])])
		if independent:
			var point: Array = _metadata["currentHp"][
				"textOriginTop" if side == 0 else "textOriginBottom"
			]
			_draw_number(
				str(current), origin + (Vector2(point[0], point[1]) + shake) * factor, factor, true
			)
			_draw_segments(side, current, int(actor["maxHp"]), origin, factor)
		else:
			_draw_forecast_details(actor, forecast, current, prediction_y, origin, factor)
			_draw_corners(side, Rect2(origin + rect.position * factor, rect.size * factor), factor)


func _draw_forecast_details(
	actor: Dictionary, forecast: Dictionary, current: int, y: float, origin: Vector2, factor: float
) -> void:
	var row: float = y + 13
	var weapon: int = int(forecast["weapon"])
	if weapon > 0:
		var icon: Variant = _interface["items"][str(weapon)]["icon"]
		if icon != null:
			var texture: Texture2D = _textures[icon]
			_draw_icon(icon, origin + Vector2(26 - texture.get_width(), row) * factor, factor)
	if forecast["canAttack"]:
		var advantage: int = int(forecast["advantage"])
		if advantage != 0:
			var arrow: String = _metadata["forecast"][
				"advantageUp" if advantage > 0 else "advantageDown"
			]
			var texture: Texture2D = _textures[arrow]
			_draw_icon(arrow, origin + Vector2(13 - texture.get_width(), row) * factor, factor)
		if forecast["double"]:
			_draw_number("*2", origin + Vector2(26, row) * factor, factor, false)
	var bar := Rect2(origin + Vector2(80, row + 2) * factor, Vector2(80, 6) * factor)
	var empty: Texture2D = _textures["map_hud_hp_empty"]
	var full: Texture2D = _textures["map_hud_hp_full"]
	draw_texture_rect(empty, bar, false)
	var ratio: float = float(current) / actor["maxHp"]
	if ratio > 0:
		draw_texture_rect_region(
			full,
			Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
			Rect2(0, 0, full.get_width() * ratio, full.get_height())
		)
	_draw_number(
		"%d/%d" % [current, actor["maxHp"]], origin + Vector2(160, row) * factor, factor, false
	)


func _draw_segments(side: int, current: int, maximum: int, origin: Vector2, factor: float) -> void:
	var definition: Dictionary = _metadata["segmentedHpBar"]
	var point: Array = definition["topOrigin" if side == 0 else "bottomOrigin"]
	var start := Vector2(point[0], point[1]) + shake
	for state: Array in [
		[maximum, definition["emptyTexture"]], [current, definition["fullTexture"]]
	]:
		var pixels: int = int(state[0]) * int(definition["pixelsPerHp"])
		var width: int = int(definition["segmentWidth"])
		var height: int = int(definition["segmentHeight"])
		var index: int = 0
		while pixels > 0:
			var count: int = mini(width, pixels)
			var column: int = index if index < 2 else index - 2
			var row: int = 0 if index < 2 else 1
			var cut: int = int(definition["firstSegmentClipLeftPixels"]) if column == 0 else 0
			if count > cut:
				var position: Vector2 = (
					origin + (start + Vector2(column * width + cut, row * (height + 2))) * factor
				)
				draw_texture_rect_region(
					_textures[state[1]],
					Rect2(position, Vector2(count - cut, height) * factor),
					Rect2(cut, 0, count - cut, height)
				)
			pixels -= count
			index += 1


func _draw_corners(side: int, panel: Rect2, factor: float) -> void:
	var left_key: String = "corner_2" if side == 0 else "corner_0"
	var right_key: String = "corner_3" if side == 0 else "corner_1"
	var left: Texture2D = _textures[left_key]
	var right: Texture2D = _textures[right_key]
	var y: float = panel.end.y if side == 0 else panel.position.y - left.get_height() * factor
	_draw_icon(left_key, Vector2(panel.position.x, y), factor)
	_draw_icon(right_key, Vector2(panel.end.x - right.get_width() * factor, y), factor)


func _draw_icon(key: String, position: Vector2, factor: float) -> void:
	var texture: Texture2D = _textures[key]
	var offsets: Array = _interface["textures"][key].get("originalOffset", [0, 0])
	draw_texture_rect(
		texture,
		Rect2(position + Vector2(offsets[0], offsets[1]) * factor, texture.get_size() * factor),
		false
	)


func _draw_number(value: String, position: Vector2, factor: float, centered: bool) -> void:
	var font: Dictionary = _metadata["numberFont"]
	var start: Vector2 = position
	if centered:
		start.y -= floorf(float(font["height"]) / 2) * factor
	for character: String in value:
		_draw_icon(font["glyphs"][character], start, factor)
		start.x += int(font["advance"]) * factor
