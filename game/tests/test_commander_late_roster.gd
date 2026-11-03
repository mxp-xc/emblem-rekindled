extends "res://tests/test_commander_rules.gd"


func _initialize() -> void:
	if not _late_entry():
		return
	print("PASS commander rules: late roster, arrival order, guards and JSON")
	quit(0)
