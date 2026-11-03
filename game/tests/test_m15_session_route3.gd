extends "res://tests/test_m15_session.gd"


func _initialize() -> void:
	if not _route(M11.CONTEXTS[3]):
		return
	print("PASS m15 Session/Store: second route, outcomes and completed world cold reads")
	quit(0)
