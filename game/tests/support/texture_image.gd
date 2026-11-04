extends RefCounted

static var _atlas_images: Dictionary = {}


# Original fixtures remain raw PNGs; chapter textures can be atlas-backed paths.
static func read(source: Variant) -> Image:
	if source is Texture2D:
		return source.get_image()
	if not source is String:
		return null
	var path: String = "res://" + source.trim_prefix("res://")
	if FileAccess.file_exists(path):
		return Image.load_from_file(ProjectSettings.globalize_path(path))
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	if not _atlas_images.has(path):
		var texture: Resource = ResourceLoader.load(path, "Texture2D")
		if not texture is Texture2D:
			return null
		_atlas_images[path] = texture.get_image()
	return _atlas_images[path].duplicate()
