extends ResourceFormatLoader

var _textures: Dictionary
var _available: Dictionary = {}


func _init(textures: Dictionary = {}) -> void:
	_textures = textures
	# The chapter snapshot is immutable for the lifetime of the process. Check
	# each physical atlas once rather than once for every projected frame.
	var physical: Dictionary = {}
	for path: String in textures:
		var entry: Variant = textures[path]
		if not entry is Dictionary:
			continue
		var target: Variant = entry.get("texture")
		if not target is String or textures.has(target) or not _valid_region(entry.get("region")):
			continue
		if not physical.has(target):
			var texture: Resource = (
				ResourceLoader.load(target, "Texture2D")
				if ResourceLoader.exists(target, "Texture2D")
				else null
			)
			physical[target] = texture.get_size() if texture is Texture2D else Vector2.ZERO
		var size: Vector2 = physical[target]
		var region: Array = entry["region"]
		if region[0] + region[2] <= size.x and region[1] + region[3] <= size.y:
			_available[path] = true


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["png"])


func _handles_type(type: StringName) -> bool:
	return type in ["", "Resource", "Texture", "Texture2D", "AtlasTexture"]


func _recognize_path(path: String, _type: StringName) -> bool:
	return _textures.has(path)


func _get_resource_type(path: String) -> String:
	return "AtlasTexture" if _textures.has(path) else ""


func _exists(path: String) -> bool:
	return _available.has(path)


func _valid_region(region: Variant) -> bool:
	if not region is Array or region.size() != 4:
		return false
	for value: Variant in region:
		if (
			(not value is int and not value is float)
			or not is_finite(float(value))
			or float(value) != floor(float(value))
			or value < 0
		):
			return false
	return region[2] > 0 and region[3] > 0


func _load(path: String, _original: String, _threads: bool, _mode: int) -> Variant:
	if not _exists(path):
		return ERR_FILE_NOT_FOUND
	var entry: Dictionary = _textures[path]
	var region: Variant = entry.get("region")
	var atlas: Resource = ResourceLoader.load(entry["texture"], "Texture2D")
	if not atlas is Texture2D:
		return ERR_FILE_CORRUPT
	if region[0] + region[2] > atlas.get_width() or region[1] + region[3] > atlas.get_height():
		return ERR_FILE_CORRUPT
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(region[0], region[1], region[2], region[3])
	texture.filter_clip = true
	return texture
