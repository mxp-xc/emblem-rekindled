extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var story: Control = scene.story_player
	var reveal: Dictionary
	var speech: Dictionary
	for step: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if step["kind"] == "revealFaction":
			reveal = step
		if step.get("text", {}).get("sourceTextIndex") == 481:
			speech = step
	scene.map.prepare_opening(scene.content["story"]["initialBattlePresentation"])
	scene.map.view.zoom = 1
	scene.map.set_play_area(Rect2(0, 0, 240, 275))
	scene.map.view.focus_cell(Vector2i(9, 22))
	var south: Vector2 = scene.map.view.center
	story.play([reveal, speech])
	# Original dd10 holds the revealed enemy view for ten 65ms map updates.
	await create_timer(0.48).timeout
	if story.dialogue.visible or scene.map.view.center != south:
		fail("South monsters must retain their view for the source hold before the return camera")
		return
	var deadline: int = Time.get_ticks_msec() + 5000
	while not story.dialogue.visible and Time.get_ticks_msec() < deadline:
		story.advance()  # Ordinary confirmation must not skip animation/hold gates.
		await process_frame
	if not story.dialogue.visible:
		fail("The source hold and return camera must eventually open Alm's 481 dialogue")
		return
	if scene.map.view.center == south:
		fail("Alm's dialogue opens only after the camera returns from the southern monsters")
		return
	var center: Vector2 = scene.map.view.center
	var hero: Dictionary = scene.battle.unit(0)
	var original: Vector2 = scene.map.presentation_positions.get(0, Vector2(hero["x"], hero["y"]))
	scene.map.view.focus_cell(Vector2i(original))
	if not center.is_equal_approx(scene.map.view.center):
		fail("The speaking unit's actual presentation position must own the dialogue camera")
		return
	for update: int in range(10):
		story.advance()
		for tick: int in range(3):
			story.tick()
		await process_frame
		if not story.dialogue.visible:
			break
	# Text 481 has its own dd20 after reading, not an immediate objective/next action.
	await create_timer(0.5).timeout
	if not story.visible:
		fail("The source post-dialogue hold must complete before the story yields to the next step")
		return
	await create_timer(1.0).timeout
	if story.visible:
		fail("The post-dialogue hold must eventually release")
		return
	var northern: Dictionary
	var soldier: Dictionary
	for step: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if step["kind"] == "parallelEntrances":
			northern = step
		if step["kind"] == "unitEntrance" and step["unitId"] == 11:
			soldier = step
	story.play([northern, soldier])
	deadline = Time.get_ticks_msec() + 5000
	var landed: bool = false
	while not landed and Time.get_ticks_msec() < deadline:
		landed = true
		for entrance: Dictionary in northern["units"]:
			var cell := Vector2(entrance["to"][0], entrance["to"][1])
			if not (
				scene
				. map
				. presentation_positions
				. get(int(entrance["unitId"]), Vector2.INF)
				. is_equal_approx(cell)
			):
				landed = false
		await process_frame
	if not landed:
		fail("All six northern monsters must finish their movement")
		return
	var north: Vector2 = scene.map.view.center
	var landed_at: int = Time.get_ticks_msec()
	await create_timer(0.3).timeout
	if scene.map.view.center != north:
		fail("The northern camera must hold after landing before returning to our soldier")
		return
	deadline = Time.get_ticks_msec() + 5000
	while scene.map.view.center == north and Time.get_ticks_msec() < deadline:
		await process_frame
	if Time.get_ticks_msec() - landed_at < 550:
		fail("Northern landing must retain the source nine-update hold, allowing a render frame")
		return
	while story.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	if story.visible or scene.map.presentation_positions.get(11) != Vector2(10, 13):
		fail("Only after the northern hold may the soldier camera and entrance finish")
		return
	scene.queue_free()
	await process_frame
	print("PASS story timing: north landing hold, south reveal/return, unskippable source waits")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
