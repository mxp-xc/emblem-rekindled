extends "res://tests/test_m11_events.gd"


# Four contexts retain opening/priority/fixed-route settlement; phase tests run once.
func _initialize() -> void:
	_owned = "user://m11_settlement_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Fresh settlement directory required")
		return
	for context: Dictionary in _settlement_contexts():
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare settlement context"):
			_cleanup()
			return
		var opened: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m11", prepared["source"], _roll
		)
		if (
			not _expect(opened["ok"], "Open settlement context")
			or not _opening(opened["content"])
			or not _settlement(opened, context)
			or not _priority(opened)
		):
			_cleanup()
			return
		print("PASS m11 settlement route%d step%d" % [context["route"], context["step"]])
	_cleanup()
	print(
		"PASS m11 settlement scope: required priority,no recruit,1000 once,fixed ending,cold world"
	)
	quit(0)


func _settlement_contexts() -> Array[Dictionary]:
	return [Matrix.CONTEXTS[0], Matrix.CONTEXTS[3]]
