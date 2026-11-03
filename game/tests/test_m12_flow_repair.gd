extends "res://tests/test_m12_flow.gd"


func run() -> void:
	_owned = "user://m12_repair_flow_%d" % Time.get_ticks_usec()
	if not _expect(DirAccess.make_dir_absolute(_owned) == OK, "Claim fresh repair Main records"):
		return
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_scene._set_menu_visible(true)
	_scene.menu_layer.show_page("settings")
	_scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	_scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	_scene._set_menu_visible(false)
	var opened: Dictionary = prepare_boundary(Matrix.CONTEXTS[1], 1, "repair")
	if not _expect(
		opened["ok"], "Prepare actual formal1 repair boundary: " + str(opened.get("error"))
	):
		return
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	_scene.selected_unit = 1
	_scene._unit_intent("heal", {})
	var view: Control = _scene.target_selection
	var staff: Button = view.find_child("Staff_0", true, false)
	if not _expect(
		is_instance_valid(staff), "Real m12 staff menu offers inherited class4 formal1's57"
	):
		return
	staff.pressed.emit()
	view.select_target(0)
	if not _expect(view.page == "repair_items", "Actual staff-target flow opens0 held item list"):
		return
	var item: Button = view.find_child("RepairItem_0", true, false)
	if not _expect(is_instance_valid(item), "Actual damaged sword is selectable"):
		return
	item.pressed.emit()
	var deadline: int = Time.get_ticks_msec() + 10000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		if _scene.story_player.dialogue.visible:
			_scene.story_player.advance()
		if _scene.action_feedback.current_step.get("kind") in ["tutorial", "summary"]:
			_scene.action_feedback.go_back()
		await process_frame
	if not _expect(
		(
			not _scene.busy
			and _scene.battle.unit(0)["inventory"][0]["durability"] == 30
			and _scene.battle.unit(1)["inventory"][0]["durability"] == 3
			and _scene.battle.unit(1)["action"] == 2
		),
		"Real m12 staff menu commits57x4→3 and sword1→30, then returns to battle"
	):
		return
	var expected: Dictionary = _scene.battle.snapshot()
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Write actual repaired battle"):
		return
	_scene._show_title()
	_scene.load_game()
	await process_frame
	if not _expect(
		_scene.battle.snapshot() == expected,
		"Main cold load preserves actual repair durability and action"
	):
		return
	_scene.queue_free()
	await process_frame
	_cleanup()
	print("PASS m12 formal1 actual57 staff→target→item flow,repair,cold load")
	quit(0)
