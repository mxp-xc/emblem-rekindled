extends "res://tests/test_m11_events.gd"


func _initialize() -> void:
	_owned = "user://m11_occupancy_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Fresh occupancy directory required")
		return
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _roll)
	if not _expect(prepared["ok"], "Prepare occupancy context"):
		_cleanup()
		return
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m11", prepared["source"], _roll)
	if not _expect(opened["ok"], "Open occupancy context") or not _occupied(opened):
		_cleanup()
		return
	_cleanup()
	print("PASS m11 occupancy:44/56 neighbor/blocked,unchanged occupants,cold JSON")
	quit(0)
