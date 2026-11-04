extends Node

const Loader = preload("res://app/atlas_texture_loader.gd")
const MANIFEST := "res://content/chapter_1/generated/atlas/manifest.json"

var _loader: ResourceFormatLoader


func _init() -> void:
	var manifest: Dictionary = read_manifest(MANIFEST)
	if not manifest["ok"]:
		push_error(manifest["error"])
		return
	_loader = Loader.new(manifest["textures"])
	ResourceLoader.add_resource_format_loader(_loader, true)


static func read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "人物图集清单不存在: " + path}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if (
		not value is Dictionary
		or value.get("schemaVersion") != 1
		or not value.get("textures") is Dictionary
	):
		return {"ok": false, "error": "人物图集清单无效: " + path}
	return {"ok": true, "textures": value["textures"]}
