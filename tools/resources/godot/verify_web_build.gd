extends SceneTree


func _initialize() -> void:
	var identity: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/build_info.json")
	)
	var args := OS.get_cmdline_user_args()
	if (
		not identity is Dictionary
		or args.size() not in [1, 2]
		or identity.get("buildId") != args[0]
		or (args.size() == 2 and args[1] != "--compressed-catalog")
	):
		push_error("Exported PCK build identity mismatch")
		quit(1)
		return
	if args.size() == 2:
		var catalog_path := "res://content/chapter_1/generated/library/catalog.json"
		if FileAccess.file_exists(catalog_path) or not FileAccess.file_exists(catalog_path + ".gz"):
			push_error("Exported PCK must contain the compressed catalog only")
			quit(1)
			return
		var document: GDScript = load("res://app/json_document.gd")
		if document == null:
			push_error("Exported PCK cannot load the compressed catalog reader")
			quit(1)
			return
		var catalog: Variant = document.read(catalog_path)
		if not catalog is Dictionary or not catalog.get("profiles") is Dictionary:
			push_error("Exported PCK compressed catalog is invalid")
			quit(1)
			return
	print("PASS PCK build " + identity["buildId"])
	quit()
