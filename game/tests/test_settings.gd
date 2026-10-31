extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://persistence/settings_store.gd")
	if script == null:
		quit(1)
		return
	var path := "user://test_settings_%s.json" % str(Time.get_ticks_usec())
	var store: RefCounted = script.new(path)
	if not store.read()["missing"]:
		fail("Absent settings must be distinguished from corrupted data")
		return
	var saved: Dictionary = store.write({"volume": 0.25, "music_enabled": true})
	if not saved["ok"]:
		fail(str(saved))
		return
	var loaded: Dictionary = script.new(path).read()
	if (
		not loaded["ok"]
		or loaded["settings"]["volume"] != 0.25
		or not loaded["settings"]["music_enabled"]
	):
		fail("Settings must survive a new store instance")
		return
	if (
		store.write({"volume": 4.0, "music_enabled": true})["ok"]
		or store.read()["settings"]["volume"] != 0.25
	):
		fail("Invalid values must not replace the last valid settings")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	if store.read()["ok"] or store.read()["missing"]:
		fail("Corrupt data must return an explicit read error")
		return
	if (
		script
		. new("user://missing_directory/settings.json")
		. write({"volume": 0.5, "music_enabled": false})["ok"]
	):
		fail("Write failure must be reported")
		return
	DirAccess.remove_absolute(path)
	print("PASS settings: restore, invalid input preserves previous, corruption, write failure")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
