extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var before: Dictionary = scene.battle.snapshot()
	var center: Vector2 = scene.map.view.center
	var slots: Array[Dictionary] = [
		{"status": "empty"}, {"status": "empty"}, {"status": "empty"}, {"status": "empty"}
	]
	scene.save_slots.present("load", slots)
	# Eight tiny events reproduce the browser's 3.735px * 0.03 factor stream.
	for sample: int in range(8):
		await wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.11205)
	if scene.save_slots.slot != 1:
		fail("A small smooth-wheel burst must move one slot, rather than eight full selections")
		return
	# Continued movement can advance again once both distance and time have accumulated.
	await create_timer(0.09).timeout
	await wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.7)
	await create_timer(0.09).timeout
	await wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.4)
	if scene.save_slots.slot != 2:
		fail("Sustained smooth scrolling must continue after accumulating distance and time")
		return
	await create_timer(0.25).timeout
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	if scene.save_slots.slot != 3:
		fail("An independent wheel detent after idle must respond immediately")
		return
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	if scene.save_slots.slot != 2:
		fail("Reversing direction must respond without waiting for the old scroll interval")
		return
	scene.save_slots.hide()
	scene.selected_unit = 0
	scene._show_information()
	for sample: int in range(8):
		await wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.11205)
	if scene.unit_information.page != 2:
		fail("A newly active information screen must turn one page for a small scroll burst")
		return
	# No timer may replay suppressed wheel events after scrolling has stopped.
	await create_timer(0.3).timeout
	if scene.unit_information.page != 2:
		fail("Suppressed wheel input must not be queued for delayed page refreshes")
		return
	scene.unit_information.show_item(scene.battle.unit(0)["inventory"][0])
	await wheel(MOUSE_BUTTON_WHEEL_DOWN, 5.0)
	if not scene.unit_information.detail_visible or scene.unit_information.page != 2:
		fail("Large wheel events must preserve an open item detail")
		return
	scene.unit_information.go_back()
	scene.unit_information.go_back()
	scene._set_menu_visible(true)
	var initial: Control = root.gui_get_focus_owner()
	await wheel(MOUSE_BUTTON_WHEEL_DOWN, 5.0)
	var stepped: Control = root.gui_get_focus_owner()
	if stepped == initial:
		fail("A large detent must still move one menu item immediately")
		return
	for sample: int in range(6):
		await wheel(MOUSE_BUTTON_WHEEL_DOWN, 1.0)
	if root.gui_get_focus_owner() != stepped:
		fail("Dense full-factor events must be rate limited instead of repeatedly refreshing menus")
		return
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	if scene.menu_layer.visible:
		fail("Wheel pacing must not delay keyboard Back")
		return
	scene._set_menu_visible(true)
	initial = root.gui_get_focus_owner()
	await wheel(MOUSE_BUTTON_WHEEL_DOWN, 0.11205)
	if root.gui_get_focus_owner() == initial:
		fail("Reopening the same menu after Back must start a fresh wheel gesture")
		return
	Input.parse_input_event(key)
	await process_frame
	if scene.battle.snapshot() != before or scene.map.view.center != center:
		fail("Menu scrolling must leave business state and the underlying camera unchanged")
		return
	scene.selected_unit = -1
	scene.map.view.zoom_at(4.0, scene.map.view.viewport_origin + scene.map.view.viewport_size / 2)
	center = scene.map.view.center
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	var moved: Vector2 = scene.map.view.center
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	if moved == center or scene.map.view.center == moved:
		fail("Unowned battlefield wheel events must retain continuous map panning")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS wheel pacing: smooth bursts, detents, reversal, owner change, rate limit and map pan"
	)
	quit(0)


func wheel(button: MouseButton, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.factor = factor
	event.pressed = true
	event.position = Vector2(360, 500)
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
