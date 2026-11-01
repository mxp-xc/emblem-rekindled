extends Control

signal intent(kind: String, details: Dictionary)

const PixelTheme = preload("res://ui/pixel_theme.gd")
const Details = preload("res://features/tactical_map/item_details.gd")
const MenuNavigation = preload("res://ui/menu_navigation.gd")
const NAMES: Dictionary = {"use": "使用", "equip": "装备", "discard": "丢弃"}
var page: String = "operations"
var operation: String = ""
var _options: Dictionary
var _information: Dictionary
var _interface: Dictionary
var _textures: Dictionary = {}
var _panel: PanelContainer
var _rows: VBoxContainer
var _confirmation: PanelContainer
var _question: Label
var _details: Control
var _confirm: Button
var _back: Button
var _selected: Dictionary = {}


func setup(content: Dictionary) -> void:
	_interface = content["interface"]
	var directory: String = content["entry"]["interface"].get_base_dir()
	for key: String in _interface["textures"]:
		_textures[key] = load(directory.path_join(_interface["textures"][key]["texture"]))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	add_child(_panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	_panel.add_child(_rows)
	_confirmation = PanelContainer.new()
	add_child(_confirmation)
	_question = Label.new()
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirmation.add_child(_question)
	_details = Details.new()
	add_child(_details)
	_details.setup(content)
	_confirm = _icon_button("button_0", _accept)
	_confirm.tooltip_text = "确认"
	_back = _icon_button("button_1", go_back)
	_back.tooltip_text = "返回"
	resized.connect(_layout)
	_panel.minimum_size_changed.connect(_layout)
	hide()


func present(options: Dictionary, information: Dictionary) -> void:
	_options = options
	_information = information
	page = "operations"
	show()
	_render()


func refresh(options: Dictionary, information: Dictionary) -> void:
	_options = options
	_information = information
	if options.is_empty():
		hide()
		intent.emit("closed", {})
		return
	page = "items" if _options.has(operation) else "operations"
	_render()


func go_back() -> void:
	match page:
		"confirm":
			page = "items"
		"items":
			page = "operations"
		_:
			hide()
			intent.emit("closed", {})
			return
	_render()


func handle_key(event: InputEventKey) -> bool:
	if (
		page == "confirm"
		and event.pressed
		and not event.echo
		and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	):
		_accept()
		return true
	return false


func handle_wheel(direction: int) -> void:
	if page == "confirm":
		return
	var rows: Array[Button] = []
	for button: Button in _rows.get_children():
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != FOCUS_NONE:
			rows.append(button)
	MenuNavigation.step_buttons(rows, direction)


func _render() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_panel.visible = page != "confirm"
	_confirmation.visible = page == "confirm"
	_confirm.visible = page == "confirm"
	_details.visible = page == "items"
	if page == "operations":
		for kind: String in NAMES:
			if _options.has(kind):
				var button: Button = _button(NAMES[kind])
				button.name = kind.capitalize()
				button.pressed.connect(_choose_operation.bind(kind))
				_rows.add_child(button)
	elif page == "items":
		var selected: Button
		for held: Dictionary in _options[operation]:
			var item: Dictionary = _interface["items"][str(int(held["templateId"]))]
			var button: Button = _button("%s  %d" % [item["name"]["text"], held["durability"]])
			button.name = "Item_" + str(int(held["templateId"]))
			button.icon = _textures.get(item["icon"])
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 30)
			button.focus_entered.connect(_select.bind(held))
			button.pressed.connect(_ask.bind(held))
			_rows.add_child(button)
			if held["id"] == _selected.get("id"):
				selected = button
		if selected == null:
			selected = _rows.get_child(0)
		selected.grab_focus()
	else:
		_question.text = (
			"确认要%s%s吗？"
			% [
				NAMES[operation],
				_interface["items"][str(int(_selected["templateId"]))]["name"]["text"]
			]
		)
	if page == "operations" and _rows.get_child_count() > 0:
		_rows.get_child(0).grab_focus()
	_layout()


func _choose_operation(kind: String) -> void:
	operation = kind
	_selected = {}
	page = "items"
	_render()


func _select(held: Dictionary) -> void:
	_selected = held
	_details.present(held, _information.get(held["id"], {}) if operation == "equip" else {})


func _ask(held: Dictionary) -> void:
	_selected = held
	page = "confirm"
	_render()


func _accept() -> void:
	if page == "confirm":
		intent.emit(operation, {"item": _selected["id"]})


func _layout() -> void:
	if _panel == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	_panel.size = Vector2(
		minf(area.size.x - 32, 340 if page == "items" else 220),
		_panel.get_combined_minimum_size().y
	)
	_panel.position = area.get_center() - _panel.size / 2
	_confirmation.size = Vector2(area.size.x, _confirmation.get_combined_minimum_size().y)
	_confirmation.position = area.get_center() - _confirmation.size / 2
	_question.add_theme_font_size_override("font_size", roundi(12 * factor))
	_details.position = Vector2(area.position.x, size.y - 45 * factor)
	_details.size = Vector2(area.size.x, 45 * factor)
	_confirm.position = Vector2(area.position.x, size.y - 22 * factor)
	_back.position = area.end - Vector2(24, 22) * factor
	for button: Button in [_confirm, _back]:
		button.size = Vector2(24, 22) * factor


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	return button


func _icon_button(key: String, action: Callable) -> Button:
	var button: Button = _button("")
	button.custom_minimum_size = Vector2.ZERO
	button.icon = _textures[key]
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 30)
	button.pressed.connect(action)
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button
