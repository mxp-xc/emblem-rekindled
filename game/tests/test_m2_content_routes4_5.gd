extends "res://tests/test_m2_content.gd"


func _initialize() -> void:
	_run_contexts(CONTEXTS.slice(2, 4))
