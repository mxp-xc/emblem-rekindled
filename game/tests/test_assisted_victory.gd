extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = Battle.new(content)
	var before: Dictionary = battle.snapshot()
	if not battle.win_with_assistance()["ok"]:
		fail("An actionable battle must accept assisted victory")
		return
	var won: Dictionary = battle.snapshot()
	if won["outcome"] != {"kind": "victory", "reason": "assistance"}:
		fail("Assistance must enter the existing victory lifecycle")
		return
	won["outcome"] = before["outcome"]
	if won != before:
		fail("Assistance must not fabricate kills, loot, XP, gold or inventory changes")
		return
	if battle.win_with_assistance()["ok"] or battle.can_save():
		fail("An assisted terminal battle must reject duplicate victory and ordinary saves")
		return
	var completed: Dictionary = battle.complete_victory(2)
	var repeated: Dictionary = battle.complete_victory(2)
	if (
		not completed["ok"]
		or repeated["progress"] != completed["progress"]
		or completed["progress"]["gold"] != 6000
		or completed["progress"]["route"] != 2
	):
		fail("Assistance must retain route selection and award normal completion gold exactly once")
		return
	for actor: Dictionary in completed["progress"]["party"]:
		for original: Dictionary in before["units"]:
			if actor["id"] == original["id"] and actor["inventory"] != original["inventory"]:
				fail("Completion must preserve actual held items")
				return
	for scenario: String in ["pending_move", "automatic_phase", "defeat"]:
		battle = Battle.new(content)
		match scenario:
			"pending_move":
				if not battle.move_unit(0, Vector2i(8, 12))["ok"]:
					fail("Test fixture must establish a provisional move")
					return
			"automatic_phase":
				battle.end_phase()
			"defeat":
				battle.outcome = {"kind": "defeat", "reason": "required_unit_fallen", "unit": 0}
		before = battle.snapshot()
		if battle.win_with_assistance()["ok"] or battle.snapshot() != before:
			fail("Assistance must reject %s without changing authority" % scenario)
			return
	print(
		"PASS assisted victory: stable boundary, unchanged inventory, route and single settlement"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
