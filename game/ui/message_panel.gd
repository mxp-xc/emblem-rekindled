extends Control

signal completed

const PixelTheme = preload("res://ui/pixel_theme.gd")
const FONT = preload("res://ui/fonts/NotoSansCJKsc-Regular.woff2")
var native_font_size: int = 13
var full_text: String = ""
var line_index: int = 0
var reading: bool = false
var notice_mode: bool = false
var panel_rect: Rect2
var portrait: TextureRect
var speaker_label: Label
var heading_label: Label
var _clip: Control
var _text: Label
var _lines: PackedStringArray
var _scroll: int = 0
var _tone: String = "ally"
var _frame: Texture2D
var _remaining_units: int = -1
var _portrait_right: bool = false
var _content_area: Rect2
var _factor: float = 1.0
var _native_width: int = 240


func setup(content: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = content["entry"]["resourceDirectory"]
	_frame = load(directory.path_join(content["interface"]["textures"]["window_frame"]["texture"]))
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_text = Label.new()
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("font", FONT)
	_clip.add_child(_text)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	speaker_label = Label.new()
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(speaker_label)
	heading_label = Label.new()
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(heading_label)
	resized.connect(_layout)
	hide()


func present(
	text: String,
	face: Texture2D = null,
	speaker: String = "",
	tone: String = "ally",
	portrait_right: bool = false
) -> void:
	full_text = text
	notice_mode = false
	heading_label.hide()
	_tone = tone
	_portrait_right = portrait_right
	line_index = 0
	_scroll = 0
	reading = true
	portrait.texture = face
	portrait.visible = face != null
	speaker_label.text = speaker
	speaker_label.visible = face == null and not speaker.is_empty()
	_reflow()
	show()
	_layout()


func present_notice(text: String, heading: String = "", duration_units: int = -1) -> void:
	full_text = text
	notice_mode = true
	_portrait_right = false
	_tone = "notice"
	heading_label.text = heading
	heading_label.visible = not heading.is_empty()
	_remaining_units = duration_units
	reading = duration_units < 0
	line_index = 0
	_scroll = 0
	portrait.hide()
	speaker_label.hide()
	show()
	_layout()


func advance() -> void:
	if not reading or _scroll > 0:
		return
	if notice_mode:
		reading = false
		completed.emit()
		return
	if line_index + 2 < _lines.size():
		line_index += 1
		_scroll = 19
		_layout()
	else:
		reading = false
		completed.emit()


func tick() -> void:
	if notice_mode and _remaining_units >= 0:
		if _remaining_units > 0:
			_remaining_units -= 50
		else:
			_remaining_units = -1
			reading = false
			completed.emit()
		return
	if _scroll > 0:
		_scroll = maxi(0, _scroll - 7)
		_layout()


func set_content_area(area: Rect2) -> void:
	_content_area = area
	_layout()


func _reflow() -> void:
	var area: Rect2 = _content_area if _content_area.has_area() else PixelTheme.portrait_area(size)
	_factor = minf(area.size.x / 240.0, area.size.y / 320.0)
	_native_width = floori(area.size.x / _factor)
	var width: int = _native_width - (57 if portrait.visible else 2) - (0 if _portrait_right else 2)
	_lines = PixelTheme.wrap_text(full_text, width, native_font_size)
	_text.text = "\n".join(_lines)
	line_index = mini(line_index, maxi(0, _lines.size() - 2))
	panel_rect = Rect2(area.position.x, area.end.y - 48 * _factor, area.size.x, 48 * _factor)
	if notice_mode:
		var rows: int = _lines.size() + (1 if heading_label.visible else 0)
		var height: int = 28 if rows == 1 else 10 + rows * 19
		panel_rect.size.y = height * _factor
		panel_rect.position.y = area.position.y + (area.size.y - panel_rect.size.y) / 2


func _layout() -> void:
	if _text == null or _frame == null:
		return
	_reflow()
	var factor: float = _factor
	var offset: int = 57 if portrait.visible and not _portrait_right else 2
	var top: int = 24 if notice_mode and heading_label.visible else 5
	_clip.position = panel_rect.position + Vector2(offset, top) * factor
	_clip.size = (
		Vector2(
			(
				_native_width - 57
				if portrait.visible and _portrait_right
				else _native_width - offset - 2
			),
			_lines.size() * 19 if notice_mode else 38
		)
		* factor
	)
	_text.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER if notice_mode else HORIZONTAL_ALIGNMENT_LEFT
	)
	_text.size.x = _clip.size.x
	_text.position = Vector2(0, -line_index * 19 + _scroll) * factor
	var font_size: int = roundi(native_font_size * factor)
	_text.add_theme_font_size_override("font_size", font_size)
	_text.add_theme_constant_override(
		"line_spacing", roundi(19 * factor - FONT.get_height(font_size))
	)
	_text.add_theme_color_override(
		"font_color", Color("36302d") if _tone == "narration" else Color.WHITE
	)
	portrait.position = panel_rect.position - Vector2(0, 7 * factor)
	if _portrait_right:
		portrait.position.x += (_native_width - 55) * factor
	portrait.size = Vector2(55, 55) * factor
	speaker_label.position = panel_rect.position - Vector2(0, 19 * factor)
	speaker_label.add_theme_font_size_override("font_size", roundi(13 * factor))
	heading_label.position = panel_rect.position + Vector2(0, 5) * factor
	heading_label.size = Vector2(panel_rect.size.x, 19 * factor)
	heading_label.add_theme_font_size_override("font_size", font_size)
	queue_redraw()


func _draw() -> void:
	if _frame == null:
		return
	var factor: float = _factor
	var fill: Color = Color("5c7eb7")
	var gradient: Color = Color("1c345f")
	if _tone == "enemy":
		fill = Color("aa403f")
		gradient = Color("400600")
	elif _tone == "narration":
		fill = Color("b2967e")
		gradient = Color("6e4d46")
	elif _tone == "notice":
		fill = Color("214882")
		gradient = Color("022355")
	draw_rect(panel_rect, fill)
	var rows: int = mini(12, floori(panel_rect.size.y / factor / 4))
	for row: int in range(rows):
		draw_rect(
			Rect2(
				panel_rect.position + Vector2(0, 5 + row) * factor,
				Vector2(panel_rect.size.x, factor)
			),
			gradient.lerp(fill, float(row) / rows)
		)
	draw_texture_rect_region(
		_frame,
		Rect2(panel_rect.position, Vector2(panel_rect.size.x, 5 * factor)),
		Rect2(5, 0, 22, 5)
	)
	if notice_mode:
		draw_texture_rect_region(
			_frame,
			Rect2(
				panel_rect.position.x, panel_rect.end.y - 5 * factor, panel_rect.size.x, 5 * factor
			),
			Rect2(5, 27, 22, 5)
		)
	if speaker_label.visible:
		var width: float = (
			FONT.get_string_size(speaker_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 2
		)
		draw_rect(Rect2(speaker_label.position, Vector2(width, 19) * factor), Color("3b5d17"))
