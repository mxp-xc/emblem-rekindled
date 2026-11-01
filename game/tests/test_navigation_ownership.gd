extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	scene._show_cell(Vector2i(8, 11))
	await key(KEY_NUMBERSIGN)
	if not scene.unit_information.visible:
		fail("The information shortcut must work while a battlefield unit is selected")
		return
	await key(KEY_ESCAPE)
	scene._show_unit_menu(Vector2i(8, 11))
	await key(KEY_3, true)
	if not scene.unit_information.visible:
		fail("Shift+3 must open information from the action menu")
		return
	await key(KEY_ESCAPE)
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	await key(KEY_NUMBERSIGN)
	if scene.unit_information.visible:
		fail("The settings owner must block the battlefield information shortcut")
		return
	# A stale focus below a modal must not activate a hidden action through native GUI input.
	scene.unit_panel.show()
	var wait_button: Button = scene.unit_panel.find_child("Wait", true, false)
	wait_button.grab_focus()
	var before: Dictionary = scene.battle.snapshot()
	await key(KEY_ENTER)
	if scene.battle.snapshot() != before or not scene.menu_layer.visible:
		fail("A modal must consume unhandled keys when focus belongs to an underlying screen")
		return
	scene.unit_panel.hide()
	var slots: Array[Dictionary] = [
		{"status": "empty"}, {"status": "empty"}, {"status": "empty"}, {"status": "empty"}
	]
	scene.save_slots.present("load", slots)
	await key(KEY_ESCAPE)
	if scene.save_slots.visible or not scene.menu_layer.visible:
		fail("Back must close the top save selector before the underlying settings menu")
		return
	scene.menu_layer.hide()
	scene.battle_view.show()
	await key(KEY_ESCAPE)
	await key(KEY_NUMBERSIGN)
	if not scene.battle_view.visible or scene.unit_information.visible:
		fail("Battle presentation must block Back and information without invoking a screen return")
		return
	scene.battle_view.hide()
	scene.busy = true
	scene.story_player.show_notice("测试对白", "确认")
	await process_frame
	var text: String = scene.story_player.dialogue.full_text
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await process_frame
	await key(KEY_NUMBERSIGN)
	if not scene.story_player.visible or scene.story_player.dialogue.full_text != text:
		fail("A wheel event must not become dialogue Down/advance")
		return
	if scene.unit_information.visible or scene.battle.snapshot() != before:
		fail("Story ownership must protect battlefield shortcuts and authoritative state")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS navigation ownership: shortcuts, stale focus, modal Back, battle and dialogue blocking"
	)
	quit(0)


func key(code: int, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
