extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var battle: RefCounted = scene.battle
	var state: Dictionary = battle.snapshot()
	for unit: Dictionary in state["units"]:
		if unit["id"] == 0:
			unit["inventory"].append({"id": "click-iron", "templateId": 1, "durability": 30})
	if not battle.restore_snapshot(state)["ok"]:
		fail("Prepare two actually equippable items")
		return
	scene.resume_battle(battle)
	scene._show_unit_menu(Vector2i(8, 11))
	scene._unit_intent("inventory", {})
	var view: Control = scene.item_actions
	view.find_child("Equip", true, false).pressed.emit()
	var before: Dictionary = battle.snapshot()
	await click(view.find_child("Item_1", true, false))
	if view.page != "items" or view.get("_selected")["id"] != "click-iron":
		fail("A real pointer click must select the new equipment, without opening confirmation")
		return
	await click(view.find_child("Item_9", true, false))
	if view.page != "items" or battle.snapshot() != before:
		fail("Switching to another item must only display its attributes")
		return
	await click(view.find_child("Item_9", true, false))
	if view.page != "confirm" or battle.snapshot() != before:
		fail("Clicking the same selected item again must open confirmation without equipping")
		return
	scene._handle_back()
	if view.page != "items" or view.get("_selected")["templateId"] != 9:
		fail("Cancel must preserve the selected equipment")
		return
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	if view.get("_selected")["id"] != "click-iron":
		fail("Tab must select the next real equipment row")
		return
	await click(view.find_child("Item_9", true, false))
	if view.page != "items":
		fail("Clicking an older choice after Tab selection must not activate a stale candidate")
		return
	event = InputEventKey.new()
	event.keycode = KEY_DOWN
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	if (
		view.page != "confirm"
		or view.get("_selected")["id"] != "click-iron"
		or battle.snapshot() != before
	):
		fail("Keyboard selection followed by explicit confirmation must retain its direct path")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS item click: switch previews, repeat click confirms, cancel preserves, keyboard direct"
	)
	quit(0)


func click(button: Button) -> void:
	await process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
