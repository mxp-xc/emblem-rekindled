extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var map: Control = scene.map
	scene.map_hud.hide()
	await process_frame
	if not is_equal_approx(map.play_area.end.y, scene.size.y):
		fail("Opening without a HUD must use the full screen instead of reserving a black footer")
		return
	map.prepare_opening(scene.content["story"]["initialBattlePresentation"])
	if not map.has_method("visible_units"):
		fail("Rendering and map hit testing must share the actual presentation visibility")
		return
	if map.visible_units().size() != 9:
		fail("Only the nine source opening actors may appear before the northern entrance")
		return
	Engine.time_scale = 10
	var north: Dictionary
	var south: Dictionary
	var preview: Array = []
	var collecting: bool = false
	for step: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if step["kind"] == "parallelEntrances":
			north = step
			collecting = true
		elif step["kind"] == "revealFaction":
			south = step
		if step["kind"] == "unitEntrance" and step["unitId"] == 11:
			collecting = false
		if collecting:
			preview.append(step)
	await scene.story_player.play([north])
	if map.visible_units().size() != 19:
		fail(
			"The northern preview must include all ten northern units while southern enemies stay hidden"
		)
		return
	for id: int in [48, 49, 51, 57]:
		var shown: bool = false
		for actor: Dictionary in map.visible_units():
			if actor["id"] == id:
				shown = true
		if not shown:
			fail("Both northern flanks must reveal their flying units before the camera leaves")
			return
	map.view.focus_cell(Vector2i(8, 11))
	var seen: Dictionary = {}
	scene.story_player.play(preview)
	while scene.story_player.visible:
		var viewport := Rect2(map.view.viewport_origin, map.view.viewport_size)
		for actor: Dictionary in map.visible_units():
			if actor["id"] not in [48, 49, 51, 57]:
				continue
			var used: Rect2i
			for frame: Texture2D in map.animation_frames[int(actor["id"])]:
				var alpha: Rect2i = frame.get_image().get_used_rect()
				used = used.merge(alpha) if used.has_area() else alpha
			var offset := Vector2(actor["spriteOffsetX"], actor["spriteOffsetY"])
			var sprite := Rect2(
				(
					map.view.screen_at(Vector2(actor["x"], actor["y"]))
					+ (offset + Vector2(used.position)) * map.view.zoom
				),
				Vector2(used.size) * map.view.zoom
			)
			if viewport.grow(0.1).encloses(sprite):
				seen[int(actor["id"])] = true
		await process_frame
	if seen.size() != 4:
		fail(
			"The northern preview must actually frame all four flying sprites on a default portrait screen"
		)
		return
	await scene.story_player.play([south])
	if map.visible_units().size() != 29:
		fail("The southern reveal must release the integer faction imported from JSON")
		return
	map.prepare_opening(scene.content["story"]["initialBattlePresentation"])
	if map.visible_units().size() != 9:
		fail("Restarting an opening must reset its previous reveals")
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	print(
		"PASS opening: full-height map, nine/nineteen/twenty-nine actors, northern birds, restart"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
