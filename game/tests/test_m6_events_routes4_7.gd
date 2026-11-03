extends "res://tests/test_m6_events.gd"


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(4), false)
