extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var directory: String = "user://test_world_inventory_boundaries_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	scene.battle_store.path = directory.path_join("continue.json")
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	var hero: Dictionary = scene.world_inventory.actor(progress, 0)
	hero["inventory"].resize(1)
	await open_hero(scene, progress)
	var view: Control = scene.world_inventory_screen
	await process_frame
	var area := Rect2(Vector2.ZERO, scene.size)
	if not view._operations.get_global_rect().get_center().is_equal_approx(area.get_center()):
		fail("The world operations popup must remain centered after its rows finish sizing")
		return
	view.find_child("Warehouse", true, false).pressed.emit()
	for action: int in range(3):
		await key(KEY_ENTER)
	if (
		view.stage != "tabs"
		or scene.world_inventory.actor(scene.world_progress, 0)["inventory"].size() != 0
	):
		fail(
			"Depositing the last held item must automatically return to the nonempty warehouse tab"
		)
		return
	await key(KEY_ESCAPE)
	if view.page != "operations":
		fail("After the last-item transition, one Back closes the warehouse")
		return
	view.find_child("Warehouse", true, false).pressed.emit()
	for action: int in range(3):
		await key(KEY_ENTER)
	if view.stage != "tabs" or not scene.world_progress["warehouse"].is_empty():
		fail("Taking the last warehouse item automatically returns to the character tab")
		return
	await key(KEY_ESCAPE)
	if (
		view.page != "operations"
		or scene.world_inventory.actor(scene.world_progress, 0)["equippedInstanceId"] == ""
	):
		fail("Closing the warehouse must restore the first eligible equipment")
		return
	var full: Dictionary = scene.world_progress.duplicate(true)
	hero = scene.world_inventory.actor(full, 0)
	while hero["inventory"].size() < 6:
		hero["inventory"].append(
			{"id": "test:bag_%d" % hero["inventory"].size(), "templateId": 60, "durability": 1}
		)
	for index: int in range(40):
		full["warehouse"].append(
			{"id": "test:warehouse_%d" % index, "templateId": 60, "durability": 1}
		)
	await open_hero(scene, full)
	view.find_child("Warehouse", true, false).pressed.emit()
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	if view.stage != "notice" or scene.world_progress != full:
		fail(
			"A full actor reports the capacity before confirmation and leaves every item unchanged"
		)
		return
	Engine.time_scale = 8
	await create_timer(2.2).timeout
	Engine.time_scale = 1
	if view.stage != "items" or scene.world_progress != full:
		fail("The capacity strip must expire back to the same item list without requiring Continue")
		return
	for index: int in range(39):
		await key(KEY_DOWN)
	for frame: int in range(4):
		await process_frame
	var focused: Control = root.gui_get_focus_owner()
	if (
		focused == null
		or not view._scroll.get_global_rect().grow(0.1).encloses(focused.get_global_rect())
	):
		fail("The fortieth warehouse item must scroll into view and stay above the details/footer")
		return
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(540, 960), Vector2i(720, 1280)]:
		root.size = dimensions
		for frame: int in range(4):
			await process_frame
		var width: float = minf(scene.size.x, scene.size.y * 0.75)
		var frame := Rect2((scene.size.x - width) / 2, 0, width, scene.size.y)
		for control: Control in [
			view._scroll, view._footer, view._tabs, view.get_node("Back"), view.get_node("Confirm")
		]:
			if (
				control.is_visible_in_tree()
				and not frame.grow(0.1).encloses(control.get_global_rect())
			):
				fail(
					(
						"World inventory bounds %s: %s outside %s at %s"
						% [control.name, control.get_global_rect(), frame, dimensions]
					)
				)
				return
	DirAccess.remove_absolute(scene.battle_store.path)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print("PASS world inventory boundaries: last items, equip, notice, forty-row scroll and resize")
	quit(0)


func open_hero(scene: Control, progress: Dictionary) -> void:
	await scene._show_completed_progress(progress)
	scene.story_player.advance()
	scene.story_player.find_child("World_inventory", true, false).pressed.emit()
	await key(KEY_RIGHT)
	await key(KEY_ENTER)


func key(code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
