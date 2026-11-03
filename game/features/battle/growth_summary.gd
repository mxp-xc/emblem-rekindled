extends Control

signal confirmed

const STAT_LABELS: Array[String] = ["最大HP", "力量", "技巧", "速度", "魔力", "防御", "幸运", "移动"]
var selected_index: int = 0
var panel: PanelContainer
var _rows: Array = []
var _buttons: Array[Button] = []
var _heading: Label
var _details: Label
var _equipment: HBoxContainer
var _attributes: GridContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _body: VBoxContainer
var _confirm: Button
var _area: Rect2
var _active: bool = false
var _touch_id: int = -1
var _touch_start: Vector2
var _touch_scroll: int
var _touch_bar: bool = false
var _touch_dragged: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	panel = PanelContainer.new()
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_heading = _label("成长结算")
	_heading.add_theme_color_override("font_color", Color("fff000"))
	column.add_child(_heading)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	_body.add_child(_line(["人物", "等级", "经验", "成长"]))
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	_body.add_child(_list)
	_details = _label("")
	_details.add_theme_color_override("font_color", Color("fff000"))
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_details)
	_equipment = HBoxContainer.new()
	_equipment.name = "PromotionEquipment"
	_body.add_child(_equipment)
	_attributes = GridContainer.new()
	_attributes.columns = 2
	_body.add_child(_attributes)
	for index: int in range(8):
		_attributes.add_child(_label(""))
	_confirm = Button.new()
	_confirm.name = "GrowthConfirm"
	_confirm.text = "确定"
	_confirm.custom_minimum_size.y = 48
	_confirm.pressed.connect(confirm)
	column.add_child(_confirm)
	_body.minimum_size_changed.connect(_layout.call_deferred)
	resized.connect(_layout)
	hide()


func present(rows: Array) -> void:
	_touch_id = -1
	_rows = rows.duplicate(true)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_buttons.clear()
	selected_index = 0
	var found_upgrade: bool = false
	for index: int in range(_rows.size()):
		var row: Dictionary = _rows[index]
		var upgraded: bool = row["levelAfter"] > row["levelBefore"] or row.has("promotion")
		if upgraded and not found_upgrade:
			selected_index = index
			found_upgrade = true
		var button := Button.new()
		button.name = "GrowthUnit_%d" % int(row["unit"])
		button.toggle_mode = true
		button.custom_minimum_size.y = 48
		button.tooltip_text = row["name"]
		var level: String = str(row["levelAfter"])
		if row["levelAfter"] > row["levelBefore"]:
			level = "%d→%d" % [row["levelBefore"], row["levelAfter"]]
		var increments: Array = row["increments"]
		var count: int = increments.filter(func(value: int) -> bool: return value > 0).size()
		var growth: String = "—"
		if row.has("promotion"):
			growth = "转职"
		elif upgraded:
			growth = (
				"全属性+1"
				if increments.all(func(value: int) -> bool: return value == 1)
				else "%d项提升" % count
			)
		var line: HBoxContainer = _line(
			[
				row["name"],
				level,
				"%d→%d (+%d)" % [row["experienceBefore"], row["experienceAfter"], row["amount"]],
				growth
			]
		)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8
		line.offset_right = -8
		if upgraded:
			line.modulate = Color("fff7bf")
		button.add_child(line)
		button.pressed.connect(_select.bind(index))
		button.focus_entered.connect(_select.bind(index))
		_list.add_child(button)
		_buttons.append(button)
	_active = true
	show()
	_select(selected_index)
	_layout()
	_buttons[selected_index].grab_focus()
	await get_tree().process_frame
	if _active:
		_scroll.ensure_control_visible(_buttons[selected_index])


func _select(index: int) -> void:
	selected_index = index
	for position: int in range(_buttons.size()):
		_buttons[position].set_pressed_no_signal(position == index)
	var row: Dictionary = _rows[index]
	var upgraded: bool = row["levelAfter"] > row["levelBefore"] or row.has("promotion")
	_details.text = row["name"] + (" · 升级详情" if upgraded else " · 本次未升级")
	if row.has("promotion"):
		_details.text = (
			"%s · 转职\n%s→%s" % [row["name"], row["classBeforeName"], row["classAfterName"]]
		)
		if not row["newEquipment"].is_empty():
			_details.text += "\n新增装备：" + row["newEquipment"]
	for child: Node in _equipment.get_children():
		_equipment.remove_child(child)
		child.queue_free()
	var icons: Array = row.get("newEquipmentIcons", [])
	_equipment.visible = not icons.is_empty()
	for icon: Dictionary in icons:
		var image := TextureRect.new()
		image.name = "Equipment_" + icon["id"]
		image.texture = load(icon["texture"])
		image.custom_minimum_size = Vector2(32, 32)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.tooltip_text = icon["name"]
		_equipment.add_child(image)
	_attributes.visible = upgraded
	for position: int in range(8):
		var label: Label = _attributes.get_child(position)
		var increment: int = row["increments"][position]
		label.text = (
			"%s  %d → %d" % [STAT_LABELS[position], row["before"][position], row["after"][position]]
		)
		if row.has("promotion"):
			var stat: String = [
				"maxHp", "strength", "skill", "speed", "magic", "defense", "luck", "move"
			][position]
			label.text += "\n转职 +%d" % int(row["promotion"]["increments"][stat])
		label.add_theme_color_override(
			"font_color", Color("fff000") if increment > 0 else Color("a9b3bf")
		)
	_layout()


func confirm() -> void:
	if not _active or not is_visible_in_tree():
		return
	_active = false
	_touch_id = -1
	hide()
	confirmed.emit()


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if event.is_action_pressed("ui_accept"):
		confirm()
		return true
	if event.keycode in [KEY_UP, KEY_DOWN]:
		handle_wheel(-1 if event.keycode == KEY_UP else 1)
		return true
	return false


func handle_wheel(direction: int, point: Vector2 = Vector2.INF) -> void:
	if _scroll.get_global_rect().has_point(point) and not _list.get_global_rect().has_point(point):
		_scroll.scroll_vertical += direction * 48
		return
	_buttons[posmod(selected_index + direction, _buttons.size())].grab_focus()


func _input(event: InputEvent) -> void:
	if not _active or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_id != -1 or not _scroll.get_global_rect().has_point(event.position):
				return
			_touch_id = event.index
			_touch_start = event.position
			_touch_scroll = _scroll.scroll_vertical
			var bar: VScrollBar = _scroll.get_v_scroll_bar()
			_touch_bar = (
				bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position)
			)
			_touch_dragged = false
		elif event.index == _touch_id:
			_touch_id = -1
			if (
				not event.canceled
				and not _touch_dragged
				and not _touch_bar
				and event.position.distance_to(_touch_start) <= 8
			):
				for button: Button in _buttons:
					if button.get_global_rect().has_point(event.position):
						button.grab_focus()
						break
		else:
			return
	elif event is InputEventScreenDrag and event.index == _touch_id:
		var delta: Vector2 = event.position - _touch_start
		_touch_dragged = _touch_dragged or delta.length() > 8
		if _touch_dragged:
			if _touch_bar:
				var bar: VScrollBar = _scroll.get_v_scroll_bar()
				_scroll.scroll_vertical = (
					_touch_scroll + roundi(delta.y * (bar.max_value - bar.min_value) / bar.size.y)
				)
			else:
				_scroll.scroll_vertical = _touch_scroll - roundi(delta.y)
	else:
		return
	get_viewport().set_input_as_handled()


func set_content_area(area: Rect2) -> void:
	if area != _area:
		_touch_id = -1
	_area = area
	_layout()


func _layout() -> void:
	if panel == null:
		return
	var area: Rect2 = _area if _area.has_area() else Rect2(Vector2.ZERO, size)
	var width: float = minf(640, area.size.x - 32)
	var font_size: int = 22 if width >= 560 else 20
	_attributes.columns = 2 if width >= 360 else 1
	for label: Node in panel.find_children("*", "Label", true, false):
		label.add_theme_font_size_override("font_size", font_size)
	var height: float = (
		panel.get_combined_minimum_size().y
		- _scroll.get_combined_minimum_size().y
		+ _body.get_combined_minimum_size().y
	)
	panel.size = Vector2(width, minf(height, area.size.y - 32))
	panel.position = area.get_center() - panel.size / 2


func _line(values: Array) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index: int in range(values.size()):
		var label: Label = _label(str(values[index]))
		label.clip_text = true
		label.size_flags_stretch_ratio = [0.23, 0.19, 0.34, 0.24][index]
		line.add_child(label)
	return line


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 22)
	return label
