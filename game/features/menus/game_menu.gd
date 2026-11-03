extends ColorRect

signal intent(kind: String, details: Dictionary)

const CommanderScreen = preload("res://features/menus/commander_screen.gd")
const MenuNavigation = preload("res://ui/menu_navigation.gd")
const GAME_SPEEDS: Array[int] = [1, 2, 4, 8, 16, 32]

var page: String = "main"
var panel: PanelContainer
var _pages: Dictionary = {}
var _save: Button
var _return_title: Button
var _end_turn: Button
var _commander_button: Button
var _commander: Control
var _configuration: Dictionary = {}
var _music: Button
var _speed: Button
var _map_controls: VBoxContainer
var _zoom: HSlider
var _assisted_victory: Button
var _assistance_buttons: Dictionary = {}
var _notice: Label
var _notice_remaining: float = 0
var _title_context: bool = false
var _safe: Rect2
var _slider_touches: Dictionary = {}
var _page_focus: Dictionary = {}


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
	main.add_child(_button("辅助功能", "assistance"))
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
	volume.gui_input.connect(_touch_slider.bind(volume))
	volume.value_changed.connect(
		func(value: float) -> void: intent.emit("volume", {"value": value})
	)
	options.add_child(volume)
	_map_controls = VBoxContainer.new()
	options.add_child(_map_controls)
	_map_controls.add_child(_label("地图缩放"))
	_zoom = HSlider.new()
	_zoom.name = "MapZoom"
	_zoom.step = 0.1
	_zoom.scrollable = false
	_zoom.custom_minimum_size.y = 48
	_zoom.gui_input.connect(_touch_slider.bind(_zoom))
	_zoom.value_changed.connect(func(value: float) -> void: intent.emit("zoom", {"value": value}))
	_map_controls.add_child(_zoom)
	_map_controls.add_child(_button("自适应缩放", "fit_map"))
	_map_controls.add_child(_button("查看全图", "overview"))
	_speed = _button("", "speed")
	_speed.name = "GameSpeed"
	options.add_child(_speed)
	set_game_speed(Engine.time_scale)
	options.add_child(_button("返回", "back"))
	var speed_options: VBoxContainer = _page(column, "speed")
	speed_options.add_child(_label("游戏速率", true))
	speed_options.add_child(_label("仅本次运行生效，重启恢复1×。"))
	for rate: int in GAME_SPEEDS:
		var choice: Button = _button(
			"1×（正常）" if rate == 1 else "%d×" % rate, "game_speed", {"value": rate}
		)
		choice.name = "Speed_%d" % rate
		speed_options.add_child(choice)
	speed_options.add_child(_button("返回", "back"))
	var assistance: VBoxContainer = _page(column, "assistance")
	assistance.add_child(_label("辅助功能", true))
	for option: Array in [["经验共享", "share_experience"], ["升级全属性", "full_growth"]]:
		var toggle: Button = _button(option[0], "assistance_toggle", {"key": option[1]}, true)
		toggle.name = option[1]
		_assistance_buttons[option[1]] = toggle
		assistance.add_child(toggle)
	set_assistance(settings)
	_assisted_victory = _button("直接通关", "confirm_victory", {}, true)
	_assisted_victory.name = "AssistedVictory"
	assistance.add_child(_assisted_victory)
	assistance.add_child(_label("直接通关需确认后生效。"))
	assistance.add_child(_button("返回", "back"))
	var confirmation: VBoxContainer = _page(column, "confirm_victory")
	confirmation.add_child(_label("确定直接通关当前关卡？", true))
	confirmation.add_child(_label("将进入胜利剧情与路线选择。"))
	confirmation.add_child(_button("确认通关", "assisted_victory"))
	confirmation.add_child(_button("取消", "back"))
	var objective: VBoxContainer = _page(column, "objective")
	objective.add_child(_label("胜利条件", true))
	objective.add_child(_label(data["story"]["objective"]["text"]))
	objective.add_child(_button("返回", "back"))
	var help: VBoxContainer = _page(column, "help")
	help.add_child(_label("游戏帮助", true))
	help.add_child(_label("\n\n".join(data["controls"]["opening"])))
	help.add_child(_button("返回", "back"))
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


func present(
	can_save: bool, at_title: bool, configuration: Dictionary, view_settings: Dictionary = {}
) -> void:
	_title_context = at_title
	_map_controls.visible = not at_title and not view_settings.is_empty()
	if _map_controls.visible:
		_zoom.set_block_signals(true)
		_zoom.min_value = view_settings["minimum"]
		_zoom.max_value = view_settings["maximum"]
		_zoom.value = view_settings["value"]
		_zoom.set_block_signals(false)
	_configuration = configuration
	_save.disabled = not can_save
	_return_title.disabled = not can_save
	_end_turn.disabled = not can_save
	_commander_button.disabled = not can_save
	_assisted_victory.disabled = at_title or not can_save
	show()
	show_page("settings" if at_title else "main")


func show_page(value: String) -> void:
	if value != "confirm_victory" and _assisted_victory != null:
		_assisted_victory.set_pressed_no_signal(false)
	var focused: Control = get_viewport().gui_get_focus_owner()
	if _pages.has(page) and focused != null and _pages[page].is_ancestor_of(focused):
		_page_focus[page] = focused
	page = value
	_slider_touches.clear()
	_notice.hide()
	_notice_remaining = 0
	if _commander != null:
		if page == "commander":
			_commander.present(_configuration)
		else:
			_commander.hide()
	panel.visible = page != "commander"
	for key: String in _pages:
		_pages[key].visible = key == value
	_layout()
	var previous: Control = _page_focus.get(value)
	if (
		previous != null
		and previous.is_visible_in_tree()
		and not (previous is BaseButton and previous.disabled)
	):
		previous.grab_focus()
		return
	for button: Node in _pages[value].get_children() if _pages.has(value) else []:
		if button is Button and button.visible and not button.disabled:
			button.grab_focus()
			break


func go_back() -> bool:
	if page == "confirm_victory":
		show_page("assistance")
	elif page == "assistance":
		show_page("main")
	elif page == "speed":
		show_page("settings")
	elif page == "commander":
		_commander.commit()
	elif page != "main" and not _title_context:
		show_page("main")
	else:
		return false
	return true


func handle_key(event: InputEventKey) -> bool:
	return _commander.handle_key(event) if page == "commander" else false


func handle_wheel(direction: int) -> void:
	if page == "commander":
		_commander.handle_wheel(direction)
		return
	var rows: Array[Button] = []
	for button: Node in _pages[page].find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != FOCUS_NONE:
			rows.append(button)
	MenuNavigation.step_buttons(rows, direction)


func set_music_state(enabled: bool, started: bool) -> void:
	_music.text = ("音乐 · 开" if started else "音乐 · 点按播放") if enabled else "音乐 · 关"


func set_game_speed(value: float) -> void:
	_speed.text = "游戏速率 · %d×" % int(value)


func set_assistance(settings: Dictionary) -> void:
	for key: String in _assistance_buttons:
		_assistance_buttons[key].set_pressed_no_signal(settings.get(key, false))


func set_notice(message: String, transient: bool = false) -> void:
	_notice.text = message
	_notice.visible = not message.is_empty()
	_notice_remaining = 2.0 if transient and not message.is_empty() else 0
	_layout()


func _process(delta: float) -> void:
	if _notice_remaining <= 0:
		return
	_notice_remaining -= delta
	if _notice_remaining <= 0:
		set_notice("")


func _touch_slider(event: InputEvent, slider: HSlider) -> void:
	# Map touch gestures are independent of mouse emulation; native sliders need touch input.
	if event is InputEventScreenTouch:
		if not event.pressed:
			if _slider_touches.get(slider, -1) == event.index:
				_slider_touches.erase(slider)
			return
		if not _slider_touches.has(slider):
			_slider_touches[slider] = event.index
	elif not event is InputEventScreenDrag:
		return
	if _slider_touches.get(slider, -1) != event.index:
		return
	var inset: float = slider.get_theme_icon("grabber").get_width() / 2.0
	slider.ratio = clampf((event.position.x - inset) / maxf(1, slider.size.x - inset * 2), 0, 1)
	slider.accept_event()


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


func _button(text: String, kind: String, details: Dictionary = {}, toggle: bool = false) -> Button:
	var button: Button = CheckButton.new() if toggle else Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(220, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.pressed.connect(
		func() -> void:
			_choose(kind, details.merged({"value": button.button_pressed}) if toggle else details)
	)
	return button


func _choose(kind: String, details: Dictionary) -> void:
	if _title_context and kind in ["assistance", "confirm_victory"]:
		return
	if (
		kind
		in ["settings", "objective", "help", "commander", "assistance", "confirm_victory", "speed"]
	):
		show_page(kind)
	elif kind == "back":
		if not go_back():
			intent.emit("close", {})
	else:
		intent.emit(kind, details)


func _label(text: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 28 if heading else 24)
	if heading:
		label.add_theme_color_override("font_color", Color("fff000"))
	return label
