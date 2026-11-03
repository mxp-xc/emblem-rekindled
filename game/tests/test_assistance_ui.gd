extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._set_menu_visible(true)
	var menu: Control = scene.menu_layer
	if _button(menu, "辅助功能") != null:
		fail("Title settings must not expose battlefield assistance")
		return

	scene.resume_battle(scene.battle)
	scene._set_menu_visible(true)
	_button(menu, "辅助功能").pressed.emit()
	if menu.page != "assistance" or _button(menu, "直接通关").disabled:
		fail("A stable battlefield must enable assisted completion")
		return
	var before: Dictionary = scene.battle.snapshot()
	_button(menu, "直接通关").pressed.emit()
	if menu.page != "confirm_victory" or scene.battle.snapshot() != before:
		fail("Choosing assistance must only open confirmation, without changing battle state")
		return
	_button(menu, "取消").pressed.emit()
	if menu.page != "assistance" or scene.battle.snapshot() != before:
		fail("Cancel must return to assistance without changing state")
		return
	_button(menu, "直接通关").pressed.emit()
	for expected: String in ["assistance", "main"]:
		var back := InputEventKey.new()
		back.keycode = KEY_ESCAPE
		back.pressed = true
		Input.parse_input_event(back)
		await process_frame
		if not menu.visible or menu.page != expected:
			fail("Esc must cancel exactly one assistance level: " + expected)
			return
	scene._handle_back()
	if menu.visible or scene.battle.snapshot() != before:
		fail("The final back must close the menu without committing assistance")
		return
	scene.busy = true
	scene._set_menu_visible(true)
	_button(menu, "辅助功能").pressed.emit()
	if not _button(menu, "直接通关").disabled:
		fail("Busy gameplay must disable assistance")
		return
	scene.busy = false
	var path: String = "user://test_assistance_%d.json" % Time.get_ticks_usec()
	scene.battle_store.path = path
	scene._set_menu_visible(true)
	_button(menu, "辅助功能").pressed.emit()
	_button(menu, "直接通关").pressed.emit()
	var confirm_victory: Button = _button(menu, "确认通关")
	confirm_victory.pressed.emit()
	confirm_victory.pressed.emit()
	if not scene.busy or menu.visible or scene.battle.outcome.get("reason") != "assistance":
		fail("Explicit confirmation must start the normal victory flow once")
		return
	var deadline: int = Time.get_ticks_msec() + 10000
	Engine.time_scale = 32
	while not scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		if scene.story_player.choices.visible:
			var route: Button = scene.story_player.choices.get_child(2)
			route.pressed.emit()
		else:
			var confirm := InputEventKey.new()
			confirm.keycode = KEY_ENTER
			confirm.pressed = true
			Input.parse_input_event(confirm)
		await process_frame
	Engine.time_scale = 1
	var restored: Dictionary = scene.battle_store.read()
	if (
		not scene.story_player.world_ready
		or restored["ok"]
		or not restored.get("missing", false)
		or scene.world_progress["route"] != 4
		or scene.world_progress["gold"] != 6000
		or scene.world_progress["party"].size() != 2
	):
		fail("Assistance must reach the chosen route and resident world without automatic saving")
		return
	DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	print("PASS assistance UI: hierarchy, cancel, guards, single confirmation and resident world")
	quit(0)


func _button(menu: Control, text: String) -> Button:
	for child: Node in menu.find_children("*", "Button", true, false):
		if child.text == text and child.is_visible_in_tree():
			return child
	return null


func fail(message: String) -> void:
	push_error(message)
	quit(1)
