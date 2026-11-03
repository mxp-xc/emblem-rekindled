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
	if (
		store.read()["settings"].get("share_experience", false)
		or store.read()["settings"].get("full_growth", false)
		or store.read()["settings"].get("bonus_battle_used", false)
	):
		fail("Missing assistance settings must default to off")
		return
	var saved: Dictionary = store.write({"volume": 0.25, "music_enabled": true})
	if not saved["ok"]:
		fail(str(saved))
		return
	var old_file := FileAccess.open(path, FileAccess.WRITE)
	old_file.store_string('{"version":1,"volume":0.25,"music_enabled":true}')
	old_file.close()
	var legacy: Dictionary = store.read()["settings"]
	if legacy["share_experience"] or legacy["full_growth"] or legacy["bonus_battle_used"]:
		fail("Existing audio-only settings must load with assistance off")
		return
	var assisted: Dictionary = legacy.merged({"share_experience": true, "full_growth": true}, true)
	if not store.write(assisted)["ok"] or script.new(path).read()["settings"] != assisted:
		fail("Both assistance switches must survive a new settings store")
		return
	if store.write(assisted.merged({"full_growth": "true"}, true))["ok"]:
		fail("Invalid assistance switch types must be rejected")
		return
	var used: Dictionary = assisted.merged({"bonus_battle_used": true}, true)
	if (
		not store.write(used)["ok"]
		or not script.new(path).read()["settings"]["bonus_battle_used"]
		or store.write(used.merged({"bonus_battle_used": "true"}, true))["ok"]
	):
		fail("The one-time bonus flag must survive reload and reject invalid values")
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
