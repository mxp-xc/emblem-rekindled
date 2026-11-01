extends Control

signal confirmed(configuration: Dictionary)

const PixelTheme = preload("res://ui/pixel_theme.gd")

var draft: Dictionary = {}
var _candidates: Array = []
var _labels: Array[Label] = []
var _values: Array[Button] = []
var _arrows: Array[Button] = []
var _heading: Label
var _back: Button
var _background: Texture2D
var _frame: StyleBoxTexture
var _row: int = 0


func setup(data: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = data["entry"]["resourceDirectory"]
	_background = load(
		directory.path_join(data["interface"]["textures"]["content_frame"]["texture"])
	)
	_frame = StyleBoxTexture.new()
	_frame.texture = _background
	_frame.set_texture_margin_all(5)
	_heading = Label.new()
	_heading.text = "指挥官配置"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_heading)
	for index: int in range(3):
		var label := Label.new()
		label.text = ["指挥官", "指令1", "指令2"][index]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
		_labels.append(label)
		var value := Button.new()
		value.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		value.focus_mode = Control.FOCUS_NONE
		value.pressed.connect(func() -> void: change(index, 1))
		add_child(value)
		_values.append(value)
		for direction: int in [-1, 1]:
			var arrow := Button.new()
			arrow.text = "◀" if direction < 0 else "▶"
			arrow.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			arrow.focus_mode = Control.FOCUS_NONE
			arrow.pressed.connect(func() -> void: change(index, direction))
			add_child(arrow)
			_arrows.append(arrow)
	_back = Button.new()
	_back.icon = load(directory.path_join(data["interface"]["textures"]["button_1"]["texture"]))
	_back.expand_icon = true
	_back.add_theme_constant_override("icon_max_width", 30)
	_back.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_back.pressed.connect(commit)
	add_child(_back)
	resized.connect(_layout)
	hide()


func present(configuration: Dictionary) -> void:
	draft = configuration.duplicate(true)
	_row = 0
	_candidates = draft["candidates"]
	_refresh()
	show()
	_layout()


func change(row: int, direction: int) -> void:
	_row = row
	if row == 0:
		var index: int = 0
		for candidate: int in range(_candidates.size()):
			if _candidates[candidate]["id"] == draft["commander"]:
				index = candidate
		index = posmod(index + direction, _candidates.size())
		draft["commander"] = _candidates[index]["id"]
	else:
		draft["policy"] = int(draft["policy"]) ^ (1 if row == 1 else 4)
	_refresh()


func commit() -> void:
	confirmed.emit(draft.duplicate(true))


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if event.keycode in [KEY_UP, KEY_DOWN]:
		handle_wheel(-1 if event.keycode == KEY_UP else 1)
	elif event.keycode in [KEY_LEFT, KEY_RIGHT]:
		change(_row, -1 if event.keycode == KEY_LEFT else 1)
	return (
		event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	)


func handle_wheel(direction: int) -> void:
	_row = posmod(_row + direction, 3)
	_refresh()


func _refresh() -> void:
	for candidate: Dictionary in _candidates:
		if candidate["id"] == draft["commander"]:
			_values[0].text = candidate["name"]
	_values[1].text = "跟随" if int(draft["policy"]) & 1 else "自动"
	_values[2].text = "防御" if int(draft["policy"]) & 4 else "攻击"
	for row: int in range(3):
		_values[row].add_theme_color_override(
			"font_color", Color("fff7bf") if row == _row else Color.WHITE
		)


func _layout() -> void:
	if _heading == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	var header: float = 28 * factor
	var row_height: float = (size.y - header) / 3.0
	_heading.position = area.position + Vector2(0, 4 * factor)
	_heading.size = Vector2(area.size.x, header)
	_heading.add_theme_font_size_override("font_size", roundi(12 * factor))
	for row: int in range(3):
		var y: float = header + row_height * row
		_labels[row].position = area.position + Vector2(0, y)
		_labels[row].size = Vector2(area.size.x / 2, row_height)
		_labels[row].add_theme_font_size_override("font_size", roundi(12 * factor))
		_values[row].position = (
			area.position
			+ Vector2(area.size.x / 2 + 20 * factor, y + (row_height - 19 * factor) / 2)
		)
		_values[row].size = Vector2(area.size.x / 2 - 40 * factor, 19 * factor)
		_values[row].add_theme_font_size_override("font_size", roundi(12 * factor))
		for side: int in range(2):
			var arrow: Button = _arrows[row * 2 + side]
			arrow.position = (
				area.position
				+ Vector2(
					area.size.x / 2 if side == 0 else area.size.x - 20 * factor,
					y + (row_height - 22 * factor) / 2
				)
			)
			arrow.size = Vector2(20 * factor, 22 * factor)
	_back.position = area.end - Vector2(24, 22) * factor
	_back.size = Vector2(24, 22) * factor
	queue_redraw()


func _draw() -> void:
	if _background == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	draw_style_box(_frame, area)
	draw_rect(
		Rect2(area.position + Vector2(4, 4), Vector2(area.size.x - 8, 28 * factor)), Color("213482")
	)
