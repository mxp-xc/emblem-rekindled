extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var event_rules: RefCounted = load("res://gameplay/battle_events.gd").new(content)
	var units: Array = content["units"].duplicate(true)
	for unit: Dictionary in units:
		unit["action"] = 0
	var alm: Dictionary
	var celica: Dictionary
	for unit: Dictionary in units:
		if unit["id"] == 0:
			alm = unit
		elif unit["id"] == 9:
			celica = unit
	alm["y"] = 24
	if not event_rules.outcome(units).is_empty():
		fail("Reaching the south row without completing an action cannot trigger escape")
		return
	alm["action"] = 2
	if event_rules.outcome(units).get("reason") != "escaped":
		fail("A completed action at the south row must trigger escape victory")
		return
	alm["y"] = 11
	alm["hp"] = 0
	alm["visible"] = false
	if event_rules.outcome(units).get("unit") != 0:
		fail("Alm's death must end an otherwise active battle")
		return
	alm["hp"] = 30
	alm["visible"] = true
	celica["hp"] = 0
	celica["visible"] = false
	if event_rules.outcome(units).get("unit") != 9:
		fail("Celica's death must also end the battle")
		return
	for unit: Dictionary in units:
		if unit["faction"] == 2:
			unit["hp"] = 0
			unit["visible"] = false
	if event_rules.outcome(units).get("reason") != "all_enemies_defeated":
		fail("Elimination victory must preserve the original priority over simultaneous failure")
		return
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	if not battle.move_unit(0, Vector2i(8, 24))["ok"] or not battle.outcome.is_empty():
		fail("A provisional escape move must remain cancellable")
		return
	battle.cancel_move()
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var before: Dictionary = battle.snapshot()
	if (
		battle.outcome.get("reason") != "escaped"
		or battle.can_save()
		or battle.wait_unit(0)["ok"]
		or battle.end_phase()["ok"]
		or battle.snapshot() != before
	):
		fail("Completed escape must freeze further commands and ordinary battle saves")
		return
	print(
		"PASS outcomes: victories, required deaths, priority, pending cancellation, terminal freeze"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
