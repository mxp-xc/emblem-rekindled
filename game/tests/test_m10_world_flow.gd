extends "res://tests/test_m10_flow.gd"


# The inherited _initialize dispatches this concrete run through call_deferred.
# Battle presentation cases remain in test_m10_flow; this file owns world entry/endings.
func run() -> void:
	if not await _begin_flow("world"):
		return
	for context: Dictionary in [Matrix.CONTEXTS[0], Matrix.CONTEXTS[3]]:
		var stage: String = "entry.route%d" % context["route"]
		_stage(stage, "begin")
		if not await _enter(context):
			return
		_stage(stage, "end")
	for context: Dictionary in [Matrix.CONTEXTS[3], Matrix.CONTEXTS[2]]:
		var stage: String = "early" if context["step"] == 5 else "late"
		_stage(stage, "begin")
		if not _adopt(_prepare(context, "last")):
			return
		var gold: int = _scene.battle.gold
		if not await _attack(39, true) or not await _settled(context, gold):
			return
		_stage(stage, "end")
	await _end_flow()
	print("PASS m10 world Main: legal route0/7 entry/cancel,opening/commander9")
	print("PASS m10 world Main: fixed step5/8 endings577+578/579+34 and separate world guidance")
	quit(0)
