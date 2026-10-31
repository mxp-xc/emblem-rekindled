extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.resume_battle(scene.battle)
	_tap(scene.map.view.screen_at(Vector2(8.5, 11.5)))
	await process_frame
	if not scene.choosing_destination or scene.unit_panel.visible:
		fail("Single tap must enter movement immediately, without a popup")
		return
	_tap(scene.map.view.screen_at(Vector2(8.5, 15.5)))
	await create_timer(0.6).timeout
	if scene.battle.unit(0)["y"] != 15 or scene.battle.unit(0)["action"] != 0:
		fail("Touch movement must reach the destination and leave action available")
		return
	await process_frame
	await process_frame
	if not scene.unit_panel.visible:
		fail("Movement must automatically open available actions")
		return
	if scene.unit_panel.get_global_rect().get_center().distance_to(Vector2(360, 640)) > 1:
		fail("Action menu must be centered in the viewport")
		return
	var cancel: Button = scene.get_node("UnitStatus/Status/Actions/Cancel")
	_tap(cancel.get_global_rect().get_center())
	await process_frame
	if scene.battle.unit(0)["y"] != 11 or scene.battle.unit(0)["action"] != 0:
		fail("UI cancel must restore the original position")
		return
	_tap(scene.map.view.screen_at(Vector2(8.5, 15.5)))
	await create_timer(0.6).timeout
	await process_frame
	await process_frame
	var wait_button: Button = scene.get_node("UnitStatus/Status/Actions/Wait")
	_tap(wait_button.get_global_rect().get_center())
	await process_frame
	if scene.battle.unit(0)["y"] != 15 or scene.battle.unit(0)["action"] != 2:
		fail("UI wait must complete exactly one move/action")
		return
	scene.queue_free()
	await process_frame
	print("PASS movement UI: touch move, animation, cancel, wait")
	quit(0)


func _tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = pressed
		Input.parse_input_event(event)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
