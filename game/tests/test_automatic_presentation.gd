extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	Engine.time_scale = 4
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		scene.content, func(limit: int) -> int: return limit - 1
	)
	var state: Dictionary = battle.snapshot()
	# Controlled legal positions: the real planner must move enemy 59 and choose its target.
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 1 or (actor["faction"] == 2 and actor["id"] != 59):
			actor["visible"] = false
		if actor["id"] == 0:
			actor["x"] = 8
			actor["y"] = 14
		elif actor["id"] == 59:
			actor["x"] = 8
			actor["y"] = 17
	if not battle.restore_snapshot(state)["ok"]:
		fail("The controlled enemy presentation position must restore as a stable battle")
		return
	battle.complete_event("reinforcements")
	battle.complete_event("level_tutorial")
	scene.resume_battle(battle)
	scene._end_turn()
	var stages: Array[String] = []
	var deadline: int = Time.get_ticks_msec() + 15000
	while scene.busy and Time.get_ticks_msec() < deadline:
		var map: Control = scene.map
		var stage: String = ""
		if map.range_kind == "enemy" and not map.movement.is_empty():
			stage = "range"
			if not map.animation_positions.is_empty():
				stage = "moving"
			elif not map.route.is_empty():
				stage = "route"
		elif map.range_kind == "attack" and not map.target_cells.is_empty():
			stage = "target"
			if not map.movement.has(map.selected):
				fail("The chosen enemy target must be visibly inside its attack range")
				return
		elif scene.battle_view.playing:
			stage = "combat"
		if not stage.is_empty() and (stages.is_empty() or stages[-1] != stage):
			stages.append(stage)
		await process_frame
	if scene.busy or stages != ["range", "route", "moving", "target", "combat"]:
		fail(
			(
				"The real enemy planner must show range/route/movement/target/combat in order: "
				+ str(stages)
			)
		)
		return
	if not scene.map.movement.is_empty() or not scene.map.route.is_empty():
		fail("Returning to the player must clear automatic action previews")
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	print("PASS automatic presentation: real planner, ordered enemy range/route/move/target/combat")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
