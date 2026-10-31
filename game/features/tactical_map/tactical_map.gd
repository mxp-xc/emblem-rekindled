extends Control

signal cell_selected(cell: Vector2i)
signal cell_double_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)
signal empty_clicked
signal interacted
signal view_changed

const View = preload("res://features/tactical_map/map_view.gd")
const FONT = preload("res://ui/fonts/NotoSansCJKsc-Regular.otf")
const FIELD_COLORS: Dictionary = {
	"move": Color("297dcc"),
	"enemy": Color("e05264"),
	"attack": Color("e01d65"),
	"heal": Color("23b998"),
	"trade": Color("dcad3c")
}
var view: RefCounted = View.new()
var content: Dictionary = {}
var selected := Vector2i(-1, -1)
var map_texture: Texture2D
var animation_frames: Dictionary = {}
var completed_frames: Dictionary = {}
var frame_indices: Dictionary = {}
var last_ticks: Dictionary = {}
var animation_clock: float = 0.0
var touches: Dictionary = {}
var was_multitouch: bool = false
var movement: Dictionary = {}
var range_kind: String = "move"
var target_cells: Array[Vector2i] = []
var route: Array = []
var hovered := Vector2i(-1, -1)
var action_hint: String = ""
var animation_positions: Dictionary = {}
var presentation_hidden_ids: Array = []
var presentation_hidden_factions: Array = []
var presentation_revealed_ids: Array = []
var presentation_positions: Dictionary = {}
var selection_enabled: bool = true
var last_tap_cell := Vector2i(-1, -1)
var last_tap_ms: int = -1000
var play_area: Rect2
var _range_textures: Dictionary = {}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_resize)
	mouse_exited.connect(
		func() -> void:
			hovered = Vector2i(-1, -1)
			queue_redraw()
	)
	_resize()


func setup(data: Dictionary) -> void:
	content = data.duplicate()
	map_texture = load(data["entry"]["mapTexture"])
	for kind: String in FIELD_COLORS:
		var color: Color = FIELD_COLORS[kind]
		var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for y: int in range(1, 23):
			for x: int in range(1, 23):
				image.set_pixel(x, y, color if (x + y) % 2 == 0 else Color(color, 0.25))
		_range_textures[kind] = ImageTexture.create_from_image(image)
	for unit: Dictionary in data["units"]:
		var id: int = int(unit["id"])
		var definition: Dictionary = data["mapAnimations"]["units"][str(id)]
		var directory: String = data["entry"]["mapAnimations"].get_base_dir()
		var frames: Array[Texture2D] = []
		for frame: Dictionary in definition["frames"]:
			frames.append(load(directory.path_join(frame["texture"])))
		animation_frames[id] = frames
		completed_frames[id] = load(directory.path_join(definition["completedFrame"]["texture"]))
		frame_indices[id] = 0
		last_ticks[id] = animation_clock
	_resize()
	view.focus_cell(Vector2i(8, 11))
	queue_redraw()


func _process(delta: float) -> void:
	if content.is_empty() or not is_visible_in_tree():
		return
	animation_clock += delta
	var changed: bool = false
	for unit: Dictionary in content["units"]:
		if not unit["visible"] or unit.get("action", 0) == 2:
			continue
		var id: int = int(unit["id"])
		var definition: Dictionary = content["mapAnimations"]["units"][str(id)]
		var moving: bool = animation_positions.has(id)
		var step: float = float(
			definition["walkStepSeconds"] if moving else definition["idleStepSeconds"]
		)
		if animation_clock - float(last_ticks[id]) >= step:
			var sequence: Array = (
				definition["walkSequence"] if moving else definition["idleSequence"]
			)
			frame_indices[id] = (int(frame_indices[id]) + 1) % sequence.size()
			last_ticks[id] = animation_clock
			changed = true
	if changed:
		queue_redraw()


func _resize() -> void:
	var grid := Vector2i(20, 25)
	if not content.is_empty():
		grid = Vector2i(content["map"]["width"], content["map"]["height"])
	var area: Rect2 = play_area if play_area.has_area() else Rect2(Vector2.ZERO, size)
	view.configure(grid, area.size, area.position)
	view_changed.emit()
	queue_redraw()


func set_play_area(area: Rect2) -> void:
	play_area = area
	_resize()


func set_zoom(value: float) -> void:
	view.zoom_at(value, view.viewport_origin + view.viewport_size / 2.0)
	view_changed.emit()
	queue_redraw()


func focus_hero(select_unit: bool = true) -> void:
	var cell := Vector2i(-1, -1)
	for unit: Dictionary in content["units"]:
		if unit["id"] == 0:
			cell = Vector2i(unit["x"], unit["y"])
	if cell.x < 0:
		return
	view.focus_cell(cell)
	if select_unit:
		selected = cell
		cell_selected.emit(cell)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_gesture()


func cancel_gesture() -> void:
	view.cancel_pointer()
	touches.clear()
	was_multitouch = false
	last_tap_cell = Vector2i(-1, -1)
	hovered = Vector2i(-1, -1)


func set_units(units: Array) -> void:
	content["units"] = units
	queue_redraw()


func set_movement_field(field: Dictionary, kind: String = "move") -> void:
	movement = field
	range_kind = kind
	target_cells.clear()
	action_hint = ""
	queue_redraw()


func set_action_field(field: Dictionary, targets: Array, kind: String) -> void:
	set_movement_field(field, kind)
	for target: Dictionary in targets:
		target_cells.append(Vector2i(target["x"], target["y"]))
	action_hint = {"attack": "选择攻击目标", "heal": "选择治疗目标", "trade": "选择交换对象"}.get(kind, "")
	queue_redraw()


func preview_route(path: Array) -> void:
	route = path.duplicate()
	queue_redraw()


func play_move(id: int, path: Array) -> void:
	if path.is_empty():
		return
	preview_route(path)
	animation_positions[id] = Vector2(path[0])
	var tween := create_tween()
	for index: int in range(1, path.size()):
		tween.tween_method(
			func(position: Vector2) -> void:
				animation_positions[id] = position
				queue_redraw(),
			Vector2(path[index - 1]),
			Vector2(path[index]),
			2 * float(content["battleClips"]["tickMillis"]) / 1000
		)
	if path.size() > 1:
		await tween.finished
	else:
		tween.kill()
	animation_positions.erase(id)
	route.clear()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				view.begin_pointer(event.position, 1000)
			else:
				_select(view.end_pointer(event.position, 1000))
	elif event is InputEventMouseMotion:
		view.drag_pointer(event.position, 1000)
		hovered = view.cell_at(event.position) if not view.dragging else Vector2i(-1, -1)
		cell_hovered.emit(hovered)
	elif event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			touches[event.index] = event.position
			if touches.size() == 1 and not was_multitouch:
				view.begin_pointer(event.position, event.index)
			else:
				view.cancel_pointer()
				was_multitouch = true
				last_tap_cell = Vector2i(-1, -1)
		else:
			touches.erase(event.index)
			if event.canceled:
				view.cancel_pointer()
			elif not was_multitouch:
				_select(view.end_pointer(event.position, event.index))
			if touches.is_empty():
				view.cancel_pointer()
				was_multitouch = false
	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		touches[event.index] = event.position
		if not was_multitouch:
			view.drag_pointer(event.position, event.index)
	else:
		return
	interacted.emit()
	view_changed.emit()
	accept_event()
	queue_redraw()


func _select(cell: Vector2i) -> void:
	if cell.x < 0 or not selection_enabled:
		if cell.x < 0 and selection_enabled:
			empty_clicked.emit()
		last_tap_cell = Vector2i(-1, -1)
		return
	var now: int = Time.get_ticks_msec()
	if cell == last_tap_cell and now - last_tap_ms <= 350:
		last_tap_cell = Vector2i(-1, -1)
		cell_double_clicked.emit(cell)
	else:
		last_tap_cell = cell
		last_tap_ms = now
		cell_selected.emit(cell)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111e24"))
	if content.is_empty() or map_texture == null:
		return
	var tile_pixels: float = 24.0 * view.zoom
	var origin: Vector2 = view.screen_at(Vector2.ZERO)
	draw_texture_rect(map_texture, Rect2(origin, Vector2(view.grid_size) * tile_pixels), false)
	for cell: Vector2i in movement:
		_draw_field_cell(origin + Vector2(cell) * tile_pixels)
	if route.size() > 1:
		var points := PackedVector2Array()
		for cell: Vector2i in route:
			points.append(view.screen_at(Vector2(cell) + Vector2.ONE / 2))
		draw_polyline(points, Color("302d56"), 10 * view.zoom)
		draw_polyline(points, Color("9b88ff"), 6 * view.zoom)
	for unit: Dictionary in visible_units():
		var world: Vector2 = animation_positions.get(
			unit["id"], presentation_positions.get(unit["id"], Vector2(unit["x"], unit["y"]))
		)
		var position := world * tile_pixels + origin
		var offset: Vector2 = Vector2(unit["spriteOffsetX"], unit["spriteOffsetY"]) * view.zoom
		var id: int = int(unit["id"])
		var definition: Dictionary = content["mapAnimations"]["units"][str(id)]
		var sequence: Array = (
			definition["walkSequence"]
			if animation_positions.has(id)
			else definition["idleSequence"]
		)
		var texture: Texture2D = (
			completed_frames[id]
			if unit.get("action", 0) == 2
			else animation_frames[id][int(sequence[int(frame_indices[id]) % sequence.size()])]
		)
		draw_texture_rect(texture, Rect2(position + offset, Vector2(64, 64) * view.zoom), false)
	for cell: Vector2i in target_cells:
		_draw_cursor(cell, Color("ffe48c"), false)
	if selected.x >= 0:
		_draw_cursor(selected, Color("ff7557"), selected in target_cells)
	if hovered.x >= 0 and hovered != selected and selection_enabled:
		_draw_cursor(hovered, Color("ffe773"), hovered in target_cells)
	if not action_hint.is_empty():
		var area: Rect2 = content_rect()
		var font_size: int = clampi(roundi(12 * view.zoom), 18, 28)
		var width: float = minf(
			area.size.x - 16, FONT.get_string_size(action_hint, 0, -1, font_size).x + 24
		)
		var panel := Rect2(
			area.get_center().x - width / 2, area.position.y + 8, width, font_size + 16
		)
		draw_rect(panel, Color("1c345f"))
		draw_rect(panel, Color("d5e6ec"), false, 2)
		draw_string(
			FONT, panel.position + Vector2(12, font_size + 3), action_hint, 0, -1, font_size
		)


func _draw_field_cell(position: Vector2) -> void:
	var color: Color = FIELD_COLORS.get(range_kind, FIELD_COLORS["move"])
	var rect := Rect2(position + Vector2.ONE * view.zoom, Vector2.ONE * 22 * view.zoom)
	draw_texture_rect(
		_range_textures.get(range_kind, _range_textures["move"]),
		Rect2(position, Vector2.ONE * 24 * view.zoom),
		false
	)
	draw_rect(rect, Color(color.lightened(0.35), 0.9), false, maxf(1, view.zoom))


func _draw_cursor(cell: Vector2i, color: Color, target: bool) -> void:
	var rect := Rect2(view.screen_at(Vector2(cell)), Vector2.ONE * 24 * view.zoom).grow(-view.zoom)
	var width: float = maxf(2, 2 * view.zoom)
	for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.ONE]:
		var point: Vector2 = rect.position + rect.size * corner
		var direction := Vector2(1 if corner.x == 0 else -1, 1 if corner.y == 0 else -1)
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
			var end: Vector2 = point + direction * axis * 7 * view.zoom
			draw_line(point, end, Color("342438"), width + 2 * view.zoom)
			draw_line(point, end, color, width)
	if target:
		var center: Vector2 = rect.get_center()
		for direction: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2.ONE]:
			draw_line(
				center + direction * 3 * view.zoom,
				center + direction * 8 * view.zoom,
				Color("342438"),
				width + 2 * view.zoom
			)
			draw_line(
				center + direction * 3 * view.zoom,
				center + direction * 8 * view.zoom,
				Color("ff4964"),
				width
			)


func prepare_opening(definition: Dictionary) -> void:
	clear_presentation()
	for id: Variant in definition["hiddenUnitIds"]:
		presentation_hidden_ids.append(int(id))
	for faction: Variant in definition["hiddenFactions"]:
		presentation_hidden_factions.append(int(faction))
	for id: String in definition["unitPositionOverrides"]:
		var cell: Array = definition["unitPositionOverrides"][id]
		presentation_positions[int(id)] = Vector2(cell[0], cell[1])
	queue_redraw()


func visible_units() -> Array:
	var result: Array = []
	for unit: Dictionary in content.get("units", []):
		if (
			unit["visible"]
			and unit["id"] not in presentation_hidden_ids
			and (
				unit["faction"] not in presentation_hidden_factions
				or unit["id"] in presentation_revealed_ids
			)
		):
			result.append(unit)
	return result


func clear_presentation() -> void:
	presentation_hidden_ids.clear()
	presentation_hidden_factions.clear()
	presentation_revealed_ids.clear()
	presentation_positions.clear()
	animation_positions.clear()
	queue_redraw()


func show_overview() -> void:
	view.zoom_at(view.minimum_zoom(), view.viewport_origin + view.viewport_size / 2.0)
	view.center = Vector2(view.grid_size) / 2.0
	view_changed.emit()
	queue_redraw()


func content_rect() -> Rect2:
	var rendered := Rect2(view.screen_at(Vector2.ZERO), Vector2(view.grid_size) * 24 * view.zoom)
	return rendered.intersection(Rect2(view.viewport_origin, view.viewport_size))
