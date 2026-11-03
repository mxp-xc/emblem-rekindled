extends "res://tests/test_m11_flow.gd"


func run() -> void:
	if not await _begin_flow("boss"):
		return
	for context: Dictionary in [Matrix.CONTEXTS[0], Matrix.CONTEXTS[1]]:
		if not await _boss_flow(context):
			return
	await _end_flow()
	print("PASS m11 Main boss: first583/cold/death584, both endings and named cold records")
	quit(0)
