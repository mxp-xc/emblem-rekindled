extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var directory: String = "user://test_slot_errors_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	var path: String = directory.path_join("continue.json")
	scene.battle_store = load("res://persistence/battle_store.gd").new(scene.content, path)
	scene.battle_store.write(scene.battle)
	var temporary: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var broken_path: String = directory.path_join("continue_slot_1.json")
	var file := FileAccess.open(broken_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	scene.title_screen.prologue.skip()
	for update: int in range(7):
		scene.title_screen.tick()
	scene._open_save_slots("load")
	if not scene.save_slots.get("_details").text.contains("无法读取"):
		fail("The list must validate the body and mark a damaged record before attempting to load")
		return
	await key(KEY_ENTER)
	if not scene.save_slots.visible or scene.save_slots.slot != 0:
		fail("A damaged selected record must show a recoverable error on the same slot")
		return
	if FileAccess.get_file_as_string(broken_path) != "{broken":
		fail("A failed read must preserve the damaged body for recovery")
		return
	await key(KEY_ESCAPE)
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	progress["gold"] = 7000
	scene.battle_store.write_slot(2, progress)
	await scene._show_completed_progress(progress)
	var blocked_path: String = directory.path_join("continue_slot_2.json")
	DirAccess.make_dir_absolute(blocked_path)
	var sentinel: String = blocked_path.path_join("owned.txt")
	file = FileAccess.open(sentinel, FileAccess.WRITE)
	file.store_string("preserve")
	file.close()
	scene._open_save_slots("save")
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	if (
		not scene.save_slots.visible
		or scene.save_slots.slot != 1
		or scene.save_slots.page != "slots"
	):
		fail("A failed write must retain the selected slot and keep its parent world alive")
		return
	if (
		not scene.save_slots.get("_details").text.contains("无法写入")
		or not scene.story_player.world_active
	):
		fail("A failed write needs a visible error with a usable world parent")
		return
	if (
		FileAccess.get_file_as_bytes(path) != temporary
		or FileAccess.get_file_as_string(broken_path) != "{broken"
		or scene.battle_store.read_slot(2)["progress"]["gold"] != 7000
		or not FileAccess.file_exists(sentinel)
	):
		fail("Failure must preserve the temporary record, all other slots and the existing target")
		return
	await key(KEY_ESCAPE)
	if scene.save_slots.visible or not scene.story_player.visible:
		fail("Back after a storage error must remain usable")
		return
	for owned: String in [path, broken_path, directory.path_join("continue_slot_3.json"), sentinel]:
		DirAccess.remove_absolute(owned)
	DirAccess.remove_absolute(blocked_path)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print(
		"PASS slot errors UI: body validation, readable failure, protected records, usable Back/world"
	)
	quit(0)


func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
