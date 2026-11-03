extends Control

var cell: Vector2i = Vector2i(-1, -1)
var actor: Dictionary = {}
var terrain_values: Dictionary = {}
var _content: Dictionary
var _textures: Dictionary = {}
var _map_texture: Texture2D
var _tile_overlays: Dictionary = {}
var _name: Label
var _place_name: String


func setup(data: Dictionary, place_name: String = "") -> void:
	_content = data.duplicate()
	_place_name = place_name
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = data["entry"]["resourceDirectory"]
	for key: String in data["interface"]["textures"]:
		_textures[key] = load(directory.path_join(data["interface"]["textures"][key]["texture"]))
	_map_texture = load(data["entry"]["mapTexture"])
	_name = _label(Color.WHITE)
	_name.text = place_name
	add_child(_name)
	resized.connect(_layout)


func set_map_state(state: Dictionary) -> void:
	_content["map"] = state["map"].duplicate(true)
	_tile_overlays.clear()
	for overlay: Dictionary in state["overlays"]:
		_tile_overlays[overlay["cell"]] = load(overlay["texture"])
	present(cell, actor)


func present(selected_cell: Vector2i, selected_actor: Dictionary = {}) -> void:
	cell = selected_cell
	actor = selected_actor
	terrain_values = {}
	if (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < _content["map"]["width"]
		and cell.y < _content["map"]["height"]
	):
		var terrain: int = int(_content["map"]["terrain"][cell.y][cell.x])
		terrain_values = {
			"defense": int(_content["rules"]["terrainDefense"][terrain]),
			"avoid": int(_content["rules"]["terrainEvasion"][terrain])
		}
	_name.text = actor.get("name", "")
	_layout()
	queue_redraw()


func present_place(place_name: String) -> void:
	_place_name = place_name
	_name.text = place_name
	actor = {}
	terrain_values = {}
	_layout()
	queue_redraw()


func _layout() -> void:
	if _name == null:
		return
	var factor: float = size.y / 45.0
	_name.position = Vector2(10, 5) * factor
	_name.add_theme_font_size_override("font_size", roundi(12 * factor))
	_name.reset_size()
	if not _place_name.is_empty():
		_name.position = Vector2((size.x - _name.get_minimum_size().x) / 2, 15 * factor)
	queue_redraw()


func _draw() -> void:
	if _textures.is_empty():
		return
	var hud: Dictionary = _content["interface"]["mapHud"]
	var factor: float = size.y / 45.0
	var background: String = (
		"map_hud_enemy_background" if actor.get("faction", -1) == 2 else "map_hud_background"
	)
	draw_texture_rect(_textures[background], Rect2(Vector2.ZERO, size), false)
	for index: int in range(2):
		var corner: Texture2D = _textures["corner_" + str(index)]
		var x: float = 0 if index == 0 else size.x - corner.get_width() * factor
		draw_texture_rect(
			corner,
			Rect2(Vector2(x, -corner.get_height() * factor), corner.get_size() * factor),
			false
		)
	if not actor.is_empty():
		var hp_x: float = maxf(40, 10 + _name.get_minimum_size().x / factor + 5)
		var hp_text: String = "%d/%d" % [actor["hp"], actor["maxHp"]]
		_icon(hud["icons"]["hp"], Vector2(hp_x, 13), factor)
		_number(hp_text, Vector2(hp_x + 28, 15), factor)
		_icon(hud["icons"]["level"], Vector2(10, 31), factor)
		_number(str(int(actor["level"])), Vector2(28, 33), factor)
		var width: int = 28 + hp_text.length() * 7
		var bar := Vector2(hp_x, 28)
		draw_rect(Rect2((bar + Vector2(0, 1)) * factor, Vector2(width, 4) * factor), Color.BLACK)
		draw_rect(
			Rect2((bar + Vector2(1, 0)) * factor, Vector2(width - 2, 6) * factor), Color.BLACK
		)
		draw_rect(
			Rect2((bar + Vector2.ONE) * factor, Vector2(width - 2, 4) * factor), Color("234779")
		)
		if actor["hp"] > 0:
			var filled: int = maxi(
				1, floori(float((width - 2) * int(actor["hp"])) / int(actor["maxHp"]))
			)
			draw_rect(
				Rect2((bar + Vector2.ONE) * factor, Vector2(filled, 4) * factor), Color("ffbe33")
			)
	elif not terrain_values.is_empty():
		var tile_size: int = int(_content["map"]["tileSize"])
		if _tile_overlays.has(cell):
			draw_texture_rect(
				_tile_overlays[cell],
				Rect2(10 * factor, 13 * factor, 24 * factor, 24 * factor),
				false
			)
		else:
			draw_texture_rect_region(
				_map_texture,
				Rect2(10 * factor, 13 * factor, 24 * factor, 24 * factor),
				Rect2(Vector2(cell * tile_size), Vector2.ONE * tile_size)
			)
		var avoid: String = "%+d" % terrain_values["avoid"]
		_icon(hud["icons"]["evasion"], Vector2(34, 24), factor)
		_number(avoid, Vector2(60, 27), factor)
		var defense_x: int = 60 + avoid.length() * 7
		_icon(hud["icons"]["defense"], Vector2(defense_x, 24), factor)
		_number("%+d" % terrain_values["defense"], Vector2(defense_x + 26, 27), factor)


func _icon(key: String, position: Vector2, factor: float) -> void:
	var texture: Texture2D = _textures[key]
	draw_texture_rect(texture, Rect2(position * factor, texture.get_size() * factor), false)


func _number(value: String, position: Vector2, factor: float) -> void:
	var font: Dictionary = _content["interface"]["battleHud"]["numberFont"]
	for character: String in value:
		_icon(font["glyphs"][character], position, factor)
		position.x += int(font["advance"])


func _label(color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	return label
