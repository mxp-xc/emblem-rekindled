extends Control

signal accepted(slot: int)
signal back_requested

const PixelTheme = preload("res://ui/pixel_theme.gd")
var slot: int = 0
var page: String = "slots"
var selector_rect: Rect2
var detail_rect: Rect2
var _mode: String
var _records: Array[Dictionary] = []
var _notice: String
var _heading: Label
var _selector: Label
var _details: Label
var _question: Label
var _arrows: Array[Button] = []
var _confirm: Button
var _back: Button
var _frame: StyleBoxTexture


func setup(content: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = content["entry"]["resourceDirectory"]
	var textures: Dictionary = content["interface"]["textures"]
	_frame = StyleBoxTexture.new()
	_frame.texture = load(directory.path_join(textures["window_frame"]["texture"]))
	_frame.set_texture_margin_all(5)
	_frame.draw_center = false
	for field: String in ["heading", "selector", "details", "question"]:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		set("_" + field, label)
	_question.text = "确定覆盖原有存档吗？"
	for direction: int in [-1, 1]:
		var arrow := Button.new()
		arrow.icon = load(
			directory.path_join(
				textures["side_arrow_0" if direction < 0 else "side_arrow_1"]["texture"]
			)
		)
		arrow.icon_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if direction < 0 else HORIZONTAL_ALIGNMENT_RIGHT
		)
		arrow.pressed.connect(change.bind(direction))
		add_child(arrow)
		_arrows.append(arrow)
	_confirm = Button.new()
	_confirm.icon = load(directory.path_join(textures["button_0"]["texture"]))
	_confirm.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_confirm.pressed.connect(_accept)
	add_child(_confirm)
	_back = Button.new()
	_back.icon = load(directory.path_join(textures["button_1"]["texture"]))
	_back.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_back.pressed.connect(go_back)
	add_child(_back)
	for button: Button in _arrows + [_confirm, _back]:
		button.expand_icon = true
		button.focus_mode = Control.FOCUS_NONE
	resized.connect(_layout)
	hide()


func present(mode: String, records: Array[Dictionary]) -> void:
	assert(mode in ["save", "load"] and records.size() == 4)
	_mode = mode
	slot = 0
	refresh(records)
	show()


func refresh(records: Array[Dictionary]) -> void:
	_records = records.duplicate(true)
	page = "slots"
	_notice = ""
	_render()


func show_error(message: String) -> void:
	page = "slots"
	_notice = message
	_render()


func change(direction: int) -> void:
	if page != "slots":
		return
	slot = posmod(slot + direction, 4)
	_notice = ""
	_render()


func go_back() -> void:
	if page == "overwrite":
		page = "slots"
		_render()
	else:
		hide()
		back_requested.emit()


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	match event.keycode:
		KEY_LEFT, KEY_RIGHT:
			change(-1 if event.keycode == KEY_LEFT else 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_accept()
		KEY_UP, KEY_DOWN:
			pass
		_:
			return false
	return true


func handle_wheel(direction: int) -> void:
	change(direction)


func _accept() -> void:
	if page == "overwrite":
		accepted.emit(slot)
	elif _mode == "save" and _records[slot]["status"] != "empty":
		page = "overwrite"
		_render()
	elif _mode == "save" or _records[slot]["status"] != "empty":
		accepted.emit(slot)


func _render() -> void:
	_heading.text = "记录存档" if _mode == "save" else "读取存档"
	_selector.text = "存档 %d/4" % (slot + 1)
	_details.text = _notice
	if _notice.is_empty():
		match _records[slot]["status"]:
			"empty":
				_details.text = "(空)"
			"world":
				_details.text = _records[slot]["description"]
			_:
				_details.text = "存档无法读取，原记录已保留。"
	for control: Control in [_heading, _selector, _details] + _arrows:
		control.visible = page == "slots"
	_question.visible = page == "overwrite"
	_layout()


func _layout() -> void:
	if _heading == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	selector_rect = Rect2(area.position.x, size.y / 2 - 30 * factor, area.size.x, 19 * factor)
	detail_rect = Rect2(
		Vector2(area.position.x, selector_rect.end.y), Vector2(area.size.x, 69 * factor)
	)
	_heading.position = area.position
	_heading.size = Vector2(area.size.x, 28 * factor)
	_selector.position = selector_rect.position
	_selector.size = selector_rect.size
	_details.position = detail_rect.position + Vector2(5, 0) * factor
	_details.size = detail_rect.size - Vector2(10, 0) * factor
	_question.position = Vector2(area.position.x, (size.y - 73 * factor) / 2)
	_question.size = Vector2(area.size.x, 28 * factor)
	for label: Label in [_heading, _selector, _details, _question]:
		label.add_theme_font_size_override("font_size", roundi(12 * factor))
		label.add_theme_color_override("font_color", Color.WHITE)
	_details.add_theme_constant_override("line_spacing", roundi(factor))
	for index: int in range(2):
		var arrow: Button = _arrows[index]
		arrow.position = Vector2(
			area.position.x if index == 0 else area.end.x - 24 * factor, selector_rect.position.y
		)
		arrow.size = Vector2(24, 19) * factor
		arrow.add_theme_constant_override("icon_max_width", roundi(8 * factor))
		for state: String in ["normal", "hover", "pressed", "focus"]:
			arrow.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for button: Button in [_confirm, _back]:
		button.position = Vector2(
			area.position.x if button == _confirm else area.end.x - 24 * factor,
			size.y - 22 * factor
		)
		button.size = Vector2(24, 22) * factor
		button.add_theme_constant_override("icon_max_width", roundi(10 * factor))
		var style := StyleBoxEmpty.new()
		style.content_margin_top = 14 * factor
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
	queue_redraw()


func _draw() -> void:
	if _frame == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var area: Rect2 = PixelTheme.portrait_area(size)
	draw_rect(area, Color("214c87"))
	if page == "overwrite":
		_draw_panel(_question.get_rect(), Color("1c345f"), Color("5c7eb7"))
	else:
		_draw_panel(_heading.get_rect(), Color("022355"), Color("214882"))
		_draw_panel(detail_rect, Color("1c345f"), Color("5c7eb7"))


func _draw_panel(rect: Rect2, top: Color, bottom: Color) -> void:
	var factor: float = PixelTheme.portrait_area(size).size.x / 240.0
	draw_set_transform(rect.position, 0, Vector2.ONE * factor)
	var native_rect := Rect2(Vector2.ZERO, rect.size / factor)
	var inner: Rect2 = native_rect.grow(-5)
	for step: int in range(12):
		var y: float = floorf(inner.size.y * step / 12)
		var height: float = floorf(inner.size.y * (step + 1) / 12) - y
		draw_rect(
			Rect2(inner.position + Vector2(0, y), Vector2(inner.size.x, height)),
			top.lerp(bottom, step / 11.0)
		)
	draw_style_box(_frame, native_rect)
	draw_set_transform(Vector2.ZERO)
