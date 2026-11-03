extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var directory: String = "user://manual_progress_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	var path: String = directory.path_join("continue.json")
	scene.battle_store.path = path
	scene.busy = false
	if not scene._save_battle():
		fail("Explicit battle save must write a record")
		return
	var before: String = FileAccess.get_file_as_string(path)
	scene.battle.win_with_assistance()
	var progress: Dictionary = scene.battle.complete_victory(0)["progress"]
	progress["gold"] += 100
	scene._commit_world_progress(progress)
	if (
		FileAccess.get_file_as_string(path) != before
		or scene.world_progress["gold"] != progress["gold"]
	):
		fail("World changes must remain in memory until an explicit save")
		return
	scene._open_save_slots("save")
	scene._accept_save_slot(0)
	var saved: Dictionary = scene.battle_store.read_slot(0)
	if not saved["ok"] or saved["progress"]["gold"] != progress["gold"]:
		fail("An explicit world slot must save the current progress")
		return
	DirAccess.remove_absolute(scene.battle_store._slot_path(0))
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	print("PASS manual progress save: battle, in-memory world, explicit slot")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
