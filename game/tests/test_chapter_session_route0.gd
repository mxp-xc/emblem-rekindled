extends "res://tests/test_chapter_session.gd"


func _initialize() -> void:
	if not _terminal_routes([0]):
		return
	print("PASS chapter session: route 4 completion and four independent cold-loaded slots")
	quit(0)
