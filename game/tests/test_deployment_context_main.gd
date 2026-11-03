extends SceneTree

const Context = preload("res://gameplay/deployment_context.gd")
const Store = preload("res://persistence/battle_store.gd")
const Main = preload("res://app/main.tscn")
var _directory: String = ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = Main.instantiate()
	root.add_child(scene)
	await process_frame
	var candidate: String = "user://deployment_context_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(candidate) or DirAccess.make_dir_absolute(candidate) != OK:
		fail("Cannot create owned test directory")
		return
	_directory = candidate
	scene.battle_store = Store.new(scene.content, _directory.path_join("continue.json"))
	if scene._deployment_context != null:
		fail("A fresh application begins without a statistics context")
		return
	if not scene.battle_store.write(scene.battle)["ok"]:
		fail("Write an owned battle snapshot for direct continuation")
		return
	scene.battle.win_with_assistance()
	var completed: Dictionary = scene.battle.complete_victory(0)
	if not completed["ok"]:
		fail("Build an actual completed-world fixture: " + str(completed))
		return
	var lower: Dictionary = completed["progress"].duplicate(true)
	var progress: Dictionary = lower.duplicate(true)
	progress["party"][0]["maxHp"] = 55
	progress["party"][0]["hp"] = 55
	var saved: Dictionary = scene.battle_store.write_slot(0, progress)
	if not saved["ok"]:
		fail("Write only the owned world-slot fixture: " + str(saved))
		return
	var preview: Array = scene._describe_save_slots()
	if preview[0]["status"] != "world" or scene._deployment_context != null:
		fail("Previewing or validating a world slot must not update context")
		return
	scene._slot_operation = "load"
	scene._accept_save_slot(0)
	await process_frame
	var expected: Variant = Context.accumulate(null, progress["party"])
	if scene._deployment_context != expected:
		fail("Actually adopting a world slot must accumulate its validated party")
		return
	if not scene.battle_store.write_slot(1, lower)["ok"]:
		fail("Write the second owned world-slot fixture")
		return
	scene._slot_operation = "load"
	scene._accept_save_slot(1)
	await process_frame
	expected = Context.accumulate(expected, lower["party"])
	if scene._deployment_context != expected:
		fail("A later world-slot load retains earlier maxima and recomputes the average")
		return
	scene._show_title()
	scene.load_game()
	if scene._deployment_context != expected:
		fail("Restoring a battle snapshot must not update the process context")
		return
	if not scene.battle_store.write_progress(progress)["ok"]:
		fail("Write owned world progress for continuation")
		return
	scene._show_title()
	scene.load_game()
	await process_frame
	expected = Context.accumulate(expected, progress["party"])
	if scene._deployment_context != expected:
		fail("Continuing from world progress must accumulate its accepted party")
		return
	scene._show_title()
	scene.title_screen.prologue.skip()
	for update: int in range(7):
		scene.title_screen.tick()
	scene.start_new_game()
	if scene._deployment_context != expected:
		fail("A new game in the same process must retain the context")
		return
	scene.queue_free()
	await process_frame
	if not await _completion():
		return
	_cleanup()
	print("PASS deployment context Main: preview stays pure; world-slot adoption updates")
	quit(0)


func _completion() -> bool:
	var scene: Control = Main.instantiate()
	root.add_child(scene)
	await process_frame
	var blocked: String = _directory.path_join("blocked")
	if DirAccess.make_dir_absolute(blocked) != OK:
		fail("Cannot create owned blocked destination")
		return false
	scene.battle_store = Store.new(scene.content, blocked)
	scene.title_screen.hide()
	scene.story_player.selected_route = 0
	scene.battle.win_with_assistance()
	scene._finish_outcome()
	var ready: bool = false
	for frame: int in range(1200):
		if scene.story_player.world_ready:
			ready = true
			break
		scene.story_player.advance()
		for tick: int in range(4):
			scene.story_player.tick()
		await process_frame
	if not ready:
		fail("Completion must reach the world without writing an automatic record")
		return false
	var completed: Dictionary = scene.battle.complete_victory(0)
	if not completed["ok"]:
		fail("Retain the completed battle candidate")
		return false
	if scene._deployment_context != Context.accumulate(null, completed["progress"]["party"]):
		fail("Completion must commit its party statistics once without saving")
		return false
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(blocked)
	return true


func _cleanup() -> void:
	if not _directory.is_empty() and DirAccess.dir_exists_absolute(_directory):
		for name: String in DirAccess.get_files_at(_directory):
			DirAccess.remove_absolute(_directory.path_join(name))
		var blocked: String = _directory.path_join("blocked")
		if DirAccess.dir_exists_absolute(blocked):
			DirAccess.remove_absolute(blocked)
		DirAccess.remove_absolute(_directory)


func fail(message: String) -> void:
	_cleanup()
	push_error(message)
	quit(1)
