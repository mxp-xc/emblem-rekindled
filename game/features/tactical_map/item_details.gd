extends Control

var description_mode: bool = false
var _interface: Dictionary
var _definitions: Dictionary = {}
var _background: Texture2D
var _description: Label
var _stats: GridContainer
var _arrow: Button
var _held: Dictionary
var _derived: Dictionary
var _full_description: String
var _description_pages: Array[String] = []
var _description_page: int = 0


func setup(content: Dictionary) -> void:
	_interface = content["interface"]
	for definition: Dictionary in content["rules"]["itemTemplates"]:
		_definitions[int(definition["id"])] = definition
	var directory: String = content["entry"]["interface"].get_base_dir()
	_background = load(directory.path_join(_interface["textures"]["item_detail_sample"]["texture"]))
	_stats = GridContainer.new()
	_stats.columns = 3
	_stats.add_theme_constant_override("h_separation", 0)
	_stats.add_theme_constant_override("v_separation", 0)
	add_child(_stats)
	for index: int in range(5):
		var label := Label.new()
		label.add_theme_color_override("font_color", Color("fff000"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats.add_child(label)
	_description = Label.new()
	_description.name = "Description"
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_description)
	_arrow = Button.new()
	_arrow.icon = load(directory.path_join(_interface["textures"]["side_arrow_1"]["texture"]))
	_arrow.expand_icon = true
	_arrow.focus_mode = Control.FOCUS_NONE
	_arrow.add_theme_constant_override("icon_max_width", 18)
	_arrow.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_arrow.pressed.connect(cycle)
	_arrow.tooltip_text = "切换物品属性与说明"
	add_child(_arrow)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)


func present(held: Dictionary, derived: Dictionary = {}, description_first: bool = false) -> void:
	_held = held
	_derived = derived
	_description_page = 0
	var template: int = int(held["templateId"])
	description_mode = description_first or (derived.is_empty() and template >= 53)
	_arrow.visible = not derived.is_empty() or template < 53
	var definition: Dictionary = _definitions[template]
	var values: Array
	if not derived.is_empty():
		values = [
			"攻击" + str(derived["attack"]),
			"必杀" + str(derived["critical"]),
			"命中" + str(derived["hit"]),
			"回避" + str(derived["avoid"]),
			"射程" + str(derived["range"])
		]
	else:
		var reach: String = (
			str(int(definition["minRange"]))
			if definition["minRange"] == definition["maxRange"]
			else "%d–%d" % [definition["minRange"], definition["maxRange"]]
		)
		values = [
			"攻击%d" % definition["power"],
			"命中%d" % definition["hit"],
			"必杀%d" % definition["critical"],
			"射程" + reach,
			"耐久%d" % definition["defaultDurability"]
		]
	for index: int in range(values.size()):
		_stats.get_child(index).text = values[index]
	var description: String = _interface["items"][str(template)]["description"]["text"]
	_description.set_meta("source_description", description)
	_full_description = (
		("耐久%d\n" % definition["defaultDurability"] if template >= 53 else "") + description
	)
	_render_mode()
	show()


func cycle() -> void:
	if _derived.is_empty() and int(_held["templateId"]) >= 53:
		_description_page = posmod(_description_page + 1, maxi(1, _description_pages.size()))
	elif description_mode and _description_page + 1 < _description_pages.size():
		_description_page += 1
	else:
		description_mode = not description_mode
		_description_page = 0
	_render_mode()


func _render_mode() -> void:
	_description.visible = description_mode
	_stats.visible = not description_mode
	_layout()


func _layout() -> void:
	if _stats == null:
		return
	var factor: float = size.y / 45.0
	_stats.position = Vector2(2, 0) * factor
	_stats.size = Vector2(size.x - 4 * factor, size.y)
	_description.position = Vector2(2, 0) * factor
	_description.size = Vector2(size.x - 30 * factor, size.y)
	_description.add_theme_font_size_override("font_size", roundi(13 * factor))
	if not _held.is_empty() and size.x > 30 * factor:
		var lines: Array[String] = []
		var font: Font = _description.get_theme_font("font")
		var font_size: int = _description.get_theme_font_size("font_size")
		var available_width: float = size.x - 30 * factor
		for paragraph: String in _full_description.split("\n"):
			var line: String = ""
			for character: String in paragraph:
				var width: float = (
					font
					. get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
					. x
				)
				if width > available_width:
					lines.append(line)
					line = ""
				line += character
			lines.append(line)
		_description_pages.clear()
		for index: int in range(0, lines.size(), 2):
			_description_pages.append("\n".join(lines.slice(index, index + 2)))
		_description_page = mini(_description_page, maxi(0, _description_pages.size() - 1))
		_description.text = _description_pages[_description_page]
		_arrow.visible = (
			not _derived.is_empty()
			or int(_held["templateId"]) < 53
			or _description_pages.size() > 1
		)
	for label: Label in _stats.get_children():
		label.add_theme_font_size_override("font_size", roundi(11 * factor))
	_arrow.position = Vector2(size.x - 18 * factor, 0)
	_arrow.size = Vector2(18, 22) * factor
	queue_redraw()


func _draw() -> void:
	if _background != null:
		draw_texture_rect(_background, Rect2(Vector2.ZERO, size), false)
