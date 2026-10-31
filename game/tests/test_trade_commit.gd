extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var script: Script = load("res://gameplay/battle_state.gd")
	var battle: RefCounted = script.new(content, func(_limit: int) -> int: return 0)
	if not battle.has_method("begin_trade") or not battle.has_method("movement_committed"):
		fail("Entering an original exchange screen must commit the participant position")
		return
	var before: Dictionary = battle.snapshot()
	if battle.begin_trade(0, 10)["ok"] or battle.snapshot() != before:
		fail("An invalid exchange target must not commit a position")
		return
	if not battle.begin_trade(0, 9)["ok"] or not battle.movement_committed(0):
		fail("Entering exchange without a transfer must still lock move cancellation")
		return
	before = battle.snapshot()
	if (
		battle.cancel_move()["ok"]
		or battle.snapshot() != before
		or battle.can_save()
		or battle.end_phase()["ok"]
	):
		fail("An open exchange action cannot undo movement, save or advance a phase")
		return
	if "move" in battle.actions_for(0) or "cancel_move" in battle.actions_for(0):
		fail("A committed exchange action must not advertise a reversible move")
		return
	if (
		not battle.wait_unit(0)["ok"]
		or battle.unit(0)["action"] != 2
		or not battle.can_save()
		or battle.unit(9)["action"] != 0
	):
		fail("Finishing after exchange consumes only the initiating unit action")
		return
	battle = script.new(content, func(_limit: int) -> int: return 0)
	if not battle.move_unit(0, Vector2i(9, 12))["ok"] or not battle.begin_trade(0, 9)["ok"]:
		fail("A legal provisional move must be eligible to enter adjacent exchange")
		return
	var sword: Dictionary = battle.unit(0)["inventory"][0]
	var staff: Dictionary = battle.unit(9)["inventory"][0]
	if not battle.trade_item(0, 9, sword["id"], staff["id"])["ok"]:
		fail("The original exchange must permit holding incompatible equipment")
		return
	before = battle.snapshot()
	if (
		battle.cancel_move()["ok"]
		or battle.snapshot() != before
		or battle.unit(0)["x"] != 9
		or battle.unit(0)["y"] != 12
	):
		fail("A transferred item cannot be carried back by undoing the initiating move")
		return
	if battle.unit(0)["equippedInstanceId"] != "" or battle.unit(9)["equippedInstanceId"] != "":
		fail("Exchange must select usable weapons again without equipping incompatible transfers")
		return
	print("PASS trade commit: empty exchange, position lock, action finish, incompatible swap")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
