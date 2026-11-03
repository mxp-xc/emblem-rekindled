extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var step: Dictionary
	for candidate: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if candidate.get("text", {}).get("sourceTextIndex") == 478:
			step = candidate
	scene.story_player.play([step])
	await process_frame
	var dialogue: Control = scene.story_player.get("dialogue")
	if dialogue == null:
		fail("Original story dialogue needs its two-line pixel message panel")
		return
	if dialogue.panel_rect != Rect2(0, 1136, 720, 144):
		fail("The original dialogue strip must occupy the bottom 48 native pixels")
		return
	if dialogue.portrait.size != Vector2(165, 165) or dialogue.speaker_label.visible:
		fail("Portrait dialogue uses the original 55px face without a separate name row")
		return
	await _cancel_touch(dialogue.panel_rect.get_center())
	if dialogue.line_index != 0:
		fail("A canceled touch must not advance a character's dialogue")
		return
	await _key(KEY_ESCAPE)
	if not scene.story_player.visible or dialogue.line_index != 1:
		fail("Back advances one dialogue line rather than skipping the entire speech")
		return
	await _key(KEY_ESCAPE)
	if dialogue.line_index != 1:
		fail("Scrolling must settle before a second line can be advanced")
		return
	for press: int in range(20):
		await create_timer(0.21).timeout
		await _key(KEY_ENTER)
		if not scene.story_player.visible:
			break
	if scene.story_player.visible:
		fail("The original long speech must eventually return to the map")
		return
	var instruction: Dictionary
	for candidate: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if candidate["kind"] == "instruction":
			instruction = candidate
	scene.story_player.play([instruction])
	await process_frame
	if dialogue.portrait.visible or dialogue.speaker_label.visible:
		fail("The source commander instruction is an unvoiced brown strip, not Alm's portrait")
		return
	for press: int in range(30):
		await create_timer(0.21).timeout
		await _key(KEY_ENTER)
		if not scene.story_player.visible:
			break
	var objective: Dictionary
	for candidate: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if candidate["kind"] == "objective":
			objective = candidate
	scene.story_player.play([objective])
	await process_frame
	if dialogue.panel_rect.size != Vector2(720, 201) or dialogue.heading_label.text != "皇都荒野":
		fail("The objective is the source 67px centered strip with its battle heading")
		return
	await _cancel_touch(dialogue.panel_rect.get_center())
	if not scene.story_player.visible:
		fail("A canceled touch must not confirm the objective")
		return
	await _key(KEY_ESCAPE)
	await _key(KEY_DOWN)
	if not scene.story_player.visible:
		fail("The objective must wait for confirmation and ignore Back/Down")
		return
	await _key(KEY_ENTER)
	if scene.story_player.visible:
		fail("Confirm must close the objective and return to the map")
		return
	scene.story_player.play([scene.content["story"]["sequences"]["newGame"][0]])
	await process_frame
	if not dialogue.portrait.visible or dialogue.portrait.position != Vector2(555, 1115):
		fail("The world narration uses the source 55px portrait on the right edge")
		return
	for press: int in range(20):
		await _key(KEY_ENTER)
		await create_timer(0.21).timeout
		if not scene.story_player.visible:
			break
	for speaker_name: String in ["", "利盖鲁军"]:
		scene.story_player.data["story"]["speakers"]["50"] = {
			"id": 50, "name": speaker_name, "faction": 2
		}
		scene.story_player.play(
			[
				{
					"kind": "dialogue",
					"text": {"sourceTextIndex": 580, "speakerId": 50, "text": "敌袭！！敌袭！！"}
				}
			]
		)
		var speech_deadline: int = Time.get_ticks_msec() + 10000
		while (
			(scene.story_player.current_text_index != 580 or not dialogue.visible)
			and Time.get_ticks_msec() < speech_deadline
		):
			await process_frame
		if scene.story_player.current_text_index != 580 or not dialogue.visible:
			fail("Enemy speech must finish its speaker focus before displaying the message")
			return
		if (
			dialogue.portrait.visible
			or dialogue.speaker_label.visible != (not speaker_name.is_empty())
			or dialogue.speaker_label.text != speaker_name
			or dialogue.get("_tone") != "enemy"
		):
			fail("Enemy speech preserves its tone and displays only an explicitly supplied name")
			return
		await _key(KEY_ENTER)
		if scene.story_player.visible:
			fail("An unnamed enemy line must confirm through the same story input flow")
			return
	scene.story_player.data["story"]["speakers"].erase("50")
	Engine.time_scale = 8
	scene.story_player.play(scene.content["story"]["sequences"]["defeat"])
	await process_frame
	if dialogue.get("notice_mode") != true or dialogue.panel_rect.size != Vector2(720, 84):
		fail("Game over must be the source 28px timed center strip")
		return
	if (
		scene.player.stream != load(scene.content["entry"]["defeatMusic"])
		or scene.player.stream.loop
	):
		fail("The game-over sequence replaces the map BGM with the source single-play music")
		return
	await _key(KEY_ESCAPE)
	await _key(KEY_ENTER)
	if not scene.story_player.visible:
		fail("Neither Back nor confirmation may dismiss the original timed game-over strip")
		return
	await create_timer(3.0).timeout
	if scene.story_player.visible:
		fail("The source game-over strip must expire after forty-one logical updates")
		return
	Engine.time_scale = 1
	scene.queue_free()
	await process_frame
	print("PASS story UI: original bottom strip, portrait, layered reading, scroll lock and return")
	quit(0)


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _cancel_touch(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = position
		event.pressed = pressed
		event.canceled = not pressed
		Input.parse_input_event(event)
		await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
