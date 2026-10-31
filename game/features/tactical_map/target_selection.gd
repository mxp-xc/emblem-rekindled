extends Control

signal intent(kind: String, details: Dictionary)

const Hud = preload("res://features/battle/combat_hud.gd")
const ItemDetails = preload("res://features/tactical_map/item_details.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
var page: String = "items"
var action_kind: String = "attack"
var target_id: int = -1
var _content: Dictionary
var _items: Array = []
var _targets: Array = []
var _panel: PanelContainer
var _rows: VBoxContainer
var _footer: Control
var _hud: Control
var _confirm: Button
var _back: Button
var _textures: Dictionary = {}
var _item_index: int = 0
var _left_side: bool = true


func setup(content: Dictionary) -> void:
	_content = content
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = content["entry"]["interface"].get_base_dir()
	for key: String in content["interface"]["textures"]:
		_textures[key] = load(directory.path_join(content["interface"]["textures"][key]["texture"]))
	_panel = PanelContainer.new()
	add_child(_panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	_panel.add_child(_rows)
	_footer = ItemDetails.new()
	add_child(_footer)
	_footer.setup(content)
	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(content)
	_confirm = _icon_button("button_0", _confirm_current)
	_confirm.name = "Confirm"
	_confirm.tooltip_text = "确认"
	_back = _icon_button("button_1", go_back)
	_back.tooltip_text = "返回"
	resized.connect(_layout)
	_panel.minimum_size_changed.connect(_layout)
	hide()


func present(items: Array, action: String = "attack", left_side: bool = true) -> void:
	_items = items
	action_kind = action
	_left_side = left_side
	_item_index = 0
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for index: int in range(_items.size()):
		var held: Dictionary = _items[index]["item"]
		var metadata: Dictionary = _content["interface"]["items"][str(int(held["templateId"]))]
		var button := Button.new()
		button.name = (
			"Staff_" + str(index)
			if action_kind == "heal"
			else "Weapon_" + str(int(held["templateId"]))
		)
		button.text = "%s  %d" % [metadata["name"]["text"], held["durability"]]
		button.icon = _textures.get(metadata["icon"])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 30)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(220, 56)
		button.add_theme_font_size_override("font_size", 28)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.mouse_entered.connect(button.grab_focus)
		button.focus_entered.connect(_select_item.bind(index))
		button.pressed.connect(_choose_item.bind(index))
		_rows.add_child(button)
	_show_items()
	show()
	if _rows.get_child_count() > 0:
		_rows.get_child(0).grab_focus()
	_select_item(0)


func _select_item(index: int) -> void:
	_item_index = index
	_footer.present(_items[index]["item"], _items[index].get("information", {}))


func _choose_item(index: int) -> void:
	_item_index = index
	intent.emit("item_selected", {"item": _items[index]["item"]["id"], "action": action_kind})


func show_targets(targets: Array) -> void:
	_targets = targets
	page = "targets"
	_panel.hide()
	_footer.hide()
	_hud.hide()
	_confirm.show()
	if not _targets.is_empty():
		_highlight(int(_targets[0]["id"]))
	_layout()


func select_target(id: int) -> void:
	if page != "targets":
		return
	for target: Dictionary in _targets:
		if int(target["id"]) == id:
			_highlight(id)
			intent.emit(
				"target_selected",
				{"target": id, "item": _items[_item_index]["item"]["id"], "action": action_kind}
			)
			return


func _highlight(id: int) -> void:
	target_id = id
	intent.emit("target_highlight", {"target": id, "action": action_kind})


func show_forecast(preview: Dictionary) -> void:
	page = "forecast"
	_hud.present(preview, false)
	_hud.show()
	# Forecast owns map input until confirm or Back; directions do not change targets.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if page == "items":
		if event.keycode in [KEY_LEFT, KEY_RIGHT]:
			_footer.cycle()
			return true
		if event.keycode in [KEY_UP, KEY_DOWN]:
			var direction: int = -1 if event.keycode == KEY_UP else 1
			_item_index = posmod(_item_index + direction, _items.size())
			_rows.get_child(_item_index).grab_focus()
			return true
		return false
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_confirm_current()
		return true
	if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		if page == "targets" and not _targets.is_empty():
			var index: int = 0
			for candidate: int in range(_targets.size()):
				if int(_targets[candidate]["id"]) == target_id:
					index = candidate
			var direction: int = -1 if event.keycode in [KEY_UP, KEY_LEFT] else 1
			_highlight(int(_targets[posmod(index + direction, _targets.size())]["id"]))
		return true
	return false


func _confirm_current() -> void:
	match page:
		"items":
			_choose_item(_item_index)
		"targets":
			select_target(target_id)
		"forecast":
			intent.emit("attack_confirmed", {"target": target_id})


func go_back() -> void:
	match page:
		"forecast":
			page = "targets"
			_hud.hide()
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			_highlight(target_id)
		"targets":
			intent.emit("target_cancelled", {})
			_show_items()
			_rows.get_child(_item_index).grab_focus()
		_:
			hide()
			intent.emit("closed", {})
	_layout()


func _show_items() -> void:
	page = "items"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.show()
	_footer.show()
	_hud.hide()
	_confirm.visible = action_kind == "heal"
	_layout()


func _layout() -> void:
	if _panel == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	_panel.size = Vector2(minf(area.size.x - 32, 340), _panel.get_combined_minimum_size().y)
	_panel.position = area.get_center() - _panel.size / 2
	if action_kind == "heal":
		_panel.position = Vector2(
			area.position.x if _left_side else area.end.x - _panel.size.x, 14 * factor
		)
	_footer.position = Vector2(area.position.x, size.y - 45 * factor)
	_footer.size = Vector2(area.size.x, 45 * factor)
	_confirm.position = area.position + Vector2(0, size.y - 22 * factor)
	_back.position = area.end - Vector2(24, 22) * factor
	for button: Button in [_confirm, _back]:
		button.size = Vector2(24, 22) * factor
		button.icon_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if button == _confirm else HORIZONTAL_ALIGNMENT_RIGHT
		)
		button.add_theme_constant_override("icon_max_width", roundi(10 * factor))
		var style := StyleBoxEmpty.new()
		style.content_margin_top = 14 * factor
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, style)


func _icon_button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = _textures[key]
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 30)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.pressed.connect(action)
	add_child(button)
	return button
