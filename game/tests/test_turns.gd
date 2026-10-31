extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(limit: int) -> int: return mini(50, limit - 1)
	)
	battle.move_unit(0, Vector2i(8, 15))
	var before: Dictionary = battle.snapshot()
	if battle.end_phase()["ok"] or battle.snapshot() != before:
		fail("End turn cannot discard a pending player move")
		return
	battle.cancel_move()
	if (
		not battle.end_phase()["ok"]
		or battle.phase != 1
		or battle.round_number != 1
		or battle.can_save()
	):
		fail("Player turn must advance to the allied automatic phase, without incrementing round")
		return
	if battle.end_phase()["ok"] or battle.move_unit(0, Vector2i(8, 15))["ok"]:
		fail("Automatic phase cannot be skipped or accept inactive player commands")
		return
	for expected_phase: int in [1, 2]:
		var count: int = 0
		while battle.automatic_actor() >= 0:
			count += 1
			if count > 32:
				fail("Automatic phase must terminate within its finite queue")
				return
			var id: int = battle.automatic_actor()
			var began: Dictionary = battle.begin_automatic_action(id)
			if not began["ok"]:
				fail("Automatic planned move failed: " + str(began))
				return
			before = battle.snapshot()
			if battle.begin_automatic_action(id)["ok"] or battle.snapshot() != before:
				fail("The same automatic move cannot be begun twice")
				return
			var plan: Dictionary = began["plan"]
			var result: Dictionary
			if plan["attackTarget"] >= 0:
				result = battle.attack_unit(id, plan["attackTarget"])
			elif plan["healTarget"] >= 0:
				result = battle.heal_unit(id, plan["healTarget"], plan["healItem"])
			else:
				result = battle.wait_unit(id)
			if not result["ok"] or battle.unit(id)["action"] != 2 or battle.phase != expected_phase:
				fail("An automatic actor must finish exactly one legal action")
				return
		var advanced: Dictionary = battle.end_phase()
		if not advanced["ok"]:
			fail("Completed automatic queue must allow phase advancement: " + str(advanced))
			return
	if (
		battle.phase != 0
		or battle.round_number != 2
		or not battle.can_save()
		or not battle.event_completed("reinforcements")
	):
		fail(
			"Enemy completion must reveal the first-round reinforcements and return to blue round two"
		)
		return
	var occupied: Dictionary = {}
	for unit: Dictionary in battle.snapshot()["units"]:
		if unit["visible"] and unit["hp"] > 0:
			var cell := Vector2i(unit["x"], unit["y"])
			if occupied.has(cell):
				fail("Reinforcements cannot overlap another living unit")
				return
			occupied[cell] = true
		if unit["id"] in [13, 14, 15] and not unit["visible"]:
			fail("First-turn reinforcements must arrive in this unobstructed scenario")
			return
	print("PASS turns: factions, finite actions, reinforcement, stable round two")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
