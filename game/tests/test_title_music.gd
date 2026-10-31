extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.title_screen.set_process(false)
	scene.settings["music_enabled"] = true
	scene.music_started = false
	scene.player.stop()
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = scene.size / 2
		touch.pressed = pressed
		touch.canceled = not pressed
		Input.parse_input_event(touch)
		await process_frame
	if scene.music_started:
		fail("A canceled touch is not a title music unlock gesture")
		return
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await process_frame
	if not scene.music_started or not scene.player.playing:
		fail("The first key that skips the prologue must unlock enabled title music")
		return
	scene.music_started = false
	scene.player.stop()
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = scene.size / 2
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await process_frame
	if not scene.music_started or not scene.player.playing:
		fail("A valid touch that skips the prologue must also unlock enabled title music")
		return
	scene.player.stop()
	await create_timer(0.1).timeout
	scene.queue_free()
	await process_frame
	print("PASS title music: first keyboard/touch skip unlock, canceled touch ignored")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
