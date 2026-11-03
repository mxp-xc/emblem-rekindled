extends "res://tests/test_m14_session.gd"


func _initialize() -> void:
	if not _route(M10.CONTEXTS[2]):
		return
	print("PASS m14 Session/Store: second route, pickup and completed world cold reads")
	quit(0)
