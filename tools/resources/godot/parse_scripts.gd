extends SceneTree


func _initialize() -> void:
	var scripts := OS.get_cmdline_user_args()
	for path: String in scripts:
		var script := load(path) as Script
		if script == get_script():
			continue
		if script == null or script.reload() != OK:
			push_error("Cannot parse " + path)
			quit(1)
			return
	print("PASS parsed %d scripts" % scripts.size())
	quit()
