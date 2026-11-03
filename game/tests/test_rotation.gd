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
	var selected: int = scene.selected_unit
	var before: Dictionary = scene.battle.snapshot()
	var taps: Array[Vector2i] = []
	scene.map.cell_selected.connect(func(cell: Vector2i) -> void: taps.append(cell))
	var old_point: Vector2 = scene.map.view.screen_at(Vector2(11.5, 11.5))
	scene.map._gui_input(contact(old_point, true))
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	if scene.size != Vector2(1280, 720):
		fail("Landscape must use the short logical edge rather than expanding a portrait canvas")
		return
	var point: Vector2 = scene.map.view.screen_at(Vector2(8.5, 11.5))
	scene.map._gui_input(contact(old_point, false))
	if not taps.is_empty() or scene.selected_unit != selected or scene.battle.snapshot() != before:
		fail("A pre-rotation touch release must not cancel selection, open actions or move a unit")
		return
	scene.map._gui_input(contact(point, true))
	scene.map._gui_input(contact(point, false))
	if taps != [Vector2i(8, 11)] or scene.selected_unit != selected:
		fail("A fresh touch must use the rotated map coordinates")
		return
	scene._show_unit_menu(Vector2i(8, 11))
	scene._unit_intent("inventory", {})
	scene.item_actions.find_child("Use", true, false).pressed.emit()
	scene.item_actions.find_child("Item_60", true, false).pressed.emit()
	scene.item_actions.find_child("Item_60", true, false).pressed.emit()
	for dimensions: Vector2i in [Vector2i(720, 1280), Vector2i(1600, 720), Vector2i(1280, 720)]:
		root.size = dimensions
		await process_frame
		await process_frame
		if scene.item_actions.page != "confirm" or scene.battle.snapshot() != before:
			fail("Rotation must preserve an item confirmation without consuming items or actions")
			return
	scene._handle_back()
	if scene.item_actions.page != "items":
		fail("Back after rotation must retain the same item list")
		return
	scene.resume_battle(scene.battle)
	scene._show_cell(Vector2i(8, 11))
	scene._show_information()
	var information: Control = scene.unit_information
	var page: int = information.page
	Input.parse_input_event(contact(Vector2(640, 360), true))
	await process_frame
	root.size = Vector2i(720, 1280)
	await process_frame
	await process_frame
	Input.parse_input_event(contact(Vector2(500, 360), false))
	await process_frame
	if information.page != page or not information.visible or scene.battle.snapshot() != before:
		fail("A pre-rotation swipe release must preserve the information page and battle")
		return
	scene._handle_back()
	await check_world(scene)
	scene.queue_free()
	await process_frame
	print("PASS rotation: stale input, fresh coordinates, item confirmation, world width/safe area")
	quit(0)


func check_world(scene: Control) -> void:
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	await scene._show_completed_progress(progress)
	var world: Control = scene.story_player
	var view: RefCounted = world.get("_world_view")
	var selected: int = world.selected_world_node
	var node: Array = content["story"]["world"]["nodes"][selected]["position"]
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(720, 1280), Vector2i(1600, 720)]:
		var old: Vector2 = view.screen_at(Vector2(node[0] + 0.5, node[1] + 0.5))
		world._handle_world_pointer(contact(old, true))
		root.size = dimensions
		await process_frame
		await process_frame
		world._handle_world_pointer(contact(old, false))
		if (
			world.choices.visible
			or scene.world_progress != progress
			or world.selected_world_node != selected
		):
			fail(
				"World rotation must discard the old touch without opening a menu or changing progress"
			)
			return
		if not is_equal_approx(view.viewport_size.x, scene.size.x):
			fail("The world map must use the available width in both orientations")
			return
		if not Rect2(view.viewport_origin, view.viewport_size).has_point(
			view.screen_at(Vector2(node[0] + 0.5, node[1] + 0.5))
		):
			fail("The selected world node must remain visible after rotation")
			return
	var inset := Rect2(48, 24, scene.size.x - 96, scene.size.y - 60)
	world.set_battle_area(inset, inset)
	await process_frame
	var map_rect := Rect2(view.viewport_origin, view.viewport_size)
	if not inset.encloses(map_rect) or not is_equal_approx(map_rect.size.x, inset.size.x):
		fail("World map content must respect rotated system insets without becoming portrait-width")
		return
	for control: Control in [
		world.get_node("WorldHud"), world.get_node("Confirm"), world.get("_world_back")
	]:
		if not inset.grow(0.1).encloses(control.get_global_rect()):
			fail("World HUD and confirmation controls must remain inside the safe area")
			return
	var point: Vector2 = view.screen_at(Vector2(node[0] + 0.5, node[1] + 0.5))
	world._handle_world_pointer(contact(point, true))
	world._handle_world_pointer(contact(point, false))
	if not world.choices.visible or scene.world_progress != progress:
		fail("A fresh touch after rotation must open the current world menu without mutation")
		return
	world._handle_world_pointer(contact(Vector2(1200, 400), true))
	root.size = Vector2i(720, 1280)
	await process_frame
	await process_frame
	world._handle_world_pointer(contact(Vector2(1200, 400), false))
	if not world.choices.visible:
		fail("A stale outside release after rotation must not close the current world menu")
		return
	world._handle_world_pointer(contact(Vector2(600, 400), true))
	world._handle_world_pointer(contact(Vector2(600, 400), false))
	if world.choices.visible:
		fail("A fresh outside tap after rotation must still close the world menu")
		return


func contact(point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 4
	event.position = point
	event.pressed = pressed
	return event


func fail(message: String) -> void:
	push_error(message)
	quit(1)
