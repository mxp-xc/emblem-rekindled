extends Control

signal new_game
signal load_game
signal continue_game
signal settings_requested
signal help_requested
signal interacted

const PixelTheme = preload("res://ui/pixel_theme.gd")
const Prologue = preload("res://features/dialogue/prologue.gd")
var prologue: Control
var splash: Texture2D
var options: Control
var load_button: Button
var message: Label
var _buttons: Array[Button] = []
var _arrows: Array[Button] = []
var _logos: Array[Texture2D] = []
var _selected: int = 0
var _ticks: int = 0
var _elapsed: float = 0
var _tick_seconds: float
var _has_temporary_progress: bool = false


func setup(data: Dictionary, has_temporary_progress: bool) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tick_seconds = float(data["battleClips"]["tickMillis"]) / 1000
	var directory: String = data["entry"]["story"].get_base_dir()
	splash = load(directory.path_join(data["story"]["images"]["splash"]["texture"]))
	for key: String in ["title_00", "title_01"]:
		_logos.append(load(directory.path_join(data["story"]["images"][key]["texture"])))
	options = Control.new()
	options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(options)
	for label: String in ["开始游戏", "读取进度", "读取存档", "游戏设置", "游戏帮助"]:
		var button := Button.new()
		button.text = label
		button.focus_mode = Control.FOCUS_NONE
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(_activate)
		options.add_child(button)
		_buttons.append(button)
	load_button = _buttons[2]
	for direction: int in [-1, 1]:
		var arrow := Button.new()
		var key: String = "side_arrow_0" if direction < 0 else "side_arrow_1"
		arrow.icon = load(
			data["entry"]["interface"].get_base_dir().path_join(
				data["interface"]["textures"][key]["texture"]
			)
		)
		arrow.expand_icon = true
		arrow.focus_mode = Control.FOCUS_NONE
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			arrow.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		arrow.pressed.connect(_change.bind(direction))
		options.add_child(arrow)
		_arrows.append(arrow)
	message = Label.new()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(message)
	prologue = Prologue.new()
	add_child(prologue)
	prologue.setup(data)
	prologue.completed.connect(prologue.hide)
	visibility_changed.connect(
		func() -> void:
			if not visible:
				prologue.hide()
	)
	gui_input.connect(_handle_touch)
	resized.connect(_layout)
	refresh_continue(has_temporary_progress)
	_layout()


func refresh_continue(has_temporary_progress: bool) -> void:
	_has_temporary_progress = has_temporary_progress
	_selected = 1 if _has_temporary_progress else 0
	_buttons[1].disabled = not _has_temporary_progress
	options.hide()
	message.text = "点击或按键开始"
	_refresh()


func _change(direction: int) -> void:
	_selected = posmod(_selected + direction, _buttons.size())
	_refresh()
	interacted.emit()


func _refresh() -> void:
	for index: int in range(_buttons.size()):
		_buttons[index].visible = index == _selected
	message.visible = not options.visible
	if not options.visible:
		message.text = "点击或按键开始"
	_layout()


func _activate() -> void:
	interacted.emit()
	if _buttons[_selected].disabled:
		return
	match _selected:
		0:
			new_game.emit()
		1:
			continue_game.emit()
		2:
			load_game.emit()
		3:
			settings_requested.emit()
		4:
			help_requested.emit()


func go_back() -> void:
	if not prologue.visible:
		if not options.visible:
			_selected = 1 if _has_temporary_progress else 0
		options.visible = not options.visible
		_refresh()


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if prologue.visible:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			prologue.skip()
			interacted.emit()
	elif not options.visible:
		_selected = 1 if _has_temporary_progress else 0
		options.show()
		_refresh()
		interacted.emit()
	elif event.keycode in [KEY_LEFT, KEY_RIGHT]:
		_change(-1 if event.keycode == KEY_LEFT else 1)
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_activate()
	return true


func _handle_touch(event: InputEvent) -> void:
	if (
		(event is InputEventScreenTouch and not event.pressed and not event.canceled)
		or (
			event is InputEventMouseButton
			and not event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		)
	):
		if prologue.visible:
			prologue.skip()
			interacted.emit()
		elif not options.visible:
			_selected = 1 if _has_temporary_progress else 0
			options.show()
			_refresh()
			interacted.emit()


func tick() -> void:
	_ticks += 1
	if prologue.visible:
		prologue.tick()
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		_elapsed = 0
		return
	_elapsed += delta
	while _elapsed >= _tick_seconds:
		_elapsed -= _tick_seconds
		tick()


func _layout() -> void:
	if options == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	options.size = Vector2(120, 19) * factor
	options.position = Vector2(area.get_center().x - 60 * factor, size.y / 2 + 65 * factor)
	for button: Button in _buttons:
		button.position = Vector2(20, 0) * factor
		button.size = Vector2(80, 19) * factor
		button.add_theme_font_size_override("font_size", roundi(12 * factor))
	for index: int in range(_arrows.size()):
		_arrows[index].position = Vector2(index * 100, 0) * factor
		_arrows[index].size = Vector2(20, 19) * factor
		_arrows[index].add_theme_font_size_override("font_size", roundi(12 * factor))
		_arrows[index].add_theme_constant_override("icon_max_width", roundi(8 * factor))
	message.position = Vector2(
		area.position.x, options.position.y + (19 * factor if options.visible else 0)
	)
	message.size.x = area.size.x
	message.add_theme_font_size_override("font_size", roundi(12 * factor))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if splash == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	var center := Vector2(area.get_center().x, size.y / 2)
	draw_texture_rect(
		splash, Rect2(center - Vector2(120, 86) * factor, Vector2(240, 172) * factor), false
	)
	draw_texture_rect(
		_logos[(_ticks / 2) % 2],
		Rect2(center - Vector2(94, 21) * factor, Vector2(188, 43) * factor),
		false
	)
