extends SceneTree


func _initialize() -> void:
	var identity: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/build_info.json")
	)
	var args := OS.get_cmdline_user_args()
	if not identity is Dictionary or args.size() != 1 or identity.get("buildId") != args[0]:
		push_error("Exported PCK build identity mismatch")
		quit(1)
		return
	print("PASS PCK build " + identity["buildId"])
	quit()
