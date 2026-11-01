extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(240, 320)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var story: Control = scene.story_player
	if not story.has_method("tick"):
		fail("The world entrance needs the original update clock, not a wall-time delay")
		return
	story.set_process(false)
	var hud: Control = story.get_node_or_null("WorldHud")
	var factor: float = story.size.x / 240.0
	if hud == null or hud.get_global_rect() != Rect2(0, 275 * factor, story.size.x, 45 * factor):
		fail("The world map must retain its original bottom 45px blue place-name strip")
		return
	var place: Label = hud.get("_name")
	if place.text != "皇都荒野" or not is_equal_approx(place.get_rect().get_center().x, 120 * factor):
		fail("The world node name must be centered in the original HUD")
		return
	if not is_equal_approx(place.position.y, 15 * factor):
		fail("The original world place-name top anchor is fifteen pixels into the HUD")
		return
	var circle: Control = story.get_node("WorldMap/WorldCircle")
	if not circle.clip_contents or circle.size != Vector2(24, 24):
		fail("The original circle needs its own 24x24 local clipping rectangle")
		return
	story.play(scene.content["story"]["sequences"]["newGame"])
	await process_frame
	if story.world_revealed:
		fail("World narration precedes revealing node zero and Alm")
		return
	for press: int in range(30):
		if not story.dialogue.visible:
			break
		story.advance()
		if not story.dialogue.visible:
			break
		for update: int in range(3):
			story.tick()
	if story.dialogue.visible or story.world_update != 0 or story.world_revealed:
		fail("Closing narration must leave update zero empty before the first reveal")
		return
	var actor: Dictionary = scene.content["mapAnimations"]["units"]["0"]
	var frame: Texture2D = load(
		scene.content["entry"]["mapAnimations"].get_base_dir().path_join(
			actor["frames"][0]["texture"]
		)
	)
	if (
		story.get("_world_actor_frames")[0] != frame
		or story.get("_world_actor_offset") != Vector2(-24, -24)
	):
		fail("World Alm must reuse his original fixed frame and padded-canvas offset")
		return
	var phases: Array[int] = []
	for update: int in range(1, 21):
		story.tick()
		phases.append(story.world_circle_phase)
		if not story.visible or story.background == null or not story.world_revealed:
			fail("Alm and the world node must remain visible through update twenty")
			return
		if story.world_actor_frame != 0:
			fail("The entrance must keep Alm's fixed source frame rather than cycle map idle")
			return
	if phases.slice(0, 7) != [0, 0, 1, 1, 2, 2, -1] or phases.slice(7).any(func(p): return p != -1):
		fail("The world circle needs three two-update states, then disappears while Alm waits")
		return
	story.tick()
	if story.visible or story.background != null:
		fail("Update twenty-one must enter the first battle without an extra confirmation")
		return
	if scene.player.stream != load(scene.content["entry"]["music"]):
		fail("Entering the battle must replace world music with map music")
		return
	scene.queue_free()
	await process_frame
	print("PASS world entrance: hidden narration, fixed Alm, six circle frames, update21 map")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
