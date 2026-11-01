extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	Engine.time_scale = 32
	var main_scene: PackedScene = load("res://app/main.tscn")
	var scene: Control = main_scene.instantiate()
	root.add_child(scene)
	await process_frame
	if Engine.time_scale != 1:
		fail("Each application instance must start at normal speed")
		return
	var directory: String = "user://test_session_speed_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	var settings_path: String = directory.path_join("settings.json")
	var battle_path: String = directory.path_join("battle_save.json")
	scene.store = load("res://persistence/settings_store.gd").new(settings_path)
	scene.battle_store = load("res://persistence/battle_store.gd").new(scene.content, battle_path)
	scene.store.write(scene.settings)
	scene.battle_store.write(scene.battle)
	var settings_bytes: PackedByteArray = FileAccess.get_file_as_bytes(settings_path)
	var battle_bytes: PackedByteArray = FileAccess.get_file_as_bytes(battle_path)
	scene.title_screen.prologue.hide()
	scene._set_menu_visible(true)
	var menu: Control = scene.menu_layer
	var speed: Button = menu.find_child("GameSpeed", true, false)
	if speed == null or not speed.is_visible_in_tree() or not speed.text.contains("1×"):
		fail("Title settings must expose the current session speed")
		return
	await click(speed)
	if menu.page != "speed":
		fail("Game speed must open its own selectable rates")
		return
	menu.go_back()
	if menu.page != "settings" or Engine.time_scale != 1:
		fail("Returning without selecting a rate must keep normal speed")
		return
	await click(speed)
	await click(menu.find_child("Speed_32", true, false))
	if Engine.time_scale != 32 or menu.page != "settings" or not speed.text.contains("32×"):
		fail("A real settings click must immediately apply and display 32x")
		return
	if (
		FileAccess.get_file_as_bytes(settings_path) != settings_bytes
		or FileAccess.get_file_as_bytes(battle_path) != battle_bytes
		or scene.settings.has("speed")
	):
		fail("Session speed must not write settings or continuation records")
		return
	scene._set_menu_visible(false)
	scene.resume_battle(scene.battle)
	scene.set_process(false)
	scene._played_seconds = 0
	scene._process(32)
	if not is_equal_approx(scene._played_seconds, 1):
		fail("Recorded play time must measure real foreground time independently of game speed")
		return
	scene._set_menu_visible(true)
	menu.show_page("settings")
	if Engine.time_scale != 32 or not speed.text.contains("32×"):
		fail("Title and battle menus must retain the same session rate")
		return
	var second: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json", "m1"
	)
	scene._adopt_content(second)
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	if (
		Engine.time_scale != 32
		or not scene.menu_layer.find_child("GameSpeed", true, false).text.contains("32×")
	):
		fail("Changing battle content must preserve the session speed and its label")
		return
	scene.queue_free()
	await process_frame
	scene = main_scene.instantiate()
	root.add_child(scene)
	await process_frame
	if Engine.time_scale != 1:
		fail("A restarted application must reset a previously accelerated session")
		return
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(settings_path)
	DirAccess.remove_absolute(battle_path)
	DirAccess.remove_absolute(directory)
	print(
		"PASS session speed: real UI, cancel, immediate rate, no persistence, cross-battle and restart"
	)
	quit(0)


func click(button: Button) -> void:
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
	Engine.time_scale = 1
	push_error(message)
	quit(1)
