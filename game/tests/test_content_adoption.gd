extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Matrix = preload("res://tests/test_m2_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _directory: String = ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var owned: String = "user://test_content_adoption_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(owned) or DirAccess.make_dir_absolute(owned) != OK:
		fail("Content adoption tests require a new owned record directory")
		return
	_directory = owned
	scene.store.path = owned.path_join("settings.json")
	scene.battle_store.path = owned.path_join("continue.json")
	scene.resume_battle(scene.battle)
	if not _select(scene, 0):
		return
	scene.battle.win_with_assistance()
	var completed: Dictionary = scene.battle.complete_victory(0)
	var world: Dictionary = Session.new().completed_content(CHAPTER, completed["progress"])
	if not world["ok"]:
		fail("The world adoption fixture must use real completed content")
		return
	scene._adopt_content(world["content"])
	if not _cleared(scene) or not scene.battle.snapshot()["units"].is_empty():
		fail(
			"World adoption must clear the old unit before laying out its uninitialized placeholder"
		)
		return
	# Both contexts use the actual m2 map. The late route helper supplies a validated
	# synthetic cultivation record; this does not claim natural preceding-map play.
	for context: Dictionary in [Matrix.CONTEXTS[0], Matrix.CONTEXTS[2]]:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not prepared["ok"]:
			fail("Prepare the real m2 content context")
			return
		var opened: Dictionary = Session.new().open(
			CHAPTER, "m2", {"progress": prepared["progress"]}, _roll
		)
		if not opened["ok"]:
			fail("Open the real m2 context")
			return
		var state: Dictionary = opened["battle"].snapshot()
		scene._adopt_content(opened["content"], opened["battle"])
		if not _cleared(scene) or scene.battle.snapshot() != state:
			fail(
				"Same-map context adoption must clear selection while preserving the supplied battle"
			)
			return
		scene.resume_battle(scene.battle)
		if not _select(scene, 7):
			return
	scene.queue_free()
	await process_frame
	if not DirAccess.get_files_at(_directory).is_empty() or not _cleanup():
		fail("Pure content adoption must not write records")
		return
	print(
		"PASS content adoption: active selection, empty world placeholder and same-map m2 contexts"
	)
	quit(0)


func _select(scene: Control, id: int) -> bool:
	var unit: Dictionary = scene.battle.unit(id)
	scene._show_cell(Vector2i(unit["x"], unit["y"]))
	if scene.selected_unit != id or not scene.choosing_destination:
		fail("The old context must hold a real active tactical selection")
		return false
	return true


func _cleared(scene: Control) -> bool:
	return (
		scene.selected_unit == -1
		and not scene.choosing_destination
		and not scene.unit_panel.visible
	)


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
