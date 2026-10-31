extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(240, 320)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var title: Control = scene.title_screen
	var factor: float = title.size.x / 240.0
	var prologue: Control = title.get("prologue")
	if prologue == null or not prologue.visible or title.options.visible:
		fail("The original automatic prologue must precede the title menu on app startup")
		return
	title.set_process(false)
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = title.get_global_rect().get_center()
		touch.pressed = pressed
		touch.canceled = not pressed
		Input.parse_input_event(touch)
		await process_frame
	for tick: int in range(7):
		title.tick()
	if not prologue.visible:
		fail("A canceled touch cannot skip the automatic prologue")
		return
	await _key(KEY_ESCAPE)
	if not prologue.visible:
		fail("Back cannot skip the original automatic prologue")
		return
	for tick: int in range(371):
		title.tick()
	if prologue.visible or title.options.visible:
		fail("The source 240x320 prologue completes automatically after 378 updates")
		return
	if title.load_button.size != Vector2(80, 19) * factor:
		fail("The title's actual hit target and font must fit its source-height selector")
		return
	title.refresh_continue(false)
	await _key(KEY_ENTER)
	if (
		not title.options.visible
		or (
			title.options.get_global_rect()
			!= Rect2(60 * factor, 225 * factor, 120 * factor, 19 * factor)
		)
	):
		fail(
			(
				"Any key opens the original compact horizontal title selector: "
				+ str(title.options.get_global_rect())
				+ " visible="
				+ str(title.options.visible)
			)
		)
		return
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	if not title.visible or not scene.save_slots.visible or scene.save_slots.slot != 0:
		fail("Reading without named records must open the original four empty world slots")
		return
	await _key(KEY_ESCAPE)
	await _key(KEY_RIGHT)
	await _key(KEY_ESCAPE)
	if title.options.visible:
		fail("Back closes the title selector to its press-any-key state")
		return
	await _key(KEY_ESCAPE)
	if not title.options.visible or title.get("_selected") != 0:
		fail("Back on press-any-key opens the new-game default when no progress exists")
		return
	for key: int in [KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_ENTER]:
		await _key(key)
	if not scene.menu_layer.visible or scene.menu_layer.page != "help":
		fail("The title help entry must open its own child layer")
		return
	await _key(KEY_ESCAPE)
	if scene.menu_layer.visible or not title.options.visible or title.get("_selected") != 4:
		fail("Back from help returns to the same title selector and keeps its entry selected")
		return
	await _key(KEY_LEFT)
	await _key(KEY_ENTER)
	await _key(KEY_ESCAPE)
	if scene.menu_layer.visible or not title.options.visible or title.get("_selected") != 3:
		fail("Back from settings returns to the same title selector and keeps its entry selected")
		return
	var skipped: Control = load("res://features/dialogue/prologue.gd").new()
	title.add_child(skipped)
	skipped.setup(scene.content)
	skipped.completed.connect(skipped.hide)
	skipped.skip()
	for tick: int in range(6):
		skipped.tick()
	if not skipped.visible:
		fail("Skipping must retain the source six-frame fade before its seventh update")
		return
	skipped.tick()
	if skipped.visible:
		fail("The seventh update must finish the source skip fade")
		return
	skipped.queue_free()
	scene.resume_battle(scene.battle)
	scene._show_title()
	if prologue.visible:
		fail("Returning to the title must not replay the app-start prologue")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS title UI: pre-title automatic prologue, Back disabled, horizontal selector, no replay"
	)
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
