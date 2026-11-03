extends SceneTree

var rolls: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(scene.content, _roll)
	if not battle.move_unit(95, Vector2i(9, 10))["ok"] or not battle.wait_unit(95)["ok"]:
		fail("A second allied target must reach an adjacent cell through legal commands")
		return
	battle.complete_event("level_tutorial")
	scene.resume_battle(battle)
	var before: Dictionary = battle.snapshot()
	var before_rolls: int = rolls
	scene._show_unit_menu(Vector2i(9, 11))
	var staff: Button = scene.get_node("UnitStatus/Status/Actions/Heal")
	if staff.text != "杖" or not staff.visible:
		fail("The original staff entry must remain available with full-HP adjacent allies")
		return
	staff.pressed.emit()
	await process_frame
	var view: Control = scene.get("target_selection")
	if (
		view == null
		or not view.visible
		or view.action_kind != "heal"
		or view.page != "items"
		or scene.menu_button.visible
	):
		fail("Staff must open the shared item selection with its original description footer")
		return
	var confirm: Button = view.find_child("Confirm", true, false)
	if confirm == null or not confirm.visible:
		fail("The original staff list must retain its left confirmation softkey")
		return
	confirm.pressed.emit()
	if view.page != "targets" or view.target_id < 0 or battle.snapshot() != before:
		fail("Staff confirmation must enter the map without equipping, spending charges or acting")
		return
	if scene.map.movement.size() != 4 or not scene.map.movement.has(Vector2i(9, 12)):
		fail("Staff map targeting must show all four original range-one cells")
		return
	var first: int = view.target_id
	await _key(KEY_RIGHT)
	if view.target_id == first:
		fail("Directions must cycle the real allied target set")
		return
	await _key(KEY_LEFT)
	if view.target_id != first:
		fail("Reverse direction must restore the previous target in source registration order")
		return
	await _key(KEY_ESCAPE)
	if view.page != "items" or not view.visible or not scene.map.movement.is_empty():
		fail("Back from map targeting must return to the staff list")
		return
	await _key(KEY_ESCAPE)
	if (
		view.visible
		or not scene.unit_panel.visible
		or battle.snapshot() != before
		or rolls != before_rolls
		or not scene.menu_button.visible
	):
		fail("Back from staves must return to actions without mutating the pending battle or RNG")
		return
	staff.pressed.emit()
	view.find_child("Staff_0", true, false).pressed.emit()
	scene._show_cell(Vector2i(8, 11))
	await process_frame
	scene.action_feedback.set_process(false)
	if (
		view.visible
		or not scene.busy
		or scene.action_feedback.current_step.get("kind") != "healing"
	):
		fail(
			"Tapping the full-HP map target must immediately cast, with no target list or forecast"
		)
		return
	var committed: Dictionary = battle.snapshot()
	if (
		battle.unit(9)["action"] != 2
		or battle.unit(9)["experience"] != 12
		or battle.unit(0)["hp"] != 30
	):
		fail("The source full-HP cast must settle its action, XP and capped HP once")
		return
	for tick: int in range(60):
		if scene.action_feedback.current_step.get("kind") == "summary":
			scene.action_feedback.go_back()
		else:
			scene.action_feedback.advance()
	await process_frame
	if scene.busy or battle.snapshot() != committed or scene.action_feedback.visible:
		fail("Circle and confirmed growth summary must unlock without replaying settlement")
		return
	var isolated: Dictionary = battle.snapshot()
	for actor: Dictionary in isolated["units"]:
		if actor["id"] == 9:
			actor["x"] = 18
			actor["y"] = 23
			actor["action"] = 0
	if not battle.restore_snapshot(isolated)["ok"]:
		fail("The source isolated-caster boundary must restore as a controlled stable position")
		return
	scene.resume_battle(battle)
	scene._show_unit_menu(Vector2i(18, 23))
	if staff.visible:
		fail(
			"An isolated staff user must not expose the original staff entry without allied targets"
		)
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS staff UI: source entry, item/map target, direction cycle, layered Back, full-HP cast"
	)
	quit(0)


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _roll(limit: int) -> int:
	rolls += 1
	return mini(50, limit - 1)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
