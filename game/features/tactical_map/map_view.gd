extends RefCounted

const TILE_PIXELS: int = 24

var grid_size := Vector2i(20, 25)
var viewport_size := Vector2(720, 720)
var viewport_origin := Vector2.ZERO
var center := Vector2(8.5, 11.5)
var zoom: float = 3.0
var pointer_id: int = -1
var pointer_origin := Vector2.ZERO
var pointer_previous := Vector2.ZERO
var dragging: bool = false
var _adaptive: bool = false
var _portrait: bool = true


func configure(
	grid: Vector2i,
	viewport: Vector2,
	origin: Vector2 = Vector2.ZERO,
	display_size: Vector2 = Vector2.ZERO
) -> void:
	grid_size = grid
	viewport_size = viewport
	viewport_origin = origin
	var orientation: Vector2 = (
		display_size if display_size.x > 0 and display_size.y > 0 else viewport
	)
	_portrait = orientation.x <= orientation.y
	if _adaptive:
		fit_to_viewport()
	else:
		zoom = maxf(zoom, minimum_zoom())
	_clamp_center()


func focus_cell(cell: Vector2i) -> void:
	center = Vector2(cell) + Vector2(0.5, 0.5)
	_clamp_center()


func world_at(position: Vector2) -> Vector2:
	return center + (position - viewport_origin - viewport_size / 2.0) / (TILE_PIXELS * zoom)


func cell_at(position: Vector2) -> Vector2i:
	if not Rect2(viewport_origin, viewport_size).has_point(position):
		return Vector2i(-1, -1)
	var cell := Vector2i(world_at(position).floor())
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return Vector2i(-1, -1)
	return cell


func screen_at(world: Vector2) -> Vector2:
	return (world - center) * (TILE_PIXELS * zoom) + viewport_origin + viewport_size / 2.0


func zoom_at(value: float, anchor: Vector2) -> void:
	_adaptive = false
	var world_anchor := world_at(anchor)
	zoom = clampf(value, minimum_zoom(), maxf(6.0, minimum_zoom()))
	center = world_anchor - (anchor - viewport_origin - viewport_size / 2.0) / (TILE_PIXELS * zoom)
	_clamp_center()


func fit_to_viewport() -> void:
	_adaptive = true
	var axis: int = 0 if _portrait else 1
	zoom = maxf(minimum_zoom(), viewport_size[axis] / (grid_size[axis] * float(TILE_PIXELS)))
	_clamp_center()


func minimum_zoom() -> float:
	return maxf(
		0.5, minf(viewport_size.x / grid_size.x, viewport_size.y / grid_size.y) / float(TILE_PIXELS)
	)


func pan_by(delta: Vector2) -> void:
	center -= delta / (TILE_PIXELS * zoom)
	_clamp_center()


func begin_pointer(position: Vector2, id: int) -> void:
	if pointer_id != -1:
		return
	pointer_id = id
	pointer_origin = position
	pointer_previous = position
	dragging = false


func drag_pointer(position: Vector2, id: int) -> void:
	if id != pointer_id or pointer_id == -1:
		return
	if position.distance_to(pointer_origin) > 12.0:
		dragging = true
	if dragging:
		pan_by(position - pointer_previous)
	pointer_previous = position


func end_pointer(position: Vector2, id: int) -> Vector2i:
	if id != pointer_id or pointer_id == -1:
		return Vector2i(-1, -1)
	var was_dragging: bool = dragging or position.distance_to(pointer_origin) > 12.0
	cancel_pointer()
	return Vector2i(-1, -1) if was_dragging else cell_at(position)


func cancel_pointer() -> void:
	pointer_id = -1
	dragging = false


func _clamp_center() -> void:
	var half_view := viewport_size / (2.0 * TILE_PIXELS * zoom)
	for axis: int in [0, 1]:
		if half_view[axis] * 2.0 >= grid_size[axis]:
			center[axis] = grid_size[axis] / 2.0
		else:
			center[axis] = clampf(center[axis], half_view[axis], grid_size[axis] - half_view[axis])
