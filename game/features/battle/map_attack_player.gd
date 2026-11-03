extends Control

signal completed

const Timeline = preload("res://features/battle/map_attack_timeline.gd")
const FONT = preload("res://ui/fonts/NotoSansCJKsc-Regular.woff2")
var playing: bool = false
var model: RefCounted
var _content: Dictionary
var _map: Control
var _hud: Control
var _effect: Dictionary
var _result: Dictionary
var _actors: Array
var _final_actors: Array
var _textures: Dictionary = {}
var _elapsed: float = 0
var _tick_seconds: float
var _content_area: Rect2
var _visual_rng := RandomNumberGenerator.new()


func setup(content: Dictionary, tactical_map: Control, hud: Control) -> void:
	_content = content
	_map = tactical_map
	_hud = hud
	_tick_seconds = float(content["battleClips"]["tickMillis"]) / 1000
	_visual_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	hide()


# Run before committing a command. The content boundary validates the effect
# contract; this also loads its actual textures before any gameplay is changed.
func preload_effect(preview: Dictionary) -> Dictionary:
	var reference: Variant = preview.get("mapEffect")
	var effects: Dictionary = _content.get("mapEffects", {})
	if not reference is String or not effects.get(reference) is Dictionary:
		return {"ok": false, "error": "缺少地图魔法表现"}
	var effect: Dictionary = effects[reference]
	if effect["kind"] == "sprite":
		for frame: Dictionary in effect["sprite"]["frames"]:
			var path: String = _content["entry"]["resourceDirectory"].path_join(frame["texture"])
			if not _textures.has(path):
				var texture: Variant = load(path)
				if not texture is Texture2D:
					return {"ok": false, "error": "地图魔法图片无法读取: " + path}
				_textures[path] = texture
	return {"ok": true}


func play(result: Dictionary, final_actors: Array) -> Dictionary:
	var loaded: Dictionary = preload_effect(result)
	if not loaded["ok"]:
		return loaded
	_result = result
	_effect = _content["mapEffects"][result["mapEffect"]]
	_final_actors = final_actors.duplicate(true)
	_actors = final_actors.duplicate(true)
	for index: int in range(_actors.size()):
		for retirement: Dictionary in result.get("retirements", []):
			if _actors[index]["id"] == retirement["unitId"]:
				_actors[index] = retirement["before"].duplicate(true)
		for before: Dictionary in result["participants"]:
			if _actors[index]["id"] == before["id"]:
				_actors[index] = before.duplicate(true)
	model = Timeline.new(result, _effect)
	if model.finished:
		return {"ok": false, "error": "地图魔法没有结果"}
	_elapsed = 0
	playing = true
	_map.set_units(_actors)
	show()
	set_process(true)
	await completed
	return {"ok": true}


func set_content_area(area: Rect2) -> void:
	_content_area = area
	queue_redraw()


func handle_key(event: InputEventKey) -> bool:
	return event.pressed


func handle_wheel(_direction: int) -> void:
	pass


func go_back() -> void:
	pass


func _process(delta: float) -> void:
	if not playing:
		return
	_elapsed += delta
	while _elapsed >= _tick_seconds and playing:
		_elapsed -= _tick_seconds
		model.advance()
		if model.finished:
			playing = false
			_map.presentation_offset = Vector2.ZERO
			_map.set_units(_final_actors)
			set_process(false)
			hide()
			completed.emit()
			return
		_refresh_display()
	if model.shaking():
		_map.presentation_offset = Vector2(
			_signed_remainder(int(_effect["shakeModuli"][0])),
			_signed_remainder(int(_effect["shakeModuli"][1]))
		)
	else:
		_map.presentation_offset = Vector2.ZERO
	_map.queue_redraw()
	queue_redraw()


func _refresh_display() -> void:
	var current: Dictionary = model.current_hit()
	var target: int = int(current["target"])
	for actor: Dictionary in _actors:
		var id: int = int(actor["id"])
		if model.hp.has(id):
			actor["hp"] = model.hp[id]
		if model.hidden.has(id):
			actor["visible"] = false
		if id == target:
			var cell := Vector2i(actor["x"], actor["y"])
			if model.phase == "camera":
				# Modern tactical-map focus is immediate; the native timeline's
				# camera wait is separate from the original fixed result holds.
				_map.view.focus_cell(cell)
				_map.selected = cell
				_map.view_changed.emit()
			_hud.present(cell, actor)
	_map.set_units(_actors)


func _signed_remainder(modulus: int) -> int:
	var value: int = int(_visual_rng.randi())
	if value >= 2147483648:
		value -= 4294967296
	return value % modulus


func _draw() -> void:
	if not playing:
		return
	var clip: Rect2 = _map.content_rect()
	if _content_area.has_area():
		clip = clip.intersection(_content_area)
	if not clip.has_area():
		return
	if _effect["kind"] == "sprite":
		var index: int = model.effect_frame()
		if index >= 0:
			_draw_effect(index, clip)
	if model.flashing():
		draw_rect(clip, Color.hex((int(_effect["flashColor"]) << 8) | 255))
	if model.impact:
		var hit: Dictionary = model.current_hit()
		for actor: Dictionary in _actors:
			if actor["id"] != hit["target"]:
				continue
			var point: Vector2 = _map.view.screen_at(Vector2(actor["x"] + 0.5, actor["y"]))
			var text: String = str(int(hit["damage"])) if hit["hit"] else "MISS"
			var font_size: int = clampi(roundi(10 * _map.view.zoom), 20, 36)
			var width: float = FONT.get_string_size(text, 0, -1, font_size).x
			point.x = clampf(
				point.x - width / 2, clip.position.x, maxf(clip.position.x, clip.end.x - width)
			)
			point.y = clampf(point.y, clip.position.y + font_size, clip.end.y)
			draw_string(
				FONT, point, text, 0, -1, font_size, Color.WHITE if hit["hit"] else Color.YELLOW
			)


func _draw_effect(index: int, clip: Rect2) -> void:
	var sprite: Dictionary = _effect["sprite"]
	var frame: Dictionary = sprite["frames"][index]
	var texture: Texture2D = _textures[_content["entry"]["resourceDirectory"].path_join(
		frame["texture"]
	)]
	var zoom: float = _map.view.zoom
	for actor: Dictionary in _result["participants"]:
		if actor["id"] not in _result["targetIds"]:
			continue
		var anchor := Vector2(
			int(_effect["unitOffset"][0]) - int(float(sprite["virtualWidth"]) / 2),
			float(_effect["unitOffset"][1]) - float(sprite["virtualHeight"])
		)
		var origin: Vector2 = _map.view.screen_at(Vector2(actor["x"], actor["y"]))
		origin += (anchor + Vector2(frame["offsetX"], frame["offsetY"])) * zoom
		if model.tick < int(_effect["shakeUpdates"]):
			origin += (
				Vector2(
					_visual_rng.randi_range(
						int(_effect["jitterRangeX"][0]), int(_effect["jitterRangeX"][1])
					),
					_visual_rng.randi_range(
						int(_effect["jitterRangeY"][0]), int(_effect["jitterRangeY"][1])
					)
				)
				* zoom
			)
		var destination := Rect2(origin, texture.get_size() * zoom)
		var visible: Rect2 = destination.intersection(clip)
		if visible.has_area():
			var source := Rect2((visible.position - origin) / zoom, visible.size / zoom)
			draw_texture_rect_region(texture, visible, source)
