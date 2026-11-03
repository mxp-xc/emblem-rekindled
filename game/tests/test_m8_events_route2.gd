extends "res://tests/test_m8_events.gd"


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(1, 2), false)
