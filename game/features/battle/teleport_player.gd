extends Control

signal completed

const Timeline = preload("res://features/battle/teleport_timeline.gd")
var playing: bool = false
var model: RefCounted
var _map: Control
var _tick_seconds: float
var _elapsed: float = 0
var _destination: Vector2i


func setup(content: Dictionary, tactical_map: Control) -> void:
	_map = tactical_map
	_tick_seconds = float(content["battleClips"]["tickMillis"]) / 1000
	clip_contents = true
	_layout_clip()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	hide()


func play(result: Dictionary) -> Dictionary:
	if playing or result.get("kind") != "teleport":
		return {"ok": false, "error": "INVALID_TELEPORT_PRESENTATION"}
	_destination = Vector2i(result["to"])
	# The domain already committed the final position. This detached map copy
	# exposes ag0 immediately; the ten-update gate only controls presentation.
	var actors: Array = _map.content.get("units", []).duplicate(true)
	var found: bool = false
	for actor: Dictionary in actors:
		if int(actor["id"]) == int(result["target"]):
			actor["x"] = _destination.x
			actor["y"] = _destination.y
			found = true
	if not found:
		return {"ok": false, "error": "MISSING_TELEPORT_TARGET"}
	_map.set_units(actors)
	model = Timeline.new()
	_elapsed = 0
	playing = true
	show()
	set_process(true)
	queue_redraw()
	await completed
	return {"ok": true}


func _process(delta: float) -> void:
	_layout_clip()
	_elapsed += delta
	while _elapsed >= _tick_seconds and playing:
		_elapsed -= _tick_seconds
		model.advance()
		if model.finished:
			playing = false
			set_process(false)
			hide()
			completed.emit()
	queue_redraw()


func _layout_clip() -> void:
	var parent_transform: Transform2D = Transform2D.IDENTITY
	if get_parent() is CanvasItem:
		parent_transform = get_parent().get_global_transform()
	var rect: Rect2 = (
		parent_transform.affine_inverse() * _map.get_global_transform() * _map.content_rect()
	)
	position = rect.position
	size = rect.size


func _draw() -> void:
	if not playing or model.circle_phase < 0:
		return
	var local: Transform2D = get_global_transform().affine_inverse() * _map.get_global_transform()
	var center: Vector2 = local * _map.view.screen_at(Vector2(_destination) + Vector2(0.5, 0.5))
	var zoom: float = _map.view.zoom
	# Native type1 is a clipped24px procedural circle, not an atlas or heal.
	if model.circle_phase < 2:
		var radius: float = 5 if model.circle_phase == 0 else 10
		draw_circle(center, radius * zoom, Color.CYAN)
		draw_circle(center, (radius - 2) * zoom, Color.YELLOW)
	else:
		draw_arc(center, 12 * zoom, 0, TAU, 64, Color.CYAN, zoom)
		draw_arc(center, 11 * zoom, 0, TAU, 64, Color.CYAN, zoom)
