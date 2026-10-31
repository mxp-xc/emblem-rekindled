extends SceneTree

var scene: Control


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	scene = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.settings["music_enabled"] = true
	scene.player.volume_linear = 0
	await key(KEY_ENTER)
	for tick: int in range(7):
		scene.title_screen.tick()
	await key(KEY_ENTER)
	scene.player.seek(10.0)
	await create_timer(0.15).timeout
	var before: float = scene.player.get_playback_position()
	for press: int in range(12):
		await key(KEY_RIGHT)
	if before < 9.9 or scene.player.get_playback_position() < before - 0.05:
		fail("Title selection gestures must preserve the existing music position")
		return
	scene.resume_battle(scene.battle)
	scene.player.seek(10.0)
	await create_timer(0.15).timeout
	before = scene.player.get_playback_position()
	for move: int in range(30):
		var event := InputEventMouseMotion.new()
		event.position = scene.size / 2 + Vector2(move, 0)
		Input.parse_input_event(event)
		await process_frame
	if before < 9.9 or scene.player.get_playback_position() < before - 0.05:
		fail("Pointer motion on the battlefield must preserve the music position")
		return
	scene.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var paused: float = scene.player.get_playback_position()
	await create_timer(0.15).timeout
	if absf(scene.player.get_playback_position() - paused) > 0.1:
		fail("Background music must pause without rewinding")
		return
	scene.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	scene.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.15).timeout
	if scene.player.get_playback_position() < paused - 0.05:
		fail("Repeated focus-in must resume rather than restart the existing music")
		return
	scene.player.stop()
	await create_timer(0.1).timeout
	scene.queue_free()
	await process_frame
	await process_frame
	print("PASS music continuity: title/pointer positions and idempotent foreground resume")
	quit(0)


func key(code: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
