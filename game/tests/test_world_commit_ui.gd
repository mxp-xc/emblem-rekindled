extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	var directory: String = "user://test_world_commit_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	var path: String = directory.path_join("continue.json")
	var blocked: String = directory.path_join("blocked.json")
	DirAccess.make_dir_absolute(blocked)
	var sentinel_path: String = blocked.path_join("owned.txt")
	var sentinel := FileAccess.open(sentinel_path, FileAccess.WRITE)
	sentinel.store_string("preserve")
	sentinel.close()
	scene.battle_store.path = blocked
	scene._played_seconds = 180
	scene.set_process(false)
	await scene._show_completed_progress(progress)
	var world: Control = scene.story_player
	var view: Control = scene.world_inventory_screen
	world.advance()
	world.find_child("World_inventory", true, false).pressed.emit()
	view.find_child("Party_0", true, false).pressed.emit()
	view.find_child("Shop", true, false).pressed.emit()
	if view.page != "shop" or view.stage != "tabs" or scene.world_progress != progress:
		fail("Opening an ordinary shop with no key must skip saving and not stamp elapsed time")
		return
	view.go_back()
	if view.page != "operations" or scene.world_progress != progress:
		fail("Finishing unchanged equipment must succeed without writing or stamping time")
		return
	# Introduce an owned key in a controlled valid fixture, then use the actual shop request.
	var keyed: Dictionary = progress.duplicate(true)
	scene.world_inventory.actor(keyed, 0)["inventory"].append(
		{"id": "test:shop_key", "templateId": 64, "durability": 1}
	)
	scene.world_progress = keyed.duplicate(true)
	view.present(keyed)
	view.find_child("Party_0", true, false).pressed.emit()
	view.find_child("Shop", true, false).pressed.emit()
	if (
		view.page != "shop"
		or view.stage != "tabs"
		or scene.world_progress.get("elapsedMinutes") != 3
		or scene.world_inventory.actor(scene.world_progress, 0)["inventory"].size() != 2
		or keyed["party"] == scene.world_progress["party"]
	):
		fail("Special shop entry consumes one key in memory and stamps elapsed time")
		return
	if FileAccess.get_file_as_string(sentinel_path) != "preserve":
		fail("World changes must not overwrite the storage target automatically")
		return
	if keyed.get("elapsedMinutes", -1) != -1:
		fail("Committing must not mutate the caller's candidate")
		return
	var committed: Dictionary = scene.world_progress.duplicate(true)
	view.go_back()
	view.find_child("Shop", true, false).pressed.emit()
	if scene.world_progress != committed:
		fail("Reentering without a key must preserve the committed business state")
		return
	scene.battle_store.path = path
	if not scene.battle_store.write_progress(scene._world_snapshot())["ok"]:
		fail("Explicit world save must succeed")
		return
	var saved: Dictionary = scene.battle_store.read()
	if not saved["ok"] or saved["progress"] != committed:
		fail("Explicit world save must retain the committed state")
		return
	view.hide()
	world.advance()
	scene._played_seconds = 300
	world.find_child("World_title", true, false).pressed.emit()
	if not scene.title_screen.visible or scene.battle_store.read()["progress"] != committed:
		fail("Returning to title must leave the explicit save unchanged")
		return
	for owned: String in [path, sentinel_path]:
		DirAccess.remove_absolute(owned)
	DirAccess.remove_absolute(blocked)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print(
		"PASS world commits: in-memory key consumption, candidate isolation, explicit save and title"
	)
	quit(0)


func close_notice(world: Control) -> void:
	for update: int in range(30):
		if not world.dialogue.visible:
			return
		world.advance()
		for tick: int in range(3):
			world.tick()
		await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
