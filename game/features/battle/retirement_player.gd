extends Control

signal completed

const Timeline = preload("res://features/battle/retirement_timeline.gd")
var playing: bool = false
var model: RefCounted
var _content: Dictionary
var _map: Control
var _effects: Dictionary
var _textures: Dictionary = {}
var _active: Array[Dictionary] = []
var _revival: Dictionary = {}
var _revival_actors: Array = []
var _tick_seconds: float


func setup(content: Dictionary, tactical_map: Control) -> void:
	_content = content
	_map = tactical_map
	playing = false
	model = null
	_active.clear()
	_revival.clear()
	_revival_actors.clear()
	_textures.clear()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	hide()


static func validate_definition(art: Dictionary, directory: String) -> bool:
	if not art.get("effects") is Dictionary:
		return false
	for kind: String in ["bomb", "smoke"]:
		var sprite: Variant = art["effects"].get(kind)
		if not sprite is Dictionary:
			return false
		for field: String in ["virtualWidth", "virtualHeight"]:
			if not _integer(sprite.get(field)) or sprite[field] <= 0:
				return false
		if not sprite.get("frames") is Array or sprite["frames"].is_empty():
			return false
		for frame: Variant in sprite["frames"]:
			if not frame is Dictionary:
				return false
			if (
				not frame.get("texture") is String
				or frame["texture"].is_empty()
				or not ResourceLoader.exists(directory.path_join(frame["texture"]))
			):
				return false
			for field: String in ["offsetX", "offsetY", "width", "height"]:
				if not _integer(frame.get(field)):
					return false
			if frame["width"] <= 0 or frame["height"] <= 0:
				return false
			var texture: Variant = load(directory.path_join(frame["texture"]))
			if not texture is Texture2D:
				return false
			if texture.get_size() != Vector2(frame["width"], frame["height"]):
				return false
	return true


func preflight() -> Dictionary:
	var art: Variant = _content.get("battleArt")
	var entry: Variant = _content.get("entry")
	var clips: Variant = _content.get("battleClips")
	if (
		not art is Dictionary
		or not entry is Dictionary
		or not entry.get("resourceDirectory") is String
		or not clips is Dictionary
		or not _integer(clips.get("tickMillis"))
		or clips["tickMillis"] <= 0
	):
		return {"ok": false, "error": "缺少地图退场表现或时钟定义"}
	var directory: String = entry["resourceDirectory"]
	if not validate_definition(art, directory):
		return {"ok": false, "error": "地图退场爆点或烟雾定义无效"}
	for kind: String in ["bomb", "smoke"]:
		for frame: Dictionary in art["effects"][kind]["frames"]:
			var path: String = directory.path_join(frame["texture"])
			if not _textures.has(path):
				_textures[path] = load(path)
	_effects = art["effects"]
	_tick_seconds = float(clips["tickMillis"]) / 1000
	return {"ok": true}


func play(unit: Dictionary) -> Dictionary:
	return await _play(unit, {})


func play_revival(unit: Dictionary, revival: Dictionary) -> Dictionary:
	return await _play(unit, revival)


func _play(unit: Dictionary, revival: Dictionary) -> Dictionary:
	if playing:
		return {"ok": false, "error": "地图退场尚未通过等待阶段"}
	var loaded: Dictionary = preflight()
	if not loaded["ok"]:
		return loaded
	if not _integer(unit.get("id")) or not _integer(unit.get("x")) or not _integer(unit.get("y")):
		return {"ok": false, "error": "地图退场单位或位置无效"}
	# Always detach from the input and Battle's snapshot. A revival preserves
	# visibility while its HP display waits for the shared smoke gate.
	_revival = unit.duplicate(true) if not revival.is_empty() else {}
	var actors: Array = _map.content.get("units", []).duplicate(true)
	var found: bool = false
	for actor: Dictionary in actors:
		if actor["id"] == unit["id"]:
			actor["visible"] = not revival.is_empty()
			if not revival.is_empty():
				actor["hp"] = int(revival["hpBefore"])
			found = true
	if not found:
		return {"ok": false, "error": "地图退场单位不在显示副本中"}
	_revival_actors = actors
	_map.set_units(actors)
	model = Timeline.new(unit, _effects)
	_active.append({"timeline": model, "elapsed": 0.0})
	playing = true
	show()
	set_process(true)
	queue_redraw()
	await completed
	return {"ok": true}


func _process(delta: float) -> void:
	for index: int in range(_active.size() - 1, -1, -1):
		var state: Dictionary = _active[index]
		var timeline: RefCounted = state["timeline"]
		state["elapsed"] += delta
		while state["elapsed"] >= _tick_seconds and not timeline.finished:
			state["elapsed"] -= _tick_seconds
			timeline.advance()
		if timeline.finished:
			_active.remove_at(index)
	queue_redraw()
	if _active.is_empty():
		set_process(false)
		hide()
	if playing and model.gate_open:
		if not _revival.is_empty():
			for actor: Dictionary in _revival_actors:
				if int(actor["id"]) == int(_revival["id"]):
					actor.merge(_revival, true)
			_map.set_units(_revival_actors)
			_revival.clear()
			_revival_actors = []
		playing = false
		completed.emit()


func _draw() -> void:
	if _active.is_empty():
		return
	var map_to_local: Transform2D = (
		get_global_transform().affine_inverse() * _map.get_global_transform()
	)
	var clip: Rect2 = map_to_local * _map.content_rect()
	if not clip.has_area():
		return
	var zoom: float = _map.view.zoom
	for state: Dictionary in _active:
		var timeline: RefCounted = state["timeline"]
		for kind: String in ["bomb", "smoke"]:
			var index: int = timeline.effect_frame(kind)
			if index < 0:
				continue
			var frame: Dictionary = _effects[kind]["frames"][index]
			var path: String = _content["entry"]["resourceDirectory"].path_join(frame["texture"])
			var texture: Texture2D = _textures[path]
			var anchor: Vector2 = timeline.effect_anchor(kind)
			var point: Vector2 = _map.view.screen_at(anchor / Timeline.TILE_PIXELS)
			point += (Vector2(frame["offsetX"], frame["offsetY"]) + _map.presentation_offset) * zoom
			var destination: Rect2 = map_to_local * Rect2(point, texture.get_size() * zoom)
			var visible: Rect2 = destination.intersection(clip)
			if visible.has_area():
				var ratio: Vector2 = texture.get_size() / destination.size
				var source := Rect2(
					(visible.position - destination.position) * ratio, visible.size * ratio
				)
				draw_texture_rect_region(texture, visible, source)


static func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float) and is_finite(float(value)) and float(value) == int(value)
	)
