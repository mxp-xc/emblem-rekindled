extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for touchscreen: bool in [true, false]:
		root.size = Vector2i(720, 1280)
		await process_frame
		await process_frame
		scene.resume_battle(load("res://gameplay/battle_state.gd").new(scene.content))
		scene._show_unit_menu(Vector2i(8, 11))
		scene._unit_intent("inventory", {})
		var view: Control = scene.item_actions
		view.find_child("Discard", true, false).pressed.emit()
		view.find_child("Item_60", true, false).pressed.emit()
		view.find_child("Item_60", true, false).pressed.emit()
		await process_frame
		await process_frame
		var before: Dictionary = scene.battle.snapshot()
		var confirm: Button = view.get("_confirm")
		Input.parse_input_event(pointer(confirm.get_global_rect().get_center(), true, touchscreen))
		await process_frame
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		var point: Vector2 = confirm.get_global_rect().get_center()
		Input.parse_input_event(pointer(point, false, touchscreen))
		await process_frame
		if view.page != "confirm" or scene.battle.snapshot() != before or confirm.is_pressed():
			fail(
				"Rotation must release native touch/mouse capture without submitting item confirmation"
			)
			return
		Input.parse_input_event(pointer(point, true, touchscreen))
		await process_frame
		Input.parse_input_event(pointer(point, false, touchscreen))
		await process_frame
		if view.page != "items" or scene.battle.unit(0)["inventory"].size() != 1:
			fail("A fresh touch/mouse confirmation after rotation must submit the discard once")
			return
	scene.queue_free()
	await process_frame
	print("PASS rotation confirmation: canceled native touch/mouse capture, fresh single commit")
	quit(0)


func pointer(point: Vector2, pressed: bool, touchscreen: bool) -> InputEvent:
	if touchscreen:
		var touch := InputEventScreenTouch.new()
		touch.index = 4
		touch.position = point
		touch.pressed = pressed
		return touch
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = point
	mouse.pressed = pressed
	return mouse


func fail(message: String) -> void:
	push_error(message)
	quit(1)
