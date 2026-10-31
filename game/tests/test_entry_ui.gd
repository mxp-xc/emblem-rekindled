extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	if not scene.has_method("start_new_game") or scene.get_node_or_null("TitleScreen") == null:
		fail("The game must enter a start/load screen rather than dropping directly into battle")
		return
	if not scene.title_screen.visible or scene.menu_button.visible:
		fail("The title screen must own input before starting a game")
		return
	if not scene.title_screen.prologue.visible:
		fail("The source boot prologue must precede starting a new game")
		return
	var skip := InputEventKey.new()
	skip.keycode = KEY_ENTER
	skip.pressed = true
	Input.parse_input_event(skip)
	await create_timer(0.6).timeout
	scene.start_new_game()
	var seen: Array[int] = [458]
	var deadline: int = Time.get_ticks_msec() + 35000
	while scene.busy and Time.get_ticks_msec() < deadline:
		await process_frame
		var story: Control = scene.story_player
		if story.visible:
			if story.current_text_index >= 0 and story.current_text_index not in seen:
				seen.append(story.current_text_index)
			if story.dialogue.visible:
				story.advance()
			elif story.choices.visible:
				for child: Node in story.choices.get_children():
					if child.name == "Choice_0":
						child.pressed.emit()
			elif story.commander.visible:
				story.commander.change(0, 1)
				story.go_back()
		await create_timer(0.02).timeout
	if scene.busy or not scene.battle.event_completed("opening") or scene.battle.commander_id != 0:
		fail("Opening must complete and apply the selected commander before player input")
		return
	for index: int in [458, 460, 477, 478, 479, 480, 481, 156, 455]:
		if index not in seen:
			fail("Missing original story text index: " + str(index))
			return
	if (
		not scene.map.presentation_positions.is_empty()
		or not scene.map.presentation_hidden_factions.is_empty()
	):
		fail("Opening overrides must clear without changing authoritative deployment")
		return
	var snapshot: Dictionary = scene.battle.snapshot()
	scene.resume_battle(scene.battle)
	if (
		scene.story_player.visible
		or scene.battle.snapshot() != snapshot
		or not scene.menu_button.visible
	):
		fail("Loading a stable battle must resume without replaying opening or resetting state")
		return
	scene.queue_free()
	await process_frame
	print("PASS entry: title, original prologue/world/dialogue, commander, tutorial, stable resume")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
