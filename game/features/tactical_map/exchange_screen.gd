extends Control

signal intent(kind: String, details: Dictionary)

const PixelTheme = preload("res://ui/pixel_theme.gd")
const MenuNavigation = preload("res://ui/menu_navigation.gd")
const UnitInventory = preload("res://gameplay/unit_inventory.gd")
var page: String = "targets"
var source_locked: bool = false
var target_id: int = -1
var _targets: Array = []
var _parties: Array = []
var _active_owner: int = 0
var _source_owner: int = -1
var _source_item: String = ""
var _headers: Array[Button] = []
var _lists: Array[VBoxContainer] = []
var _back: Button
var _interface: Dictionary
var _textures: Dictionary = {}


func setup(content: Dictionary) -> void:
	_interface = content["interface"]
	var directory: String = content["entry"]["interface"].get_base_dir()
	for key: String in _interface["textures"]:
		_textures[key] = load(directory.path_join(_interface["textures"][key]["texture"]))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for owner: int in range(2):
		var header := Button.new()
		header.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		header.focus_mode = Control.FOCUS_NONE
		header.pressed.connect(_focus_owner.bind(owner))
		_headers.append(header)
		add_child(header)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 0)
		_lists.append(list)
		add_child(list)
	_back = Button.new()
	_back.icon = _textures["button_1"]
	_back.expand_icon = true
	_back.add_theme_constant_override("icon_max_width", 30)
	_back.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(go_back)
	add_child(_back)
	resized.connect(_layout)
	hide()


func choose_partner(targets: Array) -> void:
	_targets = targets
	page = "targets"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for owner: int in range(2):
		_headers[owner].hide()
		_lists[owner].hide()
	if not targets.is_empty():
		_highlight(int(targets[0]["id"]))
	show()
	_layout()


func select_target(id: int) -> void:
	if page != "targets":
		return
	for target: Dictionary in _targets:
		if int(target["id"]) == id:
			target_id = id
			intent.emit("partner_selected", {"target": id})
			return


func present(actor: Dictionary, partner: Dictionary) -> void:
	_parties = [actor, partner]
	page = "inventories"
	mouse_filter = Control.MOUSE_FILTER_STOP
	source_locked = false
	_source_owner = -1
	_source_item = ""
	_active_owner = 0
	show()
	_render_inventories()


func go_back() -> void:
	if page == "inventories" and source_locked:
		_active_owner = _source_owner
		source_locked = false
		_source_item = ""
		_render_inventories()
	else:
		hide()
		intent.emit("closed", {})


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if page == "targets":
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			select_target(target_id)
			return true
		if event.keycode in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT] and not _targets.is_empty():
			handle_wheel(-1 if event.keycode in [KEY_UP, KEY_LEFT] else 1)
			return true
	elif event.keycode in [KEY_LEFT, KEY_RIGHT]:
		_focus_owner(1 - _active_owner)
		return true
	return false


func handle_wheel(direction: int) -> void:
	if page == "targets":
		if _targets.is_empty():
			return
		var index: int = 0
		for candidate: int in range(_targets.size()):
			if int(_targets[candidate]["id"]) == target_id:
				index = candidate
		_highlight(int(_targets[posmod(index + direction, _targets.size())]["id"]))
		return
	var rows: Array[Button] = []
	for button: Button in _lists[_active_owner].get_children():
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != FOCUS_NONE:
			rows.append(button)
	MenuNavigation.step_buttons(rows, direction)


func _highlight(id: int) -> void:
	target_id = id
	intent.emit("target_highlight", {"target": id})


func _focus_owner(owner: int) -> void:
	if source_locked and owner == _source_owner:
		return
	_active_owner = owner
	_update_headers()
	var empty: Node = _lists[owner].get_node_or_null("TransferHere")
	if source_locked and empty != null:
		empty.grab_focus()
	elif _lists[owner].get_child_count() > 0:
		_lists[owner].get_child(0).grab_focus()


func _render_inventories() -> void:
	for owner: int in range(2):
		_headers[owner].show()
		_lists[owner].show()
		for child: Node in _lists[owner].get_children():
			_lists[owner].remove_child(child)
			child.queue_free()
		for held: Dictionary in _parties[owner]["inventory"]:
			var definition: Dictionary = _interface["items"][str(int(held["templateId"]))]
			var row: Button = _row(
				owner,
				held["id"],
				definition["name"]["text"],
				str(int(held["durability"])),
				_textures.get(definition["icon"])
			)
			row.name = "Owner%d_Item%d" % [owner, held["templateId"]]
			if source_locked and owner == _source_owner:
				row.focus_mode = Control.FOCUS_NONE
			_lists[owner].add_child(row)
		if (
			source_locked
			and owner != _source_owner
			and _parties[owner]["inventory"].size() < UnitInventory.BAG_CAPACITY
		):
			var empty: Button = _row(owner, "", "（空位）", "", null)
			empty.name = "TransferHere"
			_lists[owner].add_child(empty)
	_focus_owner(_active_owner)
	_layout()


func _row(owner: int, item: String, title: String, durability: String, icon: Texture2D) -> Button:
	var row := Button.new()
	row.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	var active := StyleBoxFlat.new()
	active.bg_color = Color("6888a8")
	row.add_theme_stylebox_override("focus", active)
	row.mouse_entered.connect(row.grab_focus)
	row.focus_entered.connect(_row_focused.bind(owner))
	row.pressed.connect(_choose_item.bind(owner, item))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var picture := TextureRect.new()
	picture.texture = icon
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size.x = 36
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(picture)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)
	var number := Label.new()
	number.text = durability
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(number)
	row.add_child(line)
	return row


func _row_focused(owner: int) -> void:
	_active_owner = owner
	_update_headers()


func _update_headers() -> void:
	for owner: int in range(2):
		_headers[owner].text = _parties[owner]["name"]
		_headers[owner].add_theme_color_override(
			"font_color", Color("40ffbe") if owner == _active_owner else Color.WHITE
		)


func _choose_item(owner: int, item: String) -> void:
	if not source_locked:
		if item.is_empty():
			return
		source_locked = true
		_source_owner = owner
		_source_item = item
		_active_owner = 1 - owner
		_render_inventories()
	elif owner != _source_owner:
		intent.emit(
			"trade",
			{
				"item": _source_item,
				"exchange": item,
				"unit": _parties[_source_owner]["id"],
				"partner": _parties[owner]["id"]
			}
		)


func _layout() -> void:
	if _back == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	var header: float = 19 * factor
	var half: float = (area.size.y - header) / 2
	for owner: int in range(2):
		_headers[owner].position = area.position + Vector2(owner * area.size.x / 2, 0)
		_headers[owner].size = Vector2(area.size.x / 2, header)
		_headers[owner].add_theme_font_size_override("font_size", roundi(12 * factor))
		_lists[owner].position = area.position + Vector2(0, header + owner * half)
		_lists[owner].size = Vector2(area.size.x, half)
		for row: Button in _lists[owner].get_children():
			row.custom_minimum_size.y = 19 * factor
			for label: Node in row.get_child(0).get_children():
				if label is Label:
					label.add_theme_font_size_override("font_size", roundi(12 * factor))
	_back.position = area.end - Vector2(24, 22) * factor
	_back.size = Vector2(24, 22) * factor
	queue_redraw()


func _draw() -> void:
	if page != "inventories":
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var area: Rect2 = PixelTheme.portrait_area(size)
	draw_rect(area, Color("244e83"))
	var header: float = 19 * area.size.x / 240.0
	draw_rect(Rect2(area.position, Vector2(area.size.x, header)), Color("20375c"))
	var separator: float = header + (area.size.y - header) / 2
	draw_line(
		area.position + Vector2(0, separator),
		area.position + Vector2(area.size.x, separator),
		Color("173459"),
		2
	)
