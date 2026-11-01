extends Control

const PixelTheme = preload("res://ui/pixel_theme.gd")
var foreground_pass: bool = false
var frame: Dictionary = {}
var _content: Dictionary
var _participants: Dictionary = {}
var _textures: Dictionary = {}
var _art_directory: String
var _clip_directory: String


func setup(data: Dictionary, foreground: bool) -> void:
	_content = data
	foreground_pass = foreground
	_art_directory = data["entry"]["resourceDirectory"]
	_clip_directory = data["entry"]["resourceDirectory"]
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func present(state: Dictionary, participants: Array) -> void:
	frame = state
	_participants.clear()
	for actor: Dictionary in participants:
		_participants[int(actor["id"])] = actor
	queue_redraw()


func _draw() -> void:
	if not foreground_pass:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if frame.is_empty():
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240.0
	var origin := Vector2(area.position.x, (size.y - 320 * factor) / 2)
	if foreground_pass:
		_draw_foreground(area, origin, factor)
	else:
		_draw_background(area, origin, factor)


func _draw_background(area: Rect2, origin: Vector2, factor: float) -> void:
	var sky: Dictionary = frame["sky"]
	var sky_texture: Texture2D = _effect_texture(sky["texture"])
	_draw_clipped(
		sky_texture,
		Rect2(origin + Vector2(sky["x"], sky["y"]) * factor, sky_texture.get_size() * factor),
		area
	)
	var shake := Vector2(frame["backgroundOffset"][0], frame["backgroundOffset"][1])
	for role: String in ["attacker", "defender"]:
		var actor: Dictionary = _participants[int(frame["roles"][role])]
		var terrain: int = int(_content["map"]["terrain"][int(actor["y"])][int(actor["x"])])
		var key: String = _content["battleArt"]["terrainBackgrounds"][str(terrain)]
		var frames: Array = _content["battleArt"]["backgrounds"][key]["frames"]
		var placement: Dictionary = frame["terrainPlacement"][role]
		var start: Vector2 = origin + (Vector2(placement["x"], placement["y"]) + shake) * factor
		var clip := Rect2(start, Vector2(placement["clipWidth"], placement["clipHeight"]) * factor)
		clip = clip.intersection(area)
		for index: int in range(int(placement["tileCount"])):
			var tile: Dictionary = frames[1 if index == int(placement["markedTile"]) else index]
			var texture: Texture2D = _texture(_art_directory.path_join(tile["texture"]))
			var offset := Vector2(
				placement["offsetX"] + index * placement["tileWidth"] + tile["offsetX"],
				tile["offsetY"]
			)
			_draw_clipped(
				texture, Rect2(start + offset * factor, texture.get_size() * factor), clip
			)


func _draw_foreground(area: Rect2, origin: Vector2, factor: float) -> void:
	for layer: Dictionary in frame["layers"]:
		var texture: Texture2D
		var position := Vector2(layer["x"], layer["y"])
		if layer.has("actor"):
			var pose: Dictionary = _content["battleArt"]["appearances"][layer["appearance"]]["frames"][int(
				layer["frame"]
			)]
			texture = _texture(_art_directory.path_join(pose["texture"]))
			position += Vector2(pose["offsetX"], pose["offsetY"])
		else:
			texture = _effect_texture(layer["texture"])
		# These are already native-side composed frames; they must not be mirrored again.
		_draw_clipped(texture, Rect2(origin + position * factor, texture.get_size() * factor), area)
	if frame["flash"] != null:
		draw_rect(area, Color.hex((int(frame["flash"]) << 8) | 255))


func _draw_clipped(texture: Texture2D, destination: Rect2, clip: Rect2) -> void:
	var visible: Rect2 = destination.intersection(clip)
	if not visible.has_area():
		return
	var ratio: Vector2 = texture.get_size() / destination.size
	var source := Rect2((visible.position - destination.position) * ratio, visible.size * ratio)
	draw_texture_rect_region(texture, visible, source)


func _effect_texture(key: String) -> Texture2D:
	return _texture(_clip_directory.path_join(_content["battleClips"]["textures"][key]["texture"]))


func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]
