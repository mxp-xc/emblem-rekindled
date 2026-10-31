extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	await _tap_hero(scene)
	await _press_escape()
	if scene.selected_unit != -1 or scene.choosing_destination or scene.menu_layer.visible:
		fail("Esc must cancel movement selection without opening settings")
		return
	await _tap_hero(scene)
	if scene.unit_panel.visible or not scene.choosing_destination:
		fail("Cancel must reset tap history so the next single touch starts movement, not a menu")
		return
	scene._show_cell(Vector2i(8, 15))
	await create_timer(0.6).timeout
	scene._unit_intent("inventory", {})
	await _press_escape()
	if not scene.unit_panel.visible or scene.item_actions.visible:
		fail("Esc from inventory must return to actions, preserving provisional movement")
		return
	if scene.battle.unit(0)["y"] != 15:
		fail("Closing inventory must not cancel the provisional move")
		return
	scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if (
		scene.unit_panel.visible
		or scene.battle.unit(0)["y"] != 11
		or not scene.choosing_destination
	):
		fail("Android back must undo a provisional move and restore its movement range")
		return
	await _press_escape()
	await _press_escape()
	if not scene.menu_layer.visible:
		fail("Back with no selection must open the system menu")
		return
	scene.selected_unit = 0
	var shortcut := InputEventKey.new()
	shortcut.unicode = 35
	shortcut.pressed = true
	Input.parse_input_event(shortcut)
	await process_frame
	if scene.unit_information.visible:
		fail("A shortcut must not open a hidden information layer under the system menu")
		return
	scene.menu_layer.show_page("settings")
	scene.menu_layer.show_page("license")
	await _press_escape()
	if not scene.menu_layer.visible or scene.menu_layer.license_view.visible:
		fail("Back from a nested settings page must return one level")
		return
	await _press_escape()
	if not scene.menu_layer.visible or scene.menu_layer.page != "main":
		fail("Back from settings must return to the system menu first")
		return
	await _press_escape()
	if scene.menu_layer.visible:
		fail("Back from the system menu must return to the battlefield")
		return
	scene.queue_free()
	await process_frame
	print("PASS back navigation: Esc, Android, inventory, provisional move, range, settings")
	quit(0)


func _press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _tap_hero(scene: Control) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = scene.map.view.screen_at(Vector2(8.5, 11.5))
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
