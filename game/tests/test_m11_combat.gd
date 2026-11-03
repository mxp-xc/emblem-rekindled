extends "res://tests/test_m11_events.gd"


# Reuse controlled command boundaries and assertions, execute only combat seams.
func _initialize() -> void:
	_owned = "user://m11_combat_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Fresh combat directory required")
		return
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _roll)
	if not _expect(prepared["ok"], "Prepare combat context"):
		_cleanup()
		return
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m11", prepared["source"], _roll)
	if not _expect(opened["ok"], "Open combat context"):
		_cleanup()
		return
	for boundary: Callable in [_combat, _native_first_flag, _revival, _map_magic, _hero_revival]:
		var forked: Dictionary = _fork(opened)
		if not forked["ok"] or not boundary.call(forked):
			_cleanup()
			return
	_cleanup()
	print("PASS m11 combat: ordinary583/584,first flag,boss/hero80,map49/50/51")
	quit(0)
