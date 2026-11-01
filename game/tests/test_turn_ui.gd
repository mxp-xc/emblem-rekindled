extends SceneTree

var seen_lines: Array[int] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	Engine.time_scale = 8
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		scene.content, func(limit: int) -> int: return mini(50, limit - 1)
	)
	scene.resume_battle(battle)
	var advance := Timer.new()
	advance.wait_time = 0.1
	advance.timeout.connect(
		func() -> void:
			if scene.story_player.visible and scene.story_player.dialogue.visible:
				var index: int = scene.story_player.current_text_index
				if index not in seen_lines:
					seen_lines.append(index)
				scene.story_player.advance()
	)
	scene.add_child(advance)
	advance.start()
	scene._menu_intent("end_turn", {})
	await process_frame
	if not scene.busy or not scene.menu_button.disabled or scene.map.selection_enabled:
		fail("Automatic phases must lock player actions and the system menu")
		return
	scene._handle_back()
	if scene.menu_layer.visible:
		fail("Back during an automatic phase must not open an actionable menu")
		return
	var enemy_stages: Array[String] = []
	while scene.busy:
		if scene.map.range_kind == "enemy" and not scene.map.movement.is_empty():
			var stage: String = "range"
			if not scene.map.animation_positions.is_empty():
				stage = "moving"
			elif not scene.map.route.is_empty():
				stage = "route"
			if stage not in enemy_stages:
				enemy_stages.append(stage)
		await process_frame
	if enemy_stages != ["range", "route", "moving"]:
		fail(
			(
				"Enemy actions must visibly show a distinct field, planned route and actual movement: "
				+ str(enemy_stages)
			)
		)
		return
	if battle.phase != 0 or battle.round_number != 2 or not battle.can_save():
		fail("The end-turn menu must play allied/enemy actions and return to a stable player turn")
		return
	if seen_lines != [482, 483, 484] or not battle.event_completed("reinforcements"):
		fail("First-turn reinforcement dialogue must play exactly once in source order")
		return
	if (
		scene.menu_button.disabled
		or not scene.menu_button.visible
		or not scene.map.selection_enabled
	):
		fail(
			"The visible system menu and map input must return after automatic phases and reinforcement"
		)
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	print("PASS turn UI: automatic actions, input lock, reinforcement dialogue, player return")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
