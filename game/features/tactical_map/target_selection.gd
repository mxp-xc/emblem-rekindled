extends Control

signal intent(kind: String, details: Dictionary)

const Hud = preload("res://features/battle/combat_hud.gd")
const MapForecast = preload("res://features/tactical_map/map_attack_forecast.gd")
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
var _repair_rows: VBoxContainer
var _repair_items: Array = []
var _repair_index: int = 0
var _destination: Vector2i
var _footer: Control
var _hud: Control
var _map_forecast: Control
var _unavailable: Label
var _confirm: Button
var _back: Button
var _textures: Dictionary = {}
var _item_index: int = 0
var _left_side: bool = true
var _confirmed: bool = false


func setup(content: Dictionary) -> void:
	_content = content
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = content["entry"]["resourceDirectory"]
	for key: String in content["interface"]["textures"]:
		_textures[key] = load(directory.path_join(content["interface"]["textures"][key]["texture"]))
	_panel = PanelContainer.new()
	add_child(_panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	_panel.add_child(_rows)
	_repair_rows = VBoxContainer.new()
	_repair_rows.add_theme_constant_override("separation", 0)
	_panel.add_child(_repair_rows)
	_repair_rows.hide()
	_footer = ItemDetails.new()
	add_child(_footer)
	_footer.setup(content)
	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(content)
	_map_forecast = MapForecast.new()
	_map_forecast.name = "MapAttackForecast"
	add_child(_map_forecast)
	_map_forecast.setup(content)
	_unavailable = Label.new()
	_unavailable.name = "UnavailableReason"
	_unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unavailable.add_theme_color_override("font_color", Color("fff000"))
	_unavailable.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_unavailable)
	_confirm = _icon_button("button_0", _confirm_current)
	_confirm.name = "Confirm"
	_confirm.tooltip_text = "确认"
	_back = _icon_button("button_1", go_back)
	_back.name = "Back"
	_back.tooltip_text = "返回"
	resized.connect(_layout)
	_panel.minimum_size_changed.connect(_layout)
	hide()


func present(items: Array, action: String = "attack", left_side: bool = true) -> void:
	_items = items
	action_kind = action
	_left_side = left_side
	_item_index = 0
	target_id = -1
	_targets = []
	_confirmed = false
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
		if not _items[index].get("available", true):
			button.text += " · 不可用"
			button.add_theme_color_override("font_color", Color("a0a9b8"))
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
	if index < 0 or index >= _items.size():
		return
	_item_index = index
	_footer.present(_items[index]["item"], _items[index].get("information", {}))
	_unavailable.text = _unavailable_reason(str(_items[index].get("reason", "")))
	_unavailable.visible = not _items[index].get("available", true)
	_layout()


func _choose_item(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	_item_index = index
	if not _items[index].get("available", true):
		_select_item(index)
		return
	intent.emit("item_selected", {"item": _items[index]["item"]["id"], "action": action_kind})


func show_targets(targets: Array) -> void:
	_targets = targets
	page = "targets"
	_panel.hide()
	_footer.hide()
	_hud.hide()
	_map_forecast.hide()
	_unavailable.hide()
	_confirmed = false
	_confirm.disabled = false
	_confirm.show()
	if not _targets.is_empty():
		_highlight(int(_targets[0]["id"]))
	_layout()


func show_repair_items(items: Array) -> void:
	_repair_items = items
	_repair_index = 0
	page = "repair_items"
	_confirmed = false
	_rows.hide()
	_repair_rows.show()
	_panel.show()
	_footer.visible = not items.is_empty()
	_hud.hide()
	_map_forecast.hide()
	_unavailable.text = "没有持有物品"
	_unavailable.visible = items.is_empty()
	_confirm.show()
	_confirm.disabled = items.is_empty()
	for child: Node in _repair_rows.get_children():
		_repair_rows.remove_child(child)
		child.queue_free()
	for index: int in range(items.size()):
		var held: Dictionary = items[index]
		var metadata: Dictionary = _content["interface"]["items"][str(int(held["templateId"]))]
		var button := Button.new()
		button.name = "RepairItem_" + str(index)
		button.text = "%s  %d" % [metadata["name"]["text"], held["durability"]]
		button.icon = _textures.get(metadata["icon"])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 30)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(220, 56)
		button.add_theme_font_size_override("font_size", 28)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.focus_entered.connect(_select_repair.bind(index))
		button.pressed.connect(_confirm_repair.bind(index))
		_repair_rows.add_child(button)
	if not items.is_empty():
		_repair_rows.get_child(0).grab_focus()
		_select_repair(0)
	_layout()


func _select_repair(index: int) -> void:
	_repair_index = index
	_footer.present(_repair_items[index])


func _confirm_repair(index: int) -> void:
	if page != "repair_items" or _confirmed or index < 0 or index >= _repair_items.size():
		return
	_confirmed = true
	_confirm.disabled = true
	intent.emit(
		"repair_confirmed",
		{
			"target": target_id,
			"item": _items[_item_index]["item"]["id"],
			"targetItem": _repair_items[index]["id"]
		}
	)


func show_destination(cell: Vector2i, valid: bool) -> void:
	page = "destination"
	_confirmed = false
	_panel.hide()
	_footer.hide()
	_hud.hide()
	_map_forecast.hide()
	_unavailable.hide()
	_confirm.show()
	select_destination(cell, valid)
	_layout()


func select_destination(cell: Vector2i, valid: bool) -> void:
	if page != "destination" or _confirmed:
		return
	_destination = cell
	_confirm.disabled = not valid


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
	_confirmed = false
	_confirm.disabled = false
	_map_forecast.hide()
	_panel.hide()
	_footer.hide()
	_unavailable.hide()
	_hud.present(preview, false)
	_hud.show()
	# Forecast owns map input until confirm or Back; directions do not change targets.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()


func show_map_forecast(preview: Dictionary) -> void:
	page = "map_forecast"
	target_id = int(preview["primary"])
	_confirmed = false
	_confirm.disabled = false
	_panel.hide()
	_footer.hide()
	_hud.hide()
	_unavailable.hide()
	_map_forecast.present(preview)
	_confirm.show()
	# The preview owns the whole map region, including blank space outside its panel.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if page in ["items", "repair_items"]:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_confirm_current()
			return true
		if event.keycode in [KEY_LEFT, KEY_RIGHT]:
			_footer.cycle()
			return true
		if event.keycode in [KEY_UP, KEY_DOWN]:
			handle_wheel(-1 if event.keycode == KEY_UP else 1)
			return true
		return false
	if page == "destination":
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_confirm_current()
			return true
		if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			var offset: Vector2i = {
				KEY_UP: Vector2i.UP,
				KEY_DOWN: Vector2i.DOWN,
				KEY_LEFT: Vector2i.LEFT,
				KEY_RIGHT: Vector2i.RIGHT
			}[event.keycode]
			intent.emit("destination_highlight", {"cell": _destination + offset})
			return true
		return false
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_confirm_current()
		return true
	if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		handle_wheel(-1 if event.keycode in [KEY_UP, KEY_LEFT] else 1)
		return true
	return false


func handle_wheel(direction: int) -> void:
	if page == "items":
		if not _items.is_empty():
			_item_index = posmod(_item_index + direction, _items.size())
			_rows.get_child(_item_index).grab_focus()
	elif page == "repair_items" and not _repair_items.is_empty():
		_repair_index = posmod(_repair_index + direction, _repair_items.size())
		_repair_rows.get_child(_repair_index).grab_focus()
	elif page == "targets" and not _targets.is_empty():
		var index: int = 0
		for candidate: int in range(_targets.size()):
			if int(_targets[candidate]["id"]) == target_id:
				index = candidate
		_highlight(int(_targets[posmod(index + direction, _targets.size())]["id"]))
	elif page == "map_forecast":
		_map_forecast.scroll_targets(direction)


func _confirm_current() -> void:
	match page:
		"items":
			_choose_item(_item_index)
		"repair_items":
			_confirm_repair(_repair_index)
		"destination":
			if not _confirmed and not _confirm.disabled:
				_confirmed = true
				_confirm.disabled = true
				intent.emit(
					"teleport_confirmed",
					{
						"target": target_id,
						"item": _items[_item_index]["item"]["id"],
						"cell": _destination
					}
				)
		"targets":
			select_target(target_id)
		"forecast":
			if not _confirmed:
				_confirmed = true
				_confirm.disabled = true
				intent.emit("attack_confirmed", {"target": target_id})
		"map_forecast":
			if not _confirmed:
				_confirmed = true
				_confirm.disabled = true
				intent.emit("map_attack_confirmed", {"target": target_id})


func go_back() -> void:
	match page:
		"repair_items", "destination":
			var previous_target: int = target_id
			show_targets(_targets)
			_highlight(previous_target)
			intent.emit("secondary_cancelled", {"target": previous_target})
		"map_forecast":
			_map_forecast.hide()
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			if target_id < 0:
				intent.emit("target_cancelled", {})
				_show_items()
				_focus_selected_item()
			else:
				page = "targets"
				_confirm.disabled = false
				_highlight(target_id)
		"forecast":
			page = "targets"
			_hud.hide()
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			_confirm.disabled = false
			_highlight(target_id)
		"targets":
			intent.emit("target_cancelled", {})
			_show_items()
			_focus_selected_item()
		_:
			hide()
			intent.emit("closed", {})
	_layout()


func _show_items() -> void:
	page = "items"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.show()
	_rows.show()
	_repair_rows.hide()
	_footer.show()
	_hud.hide()
	_map_forecast.hide()
	_confirm.disabled = false
	_confirm.visible = action_kind == "heal"
	_select_item(_item_index)
	_layout()


func _focus_selected_item() -> void:
	if _item_index >= 0 and _item_index < _rows.get_child_count():
		_rows.get_child(_item_index).grab_focus()


func _unavailable_reason(reason: String) -> String:
	match reason:
		"ROUND_UNAVAILABLE":
			return "本回合不可使用"
		"NO_ATTACK_TARGETS":
			return "没有可攻击的目标"
		"MAP_EFFECT_UNAVAILABLE":
			return "地图效果尚未就绪"
		"INVALID_MAP_ATTACK_RULE":
			return "地图攻击配置无效"
		_:
			return "当前不可使用"


func _layout() -> void:
	if _panel == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	_map_forecast.position = Vector2.ZERO
	_map_forecast.size = size
	_panel.size = Vector2(minf(area.size.x - 32, 340), _panel.get_combined_minimum_size().y)
	_panel.position = area.get_center() - _panel.size / 2
	if action_kind == "heal":
		_panel.position = Vector2(
			area.position.x if _left_side else area.end.x - _panel.size.x, 14 * factor
		)
	_footer.position = Vector2(area.position.x, size.y - 45 * factor)
	_footer.size = Vector2(area.size.x, 45 * factor)
	_unavailable.position = Vector2(area.position.x + 12, _footer.position.y - 54)
	_unavailable.size = Vector2(maxf(0, area.size.x - 24), 50)
	_unavailable.add_theme_font_size_override("font_size", roundi(10 * factor))
	for button: Button in [_confirm, _back]:
		button.icon_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if button == _confirm else HORIZONTAL_ALIGNMENT_RIGHT
		)
		button.add_theme_constant_override("icon_max_width", roundi(10 * factor))
		var style := StyleBoxEmpty.new()
		style.content_margin_top = 14 * factor
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, style)
		button.size = Vector2(24, 22) * factor
	_confirm.position = Vector2(area.position.x, size.y - _confirm.size.y)
	_back.position = area.end - _back.size


func _icon_button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = _textures[key]
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 30)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.pressed.connect(action)
	add_child(button)
	return button
