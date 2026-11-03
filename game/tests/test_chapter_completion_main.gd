extends SceneTree

const Fixture = preload("res://tests/test_chapter_session.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var opened: Dictionary = Fixture.prepare_terminal(4, func(_limit: int) -> int: return 0)
	if not opened["ok"]:
		fail("The main flow needs the actual m9 to m13 Session path: " + str(opened))
		return
	scene._adopt_content(opened["content"], opened["battle"])
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	scene._set_menu_visible(false)
	scene.title_screen.hide()
	scene.story_player.selected_commander = 9
	scene.story_player.selected_policy = 0
	scene._play_opening()
	for frame: int in range(1200):
		if scene.story_player.commander.visible:
			fail("None opening must never request a commander selection")
			return
		if scene.battle.event_completed("opening"):
			break
		scene.story_player.advance()
		for tick: int in range(4):
			scene.story_player.tick()
		await process_frame
	if (
		not scene.battle.event_completed("opening")
		or scene.battle.snapshot()["commander"] != -1
		or scene.battle.snapshot()["commandPolicy"] != 5
	):
		fail(
			"None opening must preserve the real empty commander and policy, ignoring stale UI selections"
		)
		return
	var directory: String = "user://completion_main_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	var path: String = directory.path_join("continue.json")
	scene.battle_store.path = path
	scene._played_seconds = 180
	scene.set_process(false)
	scene.world_progress = {}
	scene.battle.win_with_assistance()
	scene._finish_outcome()
	for frame: int in range(1200):
		if scene.story_player.prologue.visible:
			break
		scene.story_player.advance()
		for tick: int in range(4):
			scene.story_player.tick()
		await process_frame
	var candidate: Dictionary = scene.battle.complete_victory(4)["progress"].duplicate(true)
	candidate["elapsedMinutes"] = 3
	if (
		FileAccess.file_exists(path)
		or not scene.story_player.prologue.visible
		or scene.story_player.current_text_index != 459
		or scene.story_player.world_active
	):
		fail("Completion must begin the ending without automatically saving")
		return
	var observed: Array[String] = []
	var personal_names: Array[String] = []
	for frame: int in range(1200):
		if scene.story_player.world_active and scene.story_player.world_ready:
			break
		var dialogue: Control = scene.story_player.dialogue
		if dialogue.visible:
			if not dialogue.full_text in observed:
				observed.append(dialogue.full_text)
			if (
				dialogue.full_text.begins_with("Lv ")
				and not dialogue.heading_label.text in personal_names
			):
				personal_names.append(dialogue.heading_label.text)
		scene.story_player.advance()
		for tick: int in range(4):
			scene.story_player.tick()
		await process_frame
	if not scene.story_player.world_ready or scene.world_progress != candidate:
		fail("The full first-session chapter ending must return to the committed completed world")
		return
	if (
		personal_names.size() != 8
		or not observed.any(func(page: String) -> bool: return page.begins_with("总资金 "))
		or not observed.any(func(page: String) -> bool: return page.contains("初章"))
		or not observed.any(func(page: String) -> bool: return page.contains("待续"))
	):
		fail(
			"The first ending must include every formal person, totals, chapter end and continuation"
		)
		return
	if scene.story_player.get("_world_next_node") != -1:
		fail("A completed route has no next target")
		return
	var record: Button = scene.story_player.find_child("World_chapter_record", true, false)
	if record == null:
		fail("A completed world must offer the local chapter record")
		return
	record.pressed.emit()
	for frame: int in range(200):
		if scene.story_player.world_active and scene.story_player.world_ready:
			break
		scene.story_player.go_back()
		await process_frame
	if scene.world_progress != candidate or FileAccess.file_exists(path):
		fail("Reviewing the completion record must not save or change progress")
		return

	# One explicit slot verifies the completion path; slot coverage lives in its own test.
	scene._open_save_slots("save")
	scene._accept_save_slot(0)
	var metadata: Array = scene._describe_save_slots()
	if metadata[0]["status"] != "world" or not metadata[0]["description"].begins_with("通关\n"):
		fail("A completed slot must display completion metadata")
		return
	if FileAccess.file_exists(path):
		fail("Explicit four-slot saves must leave the continue record untouched")
		return
	scene.save_slots.hide()
	scene._show_title()
	scene._slot_operation = "load"
	scene._accept_save_slot(0)
	await process_frame
	if not scene.story_player.world_active or scene.world_progress != candidate:
		fail("Loading an explicit slot must restore the completed world")
		return
	DirAccess.remove_absolute(scene.battle_store._slot_path(0))
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	print("PASS completion main: none opening, manual save, first ending, review, cold world, slot")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
