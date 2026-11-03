extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var directory: String = "user://test_assistance_ui_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	scene.store.path = directory.path_join("settings.json")
	scene.battle_store.path = directory.path_join("continue.json")
	scene.resume_battle(scene.battle)
	await click(scene.menu_button)
	await click(find_button(scene.menu_layer, "辅助功能"))
	if scene.menu_layer.page != "assistance":
		fail("A normal playable battle must open assistance through its real menu buttons")
		return
	for key: String in ["share_experience", "full_growth"]:
		var toggle: Button = scene.menu_layer.find_child(key, true, false)
		if toggle.button_pressed:
			fail("Assistance must default to disabled")
			return
		await click(toggle)
		if not toggle.button_pressed or not scene.settings[key] or not scene.battle.get(key):
			fail("A real switch click must immediately apply and persist assistance")
			return
		if not scene.store.read()["settings"][key]:
			fail("Assistance must survive a settings store reload")
			return
	await click(find_button(scene.menu_layer, "直接通关"))
	if scene.menu_layer.page != "confirm_victory":
		fail("A normal playable battle must open assisted victory confirmation")
		return
	scene.menu_layer.go_back()
	if scene.menu_layer.page != "assistance" or not scene.battle.outcome.is_empty():
		fail("Cancel must return without winning")
		return
	if scene.menu_layer.find_child("AssistedVictory", true, false).button_pressed:
		fail("Canceled assisted victory must reset its switch")
		return
	root.size = Vector2i(1280, 720)
	await process_frame
	scene._set_menu_visible(false)
	scene.map.set_zoom(scene.map.view.minimum_zoom())
	await click(scene.menu_button)
	await click(find_button(scene.menu_layer, "辅助功能"))
	if scene.menu_layer.page != "assistance":
		fail("Assistance must remain reachable on a landscape overview map")
		return
	var next_battle: RefCounted = load("res://gameplay/battle_state.gd").new(scene.content)
	scene.resume_battle(next_battle)
	if not next_battle.share_experience or not next_battle.full_growth:
		fail("Loading a different battle must apply the current assistance settings")
		return
	next_battle.win_with_assistance()
	var progress: Dictionary = next_battle.complete_victory(0)["progress"]
	var opened: Dictionary = load("res://app/chapter_session.gd").new().open(
		"res://content/chapter_1/chapter.json", "m1", {"progress": progress}
	)
	if not opened["ok"]:
		fail("Cross-battle fixture must open the actual next battle")
		return
	scene._adopt_content(opened["content"], opened["battle"])
	scene.resume_battle(opened["battle"])
	next_battle = scene.battle
	if not next_battle.share_experience or not next_battle.full_growth:
		fail("Actual content changes must retain both assistance options")
		return
	scene._set_menu_visible(true)
	await click(find_button(scene.menu_layer, "辅助功能"))
	for key: String in ["share_experience", "full_growth"]:
		await click(scene.menu_layer.find_child(key, true, false))
		if scene.settings[key] or next_battle.get(key):
			fail("Both persistent assistance options must be switchable off")
			return
	DirAccess.remove_absolute(scene.store.path)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print("PASS assistance UI: real battle menu, confirmation and cancellation")
	quit(0)


func find_button(parent: Node, text: String) -> Button:
	for button: Node in parent.find_children("*", "Button", true, false):
		if button.text == text and button.is_visible_in_tree():
			return button
	return null


func click(button: Button) -> void:
	if button == null:
		fail("Required visible menu button is missing")
		return
	await process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
