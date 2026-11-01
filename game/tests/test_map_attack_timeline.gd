extends SceneTree

const Timeline = preload("res://features/battle/map_attack_timeline.gd")


func _initialize() -> void:
	var result: Dictionary = {
		"hits":
		[
			{"target": 35, "hpBefore": 10, "hpAfter": 0, "hit": true},
			{"target": 33, "hpBefore": 8, "hpAfter": 8, "hit": false}
		]
	}
	result = JSON.parse_string(JSON.stringify(result))
	var before: Dictionary = result.duplicate(true)
	var sprite: Dictionary = {
		"kind": "sprite", "logicalTickUnits": 50, "sequence": [0, 1], "cycles": 2, "stepUnits": 100
	}
	var model := Timeline.new(result, sprite)
	if model.effect_frame() != 0:
		fail("The original two-frame effect must begin on its first sequence frame")
		return
	for tick: int in range(1, 14):
		model.advance()
		if model.hp[35] != 10 or model.hidden.has(35):
			fail("Precomputed damage must not leak before the first 600-unit impact hold")
			return
		if tick == 2 and model.effect_frame() != 1:
			fail("Sprite frames must advance every 100 native logical units")
			return
		if tick == 4 and model.effect_frame() != 0:
			fail("The native sequence must run exactly two complete cycles")
			return
		if tick == 8 and model.effect_frame() != -1:
			fail("Completed effect sprites must stop independently of the damage queue")
			return
	model.advance()
	if model.tick != 14 or model.hp[35] != 0 or model.hidden.has(35) or not model.impact:
		fail(
			"Impact must jump directly to final HP while retaining the dying unit for its hit hold"
		)
		return
	model.advance()
	model.advance()
	if model.hidden.has(35):
		fail("Death cleanup must wait the original 150 logical units after impact")
		return
	model.advance()
	if not model.hidden.has(35) or model.impact:
		fail("Death cleanup must hide the unit after the hit hold without changing business state")
		return
	while model.tick < 29:
		model.advance()
	if model.target_index != 1 or model.hp[33] != 8:
		fail("The next result must wait the 550-unit tail and retain its own original HP")
		return
	while not model.finished and model.tick < 100:
		model.advance()
	if model.tick != 52 or not model.finished or model.hidden.has(33) or result != before:
		fail(
			"A miss must retain HP/visibility and finish the result queue without mutating the result"
		)
		return
	var delayed := Timeline.new(result, sprite)
	delayed.advance()
	for unused: int in range(3):
		delayed.advance(false)
	delayed.advance(true)
	while delayed.tick < 17:
		delayed.advance()
	if delayed.hp[35] != 0:
		fail("Camera readiness must delay, rather than replace, the fixed native impact hold")
		return
	var quake: Dictionary = {
		"kind": "shake",
		"logicalTickUnits": 50,
		"durationUnits": 500,
		"flashUpdates": 5,
		"flashColor": 0,
		"flashOnEven": true
	}
	var shaking := Timeline.new(result, quake)
	if not shaking.shaking() or shaking.flashing():
		fail("Earthquake starts with signed-remainder shake and the native flash update parity")
		return
	shaking.advance()
	if not shaking.flashing():
		fail("The remaining even flash update must produce the original black flash")
		return
	while shaking.tick < 10:
		shaking.advance()
	if shaking.shaking() or shaking.flashing():
		fail(
			"500 logical units and five flash updates must not be treated as pixels or milliseconds"
		)
		return
	print(
		"PASS map attack timeline: original result holds, HP jumps, death, sprite cycles and shake"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
