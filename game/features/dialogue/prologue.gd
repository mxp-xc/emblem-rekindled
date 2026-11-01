extends Control

signal completed

const PixelTheme = preload("res://ui/pixel_theme.gd")
const FONT = preload("res://ui/fonts/NotoSansCJKsc-Regular.otf")
var _images: Dictionary = {}
var _lines: PackedStringArray
var _scroll_y: int
var _first_line: int = 0
var _fade: int = 0
var _ending: bool = false
var _finished: bool = false
var _scene_x: int = 0
var _scene_scroll: int = 0


func setup(content: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = content["entry"]["resourceDirectory"]
	for key: String in ["intro0", "scene0", "scene1", "scene2"]:
		_images[key] = load(directory.path_join(content["story"]["images"][key]["texture"]))
	_lines = PixelTheme.wrap_text(content["story"]["sequences"]["boot"][0]["text"]["text"], 240, 13)
	_scroll_y = floori(size.y / (PixelTheme.portrait_area(size).size.x / 240)) - 19
	resized.connect(queue_redraw)
	show()


func skip() -> void:
	if not _ending:
		_ending = true
		_fade = 6


func tick() -> void:
	if _finished:
		return
	if _scene_x < 138:
		_scene_x += 1
		_scene_scroll = (_scene_scroll + 1) % 80
	if _ending:
		_fade -= 1
		if _fade < 0:
			_finished = true
			completed.emit()
	elif _fade < 6:
		_fade += 1
	else:
		_scroll_y -= 1
		if _scroll_y < 70:
			_scroll_y += 19
			_first_line += 1
		if _first_line >= _lines.size():
			skip()
	queue_redraw()


func _draw() -> void:
	if _images.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	var height: float = size.y / factor
	draw_rect(Rect2(area.position, Vector2(240, 70) * factor), Color("a91a27"))
	draw_rect(Rect2(area.position, Vector2(240, 35) * factor), Color("ce3143"))
	for x: int in range(-_scene_scroll, 240, 81):
		_art("scene0", Vector2(x, 0), area.position, factor)
	for x: int in range(_scene_scroll - 81, 240, 81):
		_art("scene2", Vector2(x, 51), area.position, factor)
	_art("scene1", Vector2(_scene_x - 138, 0), area.position, factor)
	_art("intro0", Vector2(63, 0), area.position, factor)
	# The original fades the top picture in first, then fades the full screen out.
	var darkness: float = 1.0 - clampf(float(_fade) / 6, 0, 1)
	draw_rect(
		Rect2(area.position, Vector2(240, height if _ending else 70) * factor),
		Color(0, 0, 0, darkness)
	)
	var y: int = _scroll_y
	var font_size: int = roundi(13 * factor)
	for index: int in range(_first_line, _lines.size()):
		if y >= height - 19:
			break
		var opacity: float = clampf(minf(y - 70, height - 19 - y) / 19.0, 0, 1)
		if _ending:
			opacity *= clampf(float(_fade) / 6, 0, 1)
		draw_string(
			FONT,
			area.position + Vector2(0, y + 3) * factor + Vector2(0, FONT.get_ascent(font_size)),
			_lines[index],
			HORIZONTAL_ALIGNMENT_CENTER,
			area.size.x,
			font_size,
			Color(opacity, opacity, opacity)
		)
		y += 19
	# Moving scene layers are clipped to the original 240px picture width.
	if area.position.x > 0:
		draw_rect(Rect2(0, 0, area.position.x, size.y), Color.BLACK)
		draw_rect(Rect2(area.end.x, 0, area.position.x, size.y), Color.BLACK)


func _art(key: String, position: Vector2, origin: Vector2, factor: float) -> void:
	var texture: Texture2D = _images[key]
	draw_texture_rect(
		texture, Rect2(origin + position * factor, texture.get_size() * factor), false
	)
