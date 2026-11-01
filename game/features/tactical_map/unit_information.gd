extends Control

signal closed

const GOLD := Color("fff000")
const PixelTheme = preload("res://ui/pixel_theme.gd")
const ItemDetails = preload("res://features/tactical_map/item_details.gd")
var page: int = 0
var detail_visible: bool = false
var body: VBoxContainer
var detail: Control
var _heading: Label
var _identity: Label
var _health: Label
var _level: Label
var _experience: Label
var _left: Button
var _right: Button
var _back: Button
var _body_frame: PanelContainer
var _actor: Dictionary
var _combat: Dictionary
var _interface: Dictionary
var _directory: String
var _textures: Dictionary = {}
var _portrait: TextureRect
var _items: Dictionary = {}
var _pointer: int = -2
var _origin: Vector2
var _swiped: bool = false
var _return_focus: Control


func setup(data: Dictionary) -> void:
	_interface = data["interface"]
	_directory = data["entry"]["interface"].get_base_dir()
	for definition: Dictionary in data["rules"]["itemTemplates"]:
		_items[int(definition["id"])] = definition
	for key: String in _interface["textures"]:
		_textures[key] = load(_directory.path_join(_interface["textures"][key]["texture"]))
	name = "UnitInformation"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_identity = _label("")
	_health = _label("")
	_level = _label("")
	_experience = _label("")
	_heading = _label("", GOLD)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for label: Label in [_identity, _health, _level, _experience, _heading]:
		add_child(label)
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	_left = _button("◀", func() -> void: show_page(page - 1))
	_right = _button("▶", func() -> void: show_page(page + 1))
	_left.icon = _textures["side_arrow_0"]
	_right.icon = _textures["side_arrow_1"]
	for arrow: Button in [_left, _right]:
		arrow.expand_icon = true
		arrow.add_theme_constant_override("icon_max_width", 24)
	_left.text = ""
	_right.text = ""
	add_child(_left)
	add_child(_right)
	_body_frame = PanelContainer.new()
	_body_frame.add_theme_stylebox_override("panel", _frame())
	add_child(_body_frame)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	_body_frame.add_child(body)
	detail = ItemDetails.new()
	add_child(detail)
	detail.setup(data)
	_back = _button("", go_back)
	_back.icon = _textures["button_1"]
	_back.expand_icon = true
	_back.add_theme_constant_override("icon_max_width", 30)
	add_child(_back)
	resized.connect(_layout)
	hide()


func present(actor: Dictionary, combat: Dictionary, portrait: Texture2D) -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	_actor = actor
	_combat = combat
	_portrait.texture = portrait
	_identity.text = actor["name"] + " " + actor["className"]
	_health.text = "体力%d/%d" % [actor["hp"], actor["maxHp"]]
	_level.text = "Lv.%d" % actor["level"]
	_experience.text = str(actor["experience"])
	_pointer = -2
	show_page(1)
	show()
	_layout()
	_focus_page_if_needed()


func show_page(index: int) -> void:
	page = posmod(index, 3)
	detail_visible = false
	detail.hide()
	_clear()
	_heading.text = _interface["unitInformation"]["pages"][page]["title"]
	if page < 2:
		for stat: String in _interface["unitInformation"]["pages"][page]["attributes"]:
			var value: Variant
			if page == 0:
				value = _combat["avoid" if stat == "evasion" else stat]
			else:
				var key: String = {"resistance": "magic", "movement": "move"}.get(stat, stat)
				value = _combat["basic"][key]
			var row := HBoxContainer.new()
			row.add_child(_label(_interface["labels"][stat]["text"], GOLD))
			var number: Label = _label(str(value))
			number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(number)
			body.add_child(row)
	else:
		for held: Dictionary in _actor["inventory"]:
			var button: Button = _button("", func() -> void: show_item(held))
			button.name = "Item_" + str(int(held["templateId"]))
			button.set_meta("instance_id", held["id"])
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var metadata: Dictionary = _interface["items"][str(int(held["templateId"]))]
			var icon := TextureRect.new()
			icon.texture = _textures.get(metadata["icon"])
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size.x = 36
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
			var drop: bool = (
				_actor["faction"] == 2 and held["templateId"] == _actor["dropTemplateId"]
			)
			var label: Label = _label(
				_items[int(held["templateId"])]["name"], Color("00dd00") if drop else Color.WHITE
			)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var durability: Label = _label(
				"-" if held["durability"] == 0 else str(held["durability"])
			)
			row.add_child(durability)
			button.add_child(row)
			body.add_child(button)
		if _actor["inventory"].is_empty():
			body.add_child(_label("背包为空"))
	_layout()
	_focus_page_if_needed()


func _focus_page_if_needed() -> void:
	if not is_visible_in_tree():
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or (focused != self and not is_ancestor_of(focused)):
		_right.grab_focus()


func show_item(held: Dictionary) -> void:
	# The original keeps the equipment list and opens a bottom detail strip.
	if page != 2:
		show_page(2)
	for button: Node in body.get_children():
		if button is Button:
			var style: StyleBox = StyleBoxEmpty.new()
			if button.get_meta("instance_id") == held["id"]:
				var highlight := StyleBoxFlat.new()
				highlight.bg_color = Color("6888a8")
				style = highlight
			button.add_theme_stylebox_override("normal", style)
	detail_visible = true
	detail.show()
	detail.present(held, {}, true)
	_layout()


func go_back() -> void:
	if detail_visible:
		detail_visible = false
		detail.hide()
		_layout()
	else:
		hide()
		_pointer = -2
		if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
			_return_focus.grab_focus()
		_return_focus = null
		closed.emit()


func handle_key(_event: InputEventKey) -> bool:
	return false


func handle_wheel(direction: int) -> void:
	if not detail_visible:
		show_page(page + direction)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _pointer == -2:
			_begin_pointer(event.index, event.position)
		elif not event.pressed and event.index == _pointer:
			_end_pointer(event.position)
	elif event is InputEventScreenDrag and event.index == _pointer:
		_track_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(-1, event.position)
		elif _pointer == -1:
			_end_pointer(event.position)
	elif event is InputEventMouseMotion and _pointer == -1:
		_track_pointer(event.position)


func _begin_pointer(id: int, point: Vector2) -> void:
	_pointer = id
	_origin = point
	_swiped = false


func _track_pointer(point: Vector2) -> void:
	var delta := point - _origin
	if absf(delta.x) >= 60 and absf(delta.x) > absf(delta.y) * 1.4:
		_swiped = true
	if _swiped:
		get_viewport().set_input_as_handled()


func _end_pointer(point: Vector2) -> void:
	_track_pointer(point)
	_pointer = -2
	if _swiped:
		show_page(page + (1 if point.x < _origin.x else -1))
		get_viewport().set_input_as_handled()


func _layout() -> void:
	if _body_frame == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var scale_factor: float = area.size.x / 240.0
	var header_height: float = 50 * scale_factor
	_portrait.position = area.position
	_portrait.size = Vector2(48, 48) * scale_factor
	var title_height: float = 19 * scale_factor
	var footer_height: float = 0
	var detail_height: float = 43 * scale_factor if detail_visible else 0
	_identity.position = area.position + Vector2(54, 0) * scale_factor
	_health.position = area.position + Vector2(54, 16) * scale_factor
	_level.position = area.position + Vector2(54, 32) * scale_factor
	_experience.position = area.position + Vector2(130, 16) * scale_factor
	_heading.position = area.position + Vector2(20 * scale_factor, header_height)
	_heading.size = Vector2(area.size.x - 40 * scale_factor, title_height)
	_left.position = area.position + Vector2(0, header_height)
	_right.position = area.position + Vector2(area.size.x - 20 * scale_factor, header_height)
	for button: Button in [_left, _right]:
		button.size = Vector2(20 * scale_factor, title_height)
	_body_frame.position = area.position + Vector2(0, header_height + title_height)
	_body_frame.size = Vector2(
		area.size.x, size.y - _body_frame.position.y - footer_height - detail_height
	)
	detail.position = area.position + Vector2(0, size.y - footer_height - detail_height)
	detail.size = Vector2(area.size.x, detail_height)
	_back.position = area.end - Vector2(24, 22) * scale_factor
	_back.size = Vector2(24, 22) * scale_factor
	_set_font_size(self, roundi(12 * scale_factor))
	for child: Control in body.get_children():
		child.custom_minimum_size.y = 18 * scale_factor
	queue_redraw()


func _draw() -> void:
	if _textures.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var area: Rect2 = PixelTheme.portrait_area(size)
	draw_rect(area, Color("244e83"))
	var factor: float = area.size.x / 240.0
	draw_texture_rect(
		_textures["header_sample"], Rect2(area.position, Vector2(area.size.x, 50 * factor)), false
	)
	draw_rect(
		Rect2(area.position + Vector2(0, 50 * factor), Vector2(area.size.x, 19 * factor)),
		Color("213482")
	)
	draw_texture_rect(
		_textures["experience"],
		Rect2(area.position + Vector2(112, 19) * factor, Vector2(14, 9) * factor),
		false
	)
	var x: float = area.position.x + 84 * factor
	for mask: String in _interface["equipMaskIcons"]:
		if int(mask) & int(_actor.get("equipMask", 0)):
			var texture: Texture2D = _textures[_interface["equipMaskIcons"][mask]]
			draw_texture_rect(texture, Rect2(x, 32 * factor, 12 * factor, 12 * factor), false)
			x += 14 * factor


func _frame() -> StyleBoxTexture:
	var result := StyleBoxTexture.new()
	result.texture = _textures["content_frame"]
	result.set_texture_margin_all(5)
	result.content_margin_left = 18
	result.content_margin_right = 18
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result


func _clear() -> void:
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()


func _label(text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	var normal := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", normal)
	button.pressed.connect(action)
	return button


func _set_font_size(node: Node, font_size: int) -> void:
	if node is Control:
		node.add_theme_font_size_override("font_size", font_size)
	for child: Node in node.get_children():
		_set_font_size(child, font_size)
