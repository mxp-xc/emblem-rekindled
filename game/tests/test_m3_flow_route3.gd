extends "res://tests/test_m3_flow.gd"


func run() -> void:
	await run_cases([{"context": 1, "route": 3}])
