extends "res://tests/test_m5_flow.gd"


func run() -> void:
	await run_cases([{"context": 3, "route": 4, "target": 70, "events": false}])
