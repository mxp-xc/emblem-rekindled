extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(240, 320)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if not scene.story_player.has_method("show_world"):
		fail(
			"Named records must restore a persistent world map rather than a summary that returns to title"
		)
		return
	var path: String = "user://test_world_slots_%d.json" % Time.get_ticks_usec()
	scene.battle_store = load("res://persistence/battle_store.gd").new(scene.content, path)
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	progress["elapsedMinutes"] = 126
	if not scene.battle_store.write_slot(0, progress)["ok"]:
		fail("The world restore test needs a valid isolated named record")
		return
	scene.title_screen.prologue.skip()
	for update: int in range(7):
		scene.title_screen.tick()
	scene.title_screen.refresh_continue(false)
	for code: int in [KEY_ENTER, KEY_RIGHT, KEY_RIGHT, KEY_ENTER, KEY_ENTER]:
		await key(code)
	var world: Control = scene.story_player
	if (
		scene.title_screen.visible
		or not world.world_active
		or not world.world_ready
		or world.choices.visible
	):
		fail(
			"Reading a world record must restore its base map without repeating the completion guide/menu"
		)
		return
	if world.visible_world_nodes != [0, 1] or world.selected_world_node != 0:
		fail("The saved route reveals only its current and first next node")
		return
	await key(KEY_ENTER)
	if not world.choices.visible or world.get("_route_panel").position.y != 14 * world.size.x / 240:
		fail("Confirming the current node opens the original upper-left world menu")
		return
	world.choices.get_node("World_save").pressed.emit()
	await process_frame
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	if not scene.save_slots.visible or scene.save_slots.slot != 1:
		fail("Writing an empty world slot must retain the same source record screen")
		return
	var saved: Dictionary = scene.battle_store.read_slot(1)
	if (
		not saved["ok"]
		or saved["progress"]["elapsedMinutes"] != 126
		or saved["progress"]["gold"] != 6000
	):
		fail("The selected world slot must retain party/funds and the restored source H:MM")
		return
	scene.world_progress["gold"] = 6100
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	if (
		scene.save_slots.page != "slots"
		or scene.battle_store.read_slot(1)["progress"]["gold"] != 6000
	):
		fail("Canceling overwrite must preserve the actual prior world record")
		return
	await key(KEY_ESCAPE)
	if scene.save_slots.visible or not world.choices.visible:
		fail("Back from records returns to the same world menu")
		return
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	if world.choices.visible or not world.visible or scene.title_screen.visible:
		fail("Base-world Back must stay in the world rather than skip to title")
		return
	root.size = Vector2i(720, 1280)
	await process_frame
	await process_frame
	var view: RefCounted = world.get("_world_view")
	var point: Vector2 = view.screen_at(Vector2(5.5, 4.5))
	await touch(point, true)
	await key(KEY_ESCAPE)
	await touch(point, false)
	if world.choices.visible:
		fail("Back must cancel a pending world gesture so its release cannot reopen a menu")
		return
	await touch(point, true)
	await touch(point, false)
	if not world.choices.visible:
		fail("Actual touch on the selected world node must open its menu")
		return
	await key(KEY_ESCAPE)
	await touch(point, true)
	var drag := InputEventScreenDrag.new()
	drag.position = point + Vector2(100, 0)
	drag.relative = Vector2(100, 0)
	Input.parse_input_event(drag)
	await process_frame
	await touch(drag.position, false)
	if world.choices.visible or world.selected_world_node != 0:
		fail("Dragging the world camera must not activate a node or open its action menu")
		return
	await key(KEY_RIGHT)
	for update: int in range(30):
		world.tick()
	var origin: Vector2 = view.world_at(view.viewport_origin) * 24
	var expected_edge := Vector2(288 - view.viewport_size.x / view.zoom, 13)
	if world.get("_world_focus_pending") or not origin.is_equal_approx(expected_edge):
		fail(
			"Focusing the eastern node must clamp the actual camera to the original world-map edge"
		)
		return
	if world.selected_world_node != 1 or scene.world_progress["worldNode"] != 0:
		fail("Selecting a next node must not teleport the party or mutate the saved current node")
		return
	if world.get("_world_hud").get("_name").text != "索菲亚山脉":
		fail("The world HUD must follow the selected original location")
		return
	await key(KEY_LEFT)
	for update: int in range(30):
		world.tick()
	await key(KEY_ENTER)
	if not world.choices.visible:
		fail("After camera travel, confirming the current node must still open its usable menu")
		return
	world.choices.get_node("World_title").pressed.emit()
	await process_frame
	if not scene.title_screen.visible or world.visible:
		fail(
			"The explicit title action must preserve the continue record and leave the world layer"
		)
		return
	if scene.battle_store.read()["progress"]["gold"] != 6100:
		fail(
			"Returning to title must preserve current world progress separately from named records"
		)
		return
	for code: int in [KEY_ENTER, KEY_RIGHT, KEY_ENTER, KEY_ENTER]:
		await key(code)
	world = scene.story_player
	if not world.visible or scene.world_progress["gold"] != 6000 or scene.title_screen.visible:
		fail(
			"Reading the old named slot restores its saved results without duplicating the victory reward"
		)
		return
	for slot: int in range(4):
		DirAccess.remove_absolute(path.get_basename() + "_slot_%d.json" % (slot + 1))
	DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	print(
		"PASS world slots: persistent map, real record/write/cancel/read, source HUD, separate continue"
	)
	quit(0)


func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
