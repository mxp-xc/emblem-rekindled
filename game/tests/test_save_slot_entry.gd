extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var slots: Control = scene.get_node_or_null("SaveSlots")
	if slots == null:
		fail("Title needs separate temporary-progress and four-world-record entry points")
		return
	var path: String = "user://test_slot_entry_%d.json" % Time.get_ticks_usec()
	scene.battle_store = load("res://persistence/battle_store.gd").new(scene.content, path)
	scene.title_screen.prologue.skip()
	for update: int in range(7):
		scene.title_screen.tick()
	scene.title_screen.refresh_continue(false)
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	if not slots.visible or slots.slot != 0 or not scene.title_screen.visible:
		fail("Without temporary progress, the selected named-read entry opens four empty slots")
		return
	await _key(KEY_ENTER)
	if not slots.visible:
		fail("Empty confirmation must stay in the same slot rather than leave to title")
		return
	await _key(KEY_ESCAPE)
	if (
		slots.visible
		or not scene.title_screen.options.visible
		or not scene.title_screen.load_button.visible
	):
		fail("Back must restore the title's same Read entry before closing its selector")
		return
	await _key(KEY_ESCAPE)
	if scene.title_screen.options.visible:
		fail("A separate Back closes the title selector to press-any-key")
		return
	if not scene.battle_store.write(scene.battle)["ok"]:
		fail("The isolated entry test requires an actual temporary battle record")
		return
	var before: Dictionary = scene.battle.snapshot()
	scene.title_screen.refresh_continue(true)
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	slots = scene.save_slots
	if scene.title_screen.visible or slots.visible or not scene.map.visible:
		fail(
			"The source temporary-progress first entry resumes directly without world slot selection"
		)
		return
	if scene.battle.snapshot() != before:
		fail("Temporary continuation must restore the stored battle unchanged")
		return
	scene._show_title()
	await _key(KEY_ENTER)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	if not slots.visible or slots.slot != 0:
		fail("A temporary record must not hide the separate four-world-record entry")
		return
	await _key(KEY_LEFT)
	await _key(KEY_ESCAPE)
	await _key(KEY_ENTER)
	if not slots.visible or slots.slot != 0:
		fail("Reopening world records must reset the source selector to the first slot")
		return
	DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	print(
		"PASS save entries: empty four-slot read, parent Back, independent temporary continuation"
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
