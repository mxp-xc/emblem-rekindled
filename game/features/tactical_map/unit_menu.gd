extends PanelContainer

signal intent(kind: String, details: Dictionary)

const MenuNavigation = preload("res://ui/menu_navigation.gd")

var _actions: VBoxContainer
var _buttons: Dictionary = {}
var _finger: Texture2D


func setup(data: Dictionary) -> void:
	_finger = load(
		data["entry"]["resourceDirectory"].path_join(
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
		["OpenChest", "打开宝箱", "open_chest"],
		["Visit", "访问", "visit_location"],
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


func handle_key(_event: InputEventKey) -> bool:
	return false


func handle_wheel(direction: int) -> void:
	var rows: Array[Button] = []
	for button: Button in _actions.get_children():
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != FOCUS_NONE:
			rows.append(button)
	MenuNavigation.step_buttons(rows, direction)


func place_near(cell: Rect2, bounds: Rect2) -> void:
	var minimum: Vector2 = get_combined_minimum_size()
	var factor: float = minf(1, minf(bounds.size.y / minimum.y, bounds.size.x / minimum.x))
	scale = Vector2.ONE * factor
	size = Vector2(minf(220, bounds.size.x / factor), minimum.y)
	var extent: Vector2 = size * factor
	var point := Vector2(cell.end.x + 8, cell.get_center().y - extent.y / 2)
	if point.x + extent.x > bounds.end.x:
		point.x = cell.position.x - extent.x - 8
	if point.x < bounds.position.x:
		point = Vector2(cell.get_center().x - extent.x / 2, cell.end.y + 8)
		if point.y + extent.y > bounds.end.y:
			point.y = cell.position.y - extent.y - 8
	position = Vector2(
		clampf(point.x, bounds.position.x, bounds.end.x - extent.x),
		clampf(point.y, bounds.position.y, bounds.end.y - extent.y)
	)


func _focus_current() -> void:
	if not visible:
		return
	for kind: String in [
		"visit_location",
		"open_chest",
		"attack",
		"heal",
		"trade",
		"inventory",
		"wait",
		"information",
		"cancel_move"
	]:
		var button: Button = _buttons[kind]
		if button.visible and not button.disabled:
			button.grab_focus()
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
