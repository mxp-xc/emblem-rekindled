extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var map: Control = scene.map
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
	for step: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if step["kind"] == "parallelEntrances":
			north = step
		elif step["kind"] == "revealFaction":
			south = step
	await scene.story_player.play([north])
	if map.visible_units().size() != 15:
		fail("The northern entrance must reveal six actors while southern enemies stay hidden")
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
	print("PASS opening visibility: actual JSON metadata, nine/fifteen/twenty-nine actors, restart")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
