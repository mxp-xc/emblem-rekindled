extends PanelContainer

signal intent(kind: String, details: Dictionary)

var _actions: VBoxContainer
var _buttons: Dictionary = {}
var _finger: Texture2D


func setup(data: Dictionary) -> void:
	_finger = load(
		data["entry"]["interface"].get_base_dir().path_join(
			data["interface"]["textures"]["finger"]["texture"]
		)
	)
	var status := VBoxContainer.new()
	status.name = "Status"
	status.add_theme_constant_override("separation", 0)
	add_child(status)
	_actions = VBoxContainer.new()
	_actions.name = "Actions"
	_actions.add_theme_constant_override("separation", 0)
	status.add_child(_actions)
	for entry: Array in [
		["Information", "状态", "information"],
		["Attack", "攻击", "attack"],
		["Heal", "杖", "heal"],
		["Trade", "交换", "trade"],
		["Inventory", "物品", "inventory"],
		["Wait", "待机", "wait"],
		["Cancel", "取消移动", "cancel_move"]
	]:
		var button: Button = _button(entry[1], entry[2])
		button.name = entry[0]
		_buttons[entry[2]] = button
		_actions.add_child(button)
	visibility_changed.connect(_focus_current)
	hide()


func present(available: Array) -> void:
	for kind: String in _buttons:
		_buttons[kind].visible = kind == "information" or kind in available
	_actions.show()


func _focus_current() -> void:
	if not visible:
		return
	for child: Node in _actions.get_children():
		if child is Button and child.visible and not child.disabled:
			child.grab_focus()
			return


func _button(text: String, kind: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.mouse_entered.connect(button.grab_focus)
	button.focus_entered.connect(func() -> void: button.icon = _finger)
	button.focus_exited.connect(func() -> void: button.icon = null)
	button.pressed.connect(func() -> void: intent.emit(kind, {}))
	return button
