extends SceneTree

const Document = preload("res://app/json_document.gd")


func _initialize() -> void:
	var path := "user://compressed-document-test.json"
	var data := {"name": "纹章", "items": [1, 2, 3]}
	var compressed := JSON.stringify(data).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var file := FileAccess.open(path + ".gz", FileAccess.WRITE)
	file.store_buffer(compressed)
	file.close()
	var loaded: Variant = Document.read(path)
	if not loaded is Dictionary or loaded.get("name") != "纹章" or int(loaded["items"][2]) != 3:
		fail("A gzip-only document must load with the same values")
		return
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"name":"plain"}')
	file.close()
	if Document.read(path) != {"name": "plain"}:
		fail("The source JSON must take precedence during development")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	file = FileAccess.open(path + ".gz", FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3]))
	file.close()
	if Document.read(path) != null:
		fail("Invalid compressed data must fail to load")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".gz"))
	print("PASS: compressed JSON and source precedence")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
