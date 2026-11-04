extends SceneTree


func _initialize() -> void:
	var scripts := OS.get_cmdline_user_args()
	for path: String in scripts:
		var script := load(path) as Script
		if script == get_script():
			continue
		if script == null:
			push_error("Cannot parse " + path)
			quit(1)
			return
		# Autoloads and their resource loaders already have live instances.
		# Preserve those instances while checking the script can be reloaded.
		if script.reload(true) != OK:
			push_error("Cannot parse " + path)
			quit(1)
			return
	print("PASS parsed %d scripts" % scripts.size())
	quit()
