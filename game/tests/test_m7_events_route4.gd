extends "res://tests/test_m7_events.gd"


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(3, 4), false)
