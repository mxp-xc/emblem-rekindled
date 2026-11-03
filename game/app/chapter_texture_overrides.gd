extends RefCounted

const RESOURCE_FIELDS: Array[String] = ["texture", "sprite", "mapTexture"]


static func read_plan(chapter: Dictionary, library: Dictionary, read_json: Callable) -> Dictionary:
	if not chapter.has("textureOverrides"):
		return {"ok": true, "overrides": {}}
	var path: Variant = chapter["textureOverrides"]
	if (
		not path is String
		or not path.begins_with("res://")
		or path.simplify_path() != path
		or path.get_extension() != "json"
		or not path.contains("/authored/")
	):
		return _failure("图片替换表必须是authored目录内的绝对JSON路径")
	var overrides: Variant = read_json.call(path)
	if not overrides is Dictionary:
		return _failure("图片替换表无法读取: " + path)
	if overrides.is_empty():
		return {"ok": true, "overrides": {}}
	var referenced: Dictionary = {}
	_collect(library, referenced)
	if not chapter.get("battles") is Dictionary:
		return _failure("图片替换表无法核对章内关卡索引")
	for battle_id: Variant in chapter["battles"]:
		if not chapter["battles"][battle_id] is String:
			return _failure("图片替换表无法核对关卡路径: " + str(battle_id))
		var definition: Variant = read_json.call(chapter["battles"][battle_id])
		if (
			not definition is Dictionary
			or definition.get("battleId") != battle_id
			or not definition.get("story") is String
		):
			return _failure("图片替换表无法核对关卡: " + str(battle_id))
		_collect({"mapTexture": definition.get("mapTexture")}, referenced)
		if definition.has("map"):
			var map: Variant = read_json.call(definition["map"])
			if not map is Dictionary:
				return _failure("图片替换表无法核对地图: " + str(battle_id))
			_collect(map.get("tileVariants", {}), referenced)
		var story: Variant = read_json.call(definition.get("story", ""))
		if not story is Dictionary:
			return _failure("图片替换表无法核对剧情: " + str(battle_id))
		_collect(story, referenced)
	var directory: String = path.get_base_dir() + "/"
	for source: Variant in overrides:
		var target: Variant = overrides[source]
		if not _png_path(source) or not _png_path(target):
			return _failure("图片替换只接受规范的绝对res://PNG路径")
		if not referenced.has(source):
			return _failure("图片替换源未被本章引用: " + source)
		if not target.begins_with(directory):
			return _failure("替换图片必须位于替换表的authored目录: " + target)
		var source_size: Vector2i = _size(source)
		var target_size: Vector2i = _size(target)
		if source_size == Vector2i.ZERO or target_size == Vector2i.ZERO:
			return _failure("图片替换资源不存在或不是Texture2D: %s -> %s" % [source, target])
		if source_size != target_size:
			return _failure("替换图片尺寸必须保持一致: %s -> %s" % [source, target])
	return {"ok": true, "overrides": overrides.duplicate(true)}


# Apply exactly once to fresh absolute view data. Never follow a replacement chain.
static func apply(view: Variant, overrides: Dictionary) -> Variant:
	if overrides.is_empty():
		return view
	if view is Dictionary:
		var result: Dictionary = view.duplicate()
		for key: Variant in view:
			var value: Variant = view[key]
			if (
				key is String
				and key in RESOURCE_FIELDS
				and value is String
				and overrides.has(value)
			):
				result[key] = overrides[value]
			else:
				result[key] = apply(value, overrides)
		return result
	if view is Array:
		var result: Array = view.duplicate()
		for index: int in range(view.size()):
			result[index] = apply(view[index], overrides)
		return result
	return view


static func _collect(value: Variant, referenced: Dictionary) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if key is String and key in RESOURCE_FIELDS and _png_path(value[key]):
				referenced[value[key]] = true
			else:
				_collect(value[key], referenced)
	elif value is Array:
		for item: Variant in value:
			_collect(item, referenced)


static func _png_path(path: Variant) -> bool:
	return (
		path is String
		and path.begins_with("res://")
		and path.simplify_path() == path
		and path.get_extension().to_lower() == "png"
	)


static func _size(path: String) -> Vector2i:
	if not ResourceLoader.exists(path, "Texture2D"):
		return Vector2i.ZERO
	var texture: Resource = ResourceLoader.load(path, "Texture2D")
	return Vector2i(texture.get_size()) if texture is Texture2D else Vector2i.ZERO


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
