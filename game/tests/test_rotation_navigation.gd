extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.title_screen.prologue.hide()
	Input.parse_input_event(mouse(Vector2(360, 640), true))
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	Input.parse_input_event(mouse(Vector2(640, 360), false))
	await process_frame
	if scene.title_screen.options.visible:
		fail("Neither synthetic canceled nor stale physical release may open title options")
		return
	Input.parse_input_event(mouse(Vector2(640, 360), true))
	Input.parse_input_event(mouse(Vector2(640, 360), false))
	await process_frame
	if not scene.title_screen.options.visible:
		fail("A fresh title click after rotation must work")
		return
	scene.resume_battle(scene.battle)
	scene.story_player.show_notice("旋转应保留通知")
	await process_frame
	Input.parse_input_event(mouse(Vector2(640, 360), true))
	await process_frame
	root.size = Vector2i(720, 1280)
	await process_frame
	await process_frame
	Input.parse_input_event(mouse(Vector2(360, 640), false))
	await process_frame
	if not scene.story_player.visible or scene.story_player.dialogue.full_text != "旋转应保留通知":
		fail("Rotation and a stale release must not advance or close dialogue")
		return
	Input.parse_input_event(mouse(Vector2(360, 640), true))
	Input.parse_input_event(mouse(Vector2(360, 640), false))
	await process_frame
	if scene.story_player.visible:
		fail("Fresh confirmation after rotation must close the notification")
		return
	scene.resume_battle(scene.battle)
	var taps: Array[Vector2i] = []
	scene.map.cell_selected.connect(func(cell: Vector2i) -> void: taps.append(cell))
	var before: Dictionary = scene.battle.snapshot()
	var point: Vector2 = scene.map.view.screen_at(Vector2(11.5, 11.5))
	Input.parse_input_event(mouse(point, true))
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	Input.parse_input_event(mouse(point, false))
	await process_frame
	if not taps.is_empty() or scene.battle.snapshot() != before:
		fail("Canceled mouse capture must not select or move on the resized tactical map")
		return
	scene.queue_free()
	await process_frame
	print("PASS rotation navigation: canceled mouse ignored by title, dialogue and tactical map")
	quit(0)


func mouse(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	return event


func fail(message: String) -> void:
	push_error(message)
	quit(1)
