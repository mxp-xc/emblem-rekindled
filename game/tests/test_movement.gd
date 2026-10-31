extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://gameplay/battle_state.gd")
	if script == null:
		quit(1)
		return
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = script.new(content)
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_movement.json")
	)
	for id: int in [0, 9]:
		var field: Dictionary = battle.movement_field(id)
		var expected: Array = oracle["remainingMovement"][str(id)]
		for y: int in range(25):
			for x: int in range(20):
				if field.get(Vector2i(x, y), 0) != int(expected[y][x]):
					fail(
						(
							"Movement disagrees with original method for unit %d at %s"
							% [id, Vector2i(x, y)]
						)
					)
					return
	if battle.preview_move(0, Vector2i(9, 11))["ok"]:
		fail("Allied units may be crossed, but cannot be used as a destination")
		return
	if not battle.move_unit(0, Vector2i(8, 15))["ok"] or battle.unit(0)["y"] != 15:
		fail("Alm must reach the original observed destination")
		return
	if not battle.cancel_move()["ok"] or battle.unit(0)["y"] != 11 or battle.unit(0)["action"] != 0:
		fail("Canceling an ordinary move must restore origin without consuming action")
		return
	var before: Dictionary = battle.snapshot()
	if battle.move_unit(0, Vector2i(8, 16))["ok"] or battle.snapshot() != before:
		fail("Out-of-range movement must fail without changing state")
		return
	if battle.move_unit(10, Vector2i(7, 10))["ok"]:
		fail("Player cannot move a green automatic unit during the blue phase")
		return
	if not battle.move_unit(0, Vector2i(8, 15))["ok"] or not battle.wait_unit(0)["ok"]:
		fail("Move followed by wait must complete the action")
		return
	if battle.unit(0)["action"] != 2 or battle.move_unit(0, Vector2i(8, 14))["ok"]:
		fail("Completed unit must not act twice")
		return
	var detached: Dictionary = battle.unit(9)
	detached["hp"] = 0
	if battle.unit(9)["hp"] != 26:
		fail("A displayed unit snapshot must not mutate authoritative state")
		return
	print("PASS movement: original 1000-cell oracle, alliance, cancel, wait, invalid commands")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
