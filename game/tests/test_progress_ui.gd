extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	if not scene.story_player.has_method("show_world"):
		fail("Completed progress must have a world-map entry screen")
		return
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(2)["progress"]
	var path := "user://test_progress_ui_%d.json" % Time.get_ticks_usec()
	var store: RefCounted = load("res://persistence/battle_store.gd").new(content, path)
	store.write_progress(progress)
	scene.battle_store = store
	scene.title_screen.refresh_continue(true)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await create_timer(0.6).timeout
	Input.parse_input_event(enter)
	await process_frame
	var load_button: Button
	for child: Node in scene.title_screen.options.get_children():
		if child is Button and child.text == "读取进度":
			load_button = child
	if load_button == null or not load_button.visible:
		fail("The saved temporary record must expose the source Continue entry")
		return
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = load_button.get_global_rect().get_center()
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame
	if (
		scene.title_screen.visible
		or not scene.story_player.visible
		or not scene.story_player.world_ready
		or scene.world_progress["gold"] != 6000
		or scene.story_player.visible_world_nodes != [0, 3]
	):
		fail(
			"Completed continuation must restore the saved world/route/funds without reopening battle"
		)
		return
	scene.story_player.advance()
	scene.story_player.choices.get_node("World_title").pressed.emit()
	await process_frame
	if not scene.title_screen.visible or store.read()["progress"] != progress:
		fail("Returning from completed progress must retain the archive without another reward")
		return
	DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	print(
		"PASS progress UI: continued world/route/gold, explicit title return without duplicate reward"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
