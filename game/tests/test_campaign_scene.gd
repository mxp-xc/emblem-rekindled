extends SceneTree

var scene: Control
var _directory: String


class SlowContinueStore:
	extends "res://persistence/battle_store.gd"

	func write(battle: RefCounted, elapsed_minutes: int = -1) -> Dictionary:
		if battle.battle_id == "m1":
			OS.delay_msec(180)
		return super.write(battle, elapsed_minutes)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	scene = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var owned: String = "user://test_campaign_scene_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(owned) or DirAccess.make_dir_absolute(owned) != OK:
		fail("Campaign scene tests require a new owned record directory")
		return
	_directory = owned
	scene.store.path = _directory.path_join("settings.json")
	scene.battle_store = SlowContinueStore.new(scene.content)
	scene.battle_store.path = _directory.path_join("continue.json")
	scene.battle.win_with_assistance()
	var progress: Dictionary = scene.battle.complete_victory(0)["progress"]
	scene.battle_store.write_progress(progress)
	var original_record: String = FileAccess.get_file_as_string(scene.battle_store.path)
	await scene._show_completed_progress(progress)
	var world: Control = scene.story_player
	world.go_back()
	world.world_node_requested.emit(1)
	await process_frame
	if not world.choices.visible or not scene._world_transitioning:
		fail("The next route node must open travel confirmation")
		return
	await key(KEY_ESCAPE)
	if (
		scene._world_transitioning
		or scene.world_progress != progress
		or FileAccess.get_file_as_string(scene.battle_store.path) != original_record
		or not world.world_ready
	):
		fail("Cancel travel must preserve the exact continue record and the ready world")
		return
	world.world_node_requested.emit(1)
	await process_frame
	await key(KEY_ENTER)
	# Keep real sequence awaits and input dispatch, while accelerating the test clock.
	Engine.time_scale = 32
	var entered: bool = false
	var seen: Dictionary = {}
	for update: int in range(1200):
		var player: Control = scene.story_player
		if player.current_text_index >= 0:
			seen[player.current_text_index] = true
		if player.commander.visible:
			if player.commander.draft["commander"] != 6:
				fail("The m1 opening must offer Fols as its only commander")
				return
			scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			scene.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			await process_frame
		elif player.dialogue.visible:
			await key(KEY_ENTER)
		else:
			await process_frame
		if scene.content["entry"]["battleId"] == "m1" and not scene.busy:
			entered = true
			break
	Engine.time_scale = 1
	if (
		not entered
		or not seen.has(461)
		or not seen.has(489)
		or not seen.has(490)
		or not seen.has(157)
		or scene.battle.commander_id != 6
		or not scene.battle.event_completed("opening")
		or scene.selected_unit != -1
		or scene.menu_layer.visible
		or not scene.world_progress.is_empty()
	):
		fail(
			(
				"Travel, original entry/opening/objective and commander must precede playable m1: "
				+ str(seen)
			)
		)
		return
	var saved: Dictionary = scene.battle_store.read()
	if not saved["ok"] or saved["content"]["entry"]["battleId"] != "m1":
		fail("The new battle must be saved under m1 before commands become available")
		return
	var state: Dictionary = scene.battle.snapshot()
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	if scene.battle.snapshot() != state or scene.content["map"]["width"] != 22:
		fail("Rotating the adopted map must retain the same battle and 22-column content")
		return
	scene._show_title()
	scene.load_game()
	await process_frame
	if scene.content["entry"]["battleId"] != "m1" or scene.battle.snapshot() != state:
		fail("Continue from title must restore m1 without rebuilding the first battle")
		return
	scene.battle.win_with_assistance()
	var completed: Dictionary = scene.battle.complete_victory(1)["progress"]
	await scene._show_completed_progress(completed)
	Engine.time_scale = 32
	await scene._world_node(0)
	Engine.time_scale = 1
	var visited: Dictionary = scene.battle_store.read()
	if (
		not visited["ok"]
		or visited["progress"].get("worldLocation") != 0
		or visited["progress"]["worldNode"] != 1
		or visited["progress"]["worldStep"] != 2
		or scene.content["entry"]["battleId"] != "m1"
		or not scene.story_player.world_ready
	):
		fail("Visiting an old node must persist location while retaining the completed m1 frontier")
		return
	scene._show_title()
	scene.load_game()
	await process_frame
	if scene.story_player.selected_world_node != 0:
		fail("Reloading a visited node must keep the party there without reopening its old battle")
		return
	# An older m0 world record must switch the whole interface back to its content.
	scene.battle_store.write_progress(progress)
	scene._show_title()
	scene.load_game()
	await process_frame
	if scene.content["entry"]["battleId"] != "m0" or scene.world_progress != progress:
		fail("Loading an older world record must restore its map, menus and route context")
		return
	if not _cleanup():
		quit(1)
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS campaign scene: cancel, travel/opening, commander, rotation, m1 continue and m0 world"
	)
	quit(0)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	Engine.time_scale = 1
	push_error(message)
	_cleanup()
	quit(1)


func _cleanup() -> bool:
	if _directory.is_empty():
		return true
	for name: String in DirAccess.get_files_at(_directory):
		if DirAccess.remove_absolute(_directory.path_join(name)) != OK:
			return false
	if DirAccess.remove_absolute(_directory) != OK:
		return false
	_directory = ""
	return true
