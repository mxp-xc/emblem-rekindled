extends ColorRect

signal intent(kind: String, details: Dictionary)

const CommanderScreen = preload("res://features/menus/commander_screen.gd")

var page: String = "main"
var license_view: VBoxContainer
var panel: PanelContainer
var _pages: Dictionary = {}
var _save: Button
var _return_title: Button
var _end_turn: Button
var _commander_button: Button
var _commander: Control
var _configuration: Dictionary = {}
var _music: Button
var _notice: Label
var _title_context: bool = false
var _safe: Rect2


func setup(data: Dictionary, settings: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.12)
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = PanelContainer.new()
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var main: VBoxContainer = _page(column, "main")
	_end_turn = _button("结束回合", "end_turn")
	main.add_child(_end_turn)
	main.add_child(_button("胜利条件", "objective"))
	_save = _button("保存进度", "save")
	main.add_child(_save)
	_commander_button = _button("指挥官配置", "commander")
	main.add_child(_commander_button)
	main.add_child(_button("游戏帮助", "help"))
	main.add_child(_button("游戏设置", "settings"))
	_return_title = _button("回主菜单", "return_title")
	main.add_child(_return_title)
	var options: VBoxContainer = _page(column, "settings")
	_music = _button("音乐", "music")
	options.add_child(_music)
	options.add_child(_label("音量"))
	var volume := HSlider.new()
	volume.name = "Volume"
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = settings["volume"]
	volume.custom_minimum_size.y = 48
	volume.value_changed.connect(
		func(value: float) -> void: intent.emit("volume", {"value": value})
	)
	options.add_child(volume)
	options.add_child(_button("查看全图", "overview"))
	options.add_child(_button("字体许可", "license"))
	options.add_child(_button("返回", "back"))
	var objective: VBoxContainer = _page(column, "objective")
	objective.add_child(_label("胜利条件", true))
	objective.add_child(_label(data["story"]["objective"]["text"]))
	objective.add_child(_button("返回", "back"))
	var help: VBoxContainer = _page(column, "help")
	help.add_child(_label("游戏帮助", true))
	help.add_child(_label("\n\n".join(data["controls"]["opening"])))
	help.add_child(_button("返回", "back"))
	license_view = _page(column, "license")
	license_view.add_child(_label("字体许可", true))
	var license_text := TextEdit.new()
	license_text.text = FileAccess.get_file_as_string("res://ui/fonts/OFL.txt")
	license_text.editable = false
	license_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	license_text.custom_minimum_size = Vector2(0, 500)
	license_text.add_theme_font_size_override("font_size", 18)
	license_view.add_child(license_text)
	license_view.add_child(_button("返回", "back"))
	_notice = _label("")
	_notice.hide()
	column.add_child(_notice)
	panel.minimum_size_changed.connect(_layout)
	resized.connect(_layout)
	_commander = CommanderScreen.new()
	add_child(_commander)
	_commander.setup(data)
	_commander.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_commander.confirmed.connect(
		func(configuration: Dictionary) -> void: intent.emit("commander_commit", configuration)
	)
	show_page("main")
	hide()


func present(can_save: bool, at_title: bool, configuration: Dictionary) -> void:
	_title_context = at_title
	_configuration = configuration
	_save.disabled = not can_save
	_return_title.disabled = not can_save
	_end_turn.disabled = not can_save
	_commander_button.disabled = not can_save
	show_page("settings" if at_title else "main")
	show()
	_layout()


func show_page(value: String) -> void:
	page = value
	if _commander != null:
		if page == "commander":
			_commander.present(_configuration)
		else:
			_commander.hide()
	panel.visible = page != "commander"
	for key: String in _pages:
		_pages[key].visible = key == value
	_layout()


func go_back() -> bool:
	if page == "commander":
		_commander.commit()
	elif page == "license":
		show_page("settings")
	elif page != "main" and not _title_context:
		show_page("main")
	else:
		return false
	return true


func handle_key(event: InputEventKey) -> bool:
	return _commander.handle_key(event) if page == "commander" else false


func set_music_state(enabled: bool, started: bool) -> void:
	_music.text = ("音乐 · 开" if started else "音乐 · 点按播放") if enabled else "音乐 · 关"


func set_notice(message: String) -> void:
	_notice.text = message
	_notice.visible = not message.is_empty()
	_layout()


func set_safe_rect(value: Rect2) -> void:
	_safe = value
	_layout()


func _layout() -> void:
	if panel == null:
		return
	var safe: Rect2 = _safe if _safe.has_area() else Rect2(Vector2.ZERO, size)
	if _commander != null:
		_commander.position = safe.position
		_commander.size = safe.size
	var width: float = 290 if page == "main" else 560
	panel.size = Vector2(minf(width, safe.size.x - 40), panel.get_combined_minimum_size().y)
	panel.position = safe.get_center() - panel.size / 2.0


func _page(parent: VBoxContainer, key: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	parent.add_child(column)
	_pages[key] = column
	return column


func _button(text: String, kind: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(220, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: _choose(kind))
	return button


func _choose(kind: String) -> void:
	if kind in ["settings", "objective", "help", "license", "commander"]:
		show_page(kind)
	elif kind == "back":
		if not go_back():
			intent.emit("close", {})
	else:
		intent.emit(kind, {})


func _label(text: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 28 if heading else 24)
	if heading:
		label.add_theme_color_override("font_color", Color("fff000"))
	return label
