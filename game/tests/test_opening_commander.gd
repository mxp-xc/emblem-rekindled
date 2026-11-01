extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _directory: String = ""
var _selection_finished: bool = false
var _commit_finished: bool = false
var _commit_ok: bool = false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var owned: String = "user://test_opening_commander_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(owned) or DirAccess.make_dir_absolute(owned) != OK:
		fail("Commander scene tests require a new owned record directory")
		return
	_directory = owned
	scene.store.path = owned.path_join("settings.json")
	scene.battle_store.path = owned.path_join("continue.json")
	var opened: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, _roll)
	for id: int in [6, 7]:
		opened["battle"].win_with_assistance()
		var completed: Dictionary = opened["battle"].complete_victory(0)
		opened = Session.new().open(
			CHAPTER, "m1" if id == 6 else "m2", {"progress": completed["progress"]}, _roll
		)
		if not opened["ok"]:
			fail("The commander UI must use actual world-entry content")
			return
		scene._adopt_content(opened["content"], opened["battle"])
		scene.resume_battle(opened["battle"])
		var before: Dictionary = scene.battle.snapshot()
		_selection_finished = false
		_play_selection(scene)
		await process_frame
		var screen: Control = scene.story_player.commander
		if (
			not screen.visible
			or screen.draft["candidates"] != [{"id": id, "name": scene.battle.unit(id)["name"]}]
		):
			fail("The opening UI must expose exactly the domain's visible declared commander")
			return
		screen.change(0, 1)
		screen.change(0, -1)
		if screen.draft["commander"] != id or scene.battle.snapshot() != before:
			fail("Cycling must never expose hidden living0 or submit the selector draft")
			return
		scene.story_player.go_back()
		await process_frame
		if not _selection_finished or scene.story_player.selected_commander != id:
			fail("Back must commit the same eligible opening commander through the real story step")
			return
		# Simulate a stale selection at the UI/domain boundary. Main must explain
		# the rejection and reopen the selector, rather than silently use its default.
		scene.story_player.selected_commander = 0
		_commit_finished = false
		_commit_selection(scene)
		await process_frame
		if (
			_commit_finished
			or not scene.story_player.dialogue.visible
			or scene.battle.snapshot() != before
		):
			fail(
				"A rejected opening selection must display a retry notice without mutating the battle"
			)
			return
		scene.story_player.advance()
		await process_frame
		if not screen.visible or _commit_finished:
			fail("Acknowledging the rejection must reopen the current eligible selection")
			return
		screen.change(1, 1)
		scene.story_player.go_back()
		await process_frame
		if (
			not _commit_finished
			or not _commit_ok
			or scene.battle.commander_id != id
			or scene.battle.command_policy != 1
		):
			fail("Main must explicitly commit the retried commander and changed policy")
			return
		if not DirAccess.get_files_at(_directory).is_empty():
			fail("Opening selection and rejection must not write progress or settings")
			return
	scene.queue_free()
	await process_frame
	if not _cleanup():
		quit(1)
		return
	print(
		"PASS opening commander: actual m1/m2 candidates, hidden exclusion, draft/Back and explicit retry"
	)
	quit(0)


func _play_selection(scene: Control) -> void:
	await scene.story_player.play(
		[{"kind": "commanderSetup"}], scene.battle.command_configuration()
	)
	_selection_finished = true


func _commit_selection(scene: Control) -> void:
	_commit_ok = await scene._commit_opening_commander()
	_commit_finished = true


func _roll(_limit: int) -> int:
	return 0


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


func fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
