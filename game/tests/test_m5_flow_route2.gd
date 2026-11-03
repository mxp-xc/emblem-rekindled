extends "res://tests/test_m5_flow.gd"


func run() -> void:
	await run_cases([{"context": 2, "route": 2, "target": 70, "events": false}])
