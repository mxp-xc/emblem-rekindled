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
	scene._show_cell(Vector2i(8, 11))
	var before: Dictionary = scene.battle.snapshot()
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_3
	shortcut.shift_pressed = true
	shortcut.pressed = true
	Input.parse_input_event(shortcut)
	await process_frame
	await process_frame
	var info: Control = scene.unit_information
	if not info.visible or info.page != 1 or info.body.get_child_count() != 7:
		fail("The # shortcut must open character information with seven basic attributes")
		return
	if info.get_global_rect() != Rect2(0, 0, 720, 1280):
		fail("Character information must follow the original full-screen layout")
		return
	_swipe(Vector2(520, 650), Vector2(200, 650))
	await process_frame
	await process_frame
	if info.page != 2 or info.detail_visible:
		fail("A left swipe must switch to the equipment page")
		return
	var herb: Button = info.body.get_node("Item_60")
	_swipe(
		herb.get_global_rect().get_center(), herb.get_global_rect().get_center() + Vector2(200, 0)
	)
	await process_frame
	await process_frame
	if info.page != 1 or info.detail_visible:
		fail("Swiping on an item must switch pages without accidentally opening details")
		return
	_swipe(Vector2(520, 650), Vector2(200, 650))
	await process_frame
	await process_frame
	herb = info.body.get_node("Item_60")
	_tap(herb.get_global_rect().get_center())
	await process_frame
	await process_frame
	if (
		not info.detail_visible
		or info.detail.get_node("Description").get_meta("source_description") != "回复10点体力"
	):
		fail("An equipment tap after a swipe must show the original item description")
		return
	if info.body.get_node_or_null("Item_60") == null or info.detail.get_global_rect().end.y > 1280:
		fail(
			(
				"Item details must retain the equipment list and occupy the bottom strip: "
				+ str(info.detail.get_global_rect())
				+ " minimum="
				+ str(info.detail.get_combined_minimum_size())
			)
		)
		return
	scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if not info.visible or info.detail_visible or info.page != 2:
		fail("One Android back with duplicated notifications must return exactly one level")
		return
	scene._handle_back()
	if info.visible or not scene.choosing_destination or scene.battle.snapshot() != before:
		fail("Inspecting information must preserve selection and all battle state")
		return
	scene.queue_free()
	await process_frame
	await process_frame
	print(
		"PASS information UI: # shortcut, basic stats, equipment swipe, original detail, layered back"
	)
	quit(0)


func _tap(point: Vector2) -> void:
	_touch(point, true)
	_touch(point, false)


func _swipe(start: Vector2, finish: Vector2) -> void:
	_touch(start, true)
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = finish
	event.relative = finish - start
	Input.parse_input_event(event)
	_touch(finish, false)


func _touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
