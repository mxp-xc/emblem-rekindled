extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var setup: Dictionary
	for step: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			setup = step
	scene.story_player.play([setup], scene.battle.command_configuration())
	await process_frame
	var commander: Control = scene.story_player.get("commander")
	if commander == null or not commander.visible:
		fail("Opening must reuse the original full-screen three-row commander configuration")
		return
	await _key(KEY_RIGHT)
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	if not scene.story_player.visible or commander.draft["policy"] != 5:
		fail("Confirm does not submit; the three selectors must retain their draft")
		return
	await _key(KEY_ESCAPE)
	if (
		scene.story_player.visible
		or scene.story_player.selected_commander != 0
		or scene.story_player.get("selected_policy") != 5
	):
		fail("Back commits the chosen commander and follow/defend policy before continuing")
		return
	var route: Dictionary
	for step: Dictionary in scene.content["story"]["sequences"]["victory"]:
		if step["kind"] == "routeChoice":
			route = step
	scene.story_player.play([route])
	await process_frame
	var rows: VBoxContainer = scene.story_player.choices
	var bounds: Rect2 = rows.get_parent().get_global_rect()
	if bounds != Rect2(183, 502, 354, 276):
		fail("The four routes must use the original centered 118x92 native menu")
		return
	await _key(KEY_ESCAPE)
	if not scene.story_player.visible:
		fail("Back cannot dismiss the required route selection")
		return
	await _key(KEY_UP)
	await _key(KEY_ENTER)
	if scene.story_player.visible or scene.story_player.selected_route != 6:
		fail("Up wraps from first to fourth source route and confirm selects that route")
		return
	scene.queue_free()
	await process_frame
	print("PASS story choices: original route geometry, loop/Back/confirm, commander draft/return")
	quit(0)


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
