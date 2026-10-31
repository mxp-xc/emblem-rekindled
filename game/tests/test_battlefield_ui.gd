extends SceneTree

var scene: Control


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	scene = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.resume_battle(scene.battle)
	var map: Control = scene.get_node("TacticalMap")
	var status: Control = scene.get_node("UnitStatus")
	if map.get_global_rect() != Rect2(0, 0, 720, 1280) or status.visible:
		fail("Battlefield must fill the screen without a persistent status panel")
		return
	_touch(scene.map.view.screen_at(Vector2(8.5, 11.5)), 0, true)
	_touch(scene.map.view.screen_at(Vector2(8.5, 11.5)), 0, false)
	await process_frame
	if status.visible or not scene.choosing_destination or map.movement.is_empty():
		fail("Single tap must immediately show movement without opening the secondary menu")
		return
	var selected_before: Vector2i = map.selected
	_touch(Vector2(200, 500), 0, true)
	_drag(Vector2(400, 500), 0)
	_touch(Vector2(400, 500), 0, false)
	await process_frame
	if map.selected != selected_before:
		fail("Swiping must pan without changing selection")
		return
	var zoom_before: float = map.view.zoom
	_touch(Vector2(260, 640), 1, true)
	_touch(Vector2(460, 640), 2, true)
	_drag(Vector2(560, 640), 2)
	_touch(Vector2(560, 640), 2, false)
	_touch(Vector2(260, 640), 1, false)
	await process_frame
	if map.view.zoom <= zoom_before or map.selected != selected_before:
		fail("Pinch must zoom without selecting when either finger lifts")
		return
	var center_before_menu: Vector2 = map.view.center
	var menu_position: Vector2 = scene.menu_button.get_global_rect().get_center()
	_touch(menu_position, 0, true)
	_touch(menu_position, 0, false)
	await process_frame
	if not scene.menu_layer.visible:
		fail("The in-game menu must open through touch input")
		return
	_touch(Vector2(20, 400), 0, true)
	_drag(Vector2(200, 500), 0)
	_touch(Vector2(200, 500), 0, false)
	if not map.view.center.is_equal_approx(center_before_menu) or map.selected != selected_before:
		fail("Menu input must not pan or select the battlefield behind it")
		return
	scene.queue_free()
	await process_frame
	print("PASS battlefield UI: full screen, touch selection/swipe/pinch, modal input isolation")
	quit(0)


func _touch(position: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = index
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(position: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.index = index
	Input.parse_input_event(event)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
