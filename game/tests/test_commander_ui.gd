extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	scene.battle.wait_unit(0)
	var before: Dictionary = scene.battle.snapshot()
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("commander")
	var commander: Control = scene.menu_layer._commander
	if not commander.visible or commander.get_global_rect() != Rect2(0, 0, 720, 1280):
		fail("Commander configuration must use the original full-screen three-row layout")
		return
	commander.change(0, 1)
	commander.change(1, 1)
	commander.change(2, 1)
	if scene.battle.snapshot() != before or commander.draft["commander"] != 0:
		fail("Editing the selectors must remain a draft, and an acted hero remains selectable")
		return
	var back := InputEventKey.new()
	back.keycode = KEY_ESCAPE
	back.pressed = true
	Input.parse_input_event(back)
	await process_frame
	before["commander"] = 0
	before["commandPolicy"] = 5
	if scene.battle.snapshot() != before or scene.menu_layer.page != "main":
		fail(
			"Returning must commit follow/defend and preserve all actions, positions and inventory"
		)
		return
	scene.queue_free()
	await process_frame
	print("PASS commander UI: original layout, draft selectors, acted candidates, return commit")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
