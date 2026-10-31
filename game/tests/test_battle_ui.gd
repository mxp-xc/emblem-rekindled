extends SceneTree

var rolls: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	Engine.time_scale = 8
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(scene.content, _roll)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = 8
			actor["y"] = 20
		elif actor["id"] == 59:
			actor["x"] = 8
			actor["y"] = 21
	if not battle.restore_snapshot(state)["ok"]:
		fail("Controlled legal combat positions must restore")
		return
	battle.complete_event("level_tutorial")
	scene.resume_battle(battle)
	scene._show_unit_menu(Vector2i(8, 20))
	var before: Dictionary = battle.snapshot()
	var before_rolls: int = rolls
	var attack: Button = scene.get_node("UnitStatus/Status/Actions/Attack")
	if not attack.visible:
		fail("An actionable unit with a reachable enemy must expose Attack")
		return
	attack.pressed.emit()
	await process_frame
	if not scene.target_selection.visible or scene.target_selection.page != "items":
		fail("Attack must first open weapon selection")
		return
	scene.target_selection.find_child("Weapon_9", true, false).pressed.emit()
	if scene.target_selection.page != "targets":
		fail("Confirming a weapon must enter map target selection")
		return
	if scene.map.movement.size() != 4 or not scene.map.movement.has(Vector2i(9, 20)):
		fail("Attack must show the complete weapon range, including unoccupied squares")
		return
	scene._show_cell(Vector2i(8, 21))
	if scene.target_selection.page != "forecast":
		fail("Confirming a map target must open the forecast before committing combat")
		return
	await _key(KEY_RIGHT)
	if (
		scene.target_selection.target_id != 59
		or battle.snapshot() != before
		or rolls != before_rolls
	):
		fail("Forecast directions must not change targets, consume RNG or modify the battle")
		return
	for expected: String in ["targets", "items", "actions"]:
		await _key(KEY_ESCAPE)
		if expected == "actions":
			if scene.target_selection.visible or not scene.unit_panel.visible:
				fail("Back from weapons must return to actions")
				return
		elif scene.target_selection.page != expected:
			fail("Back must return through forecast, targets and weapons one level at a time")
			return
		if expected == "items" and not scene.map.movement.is_empty():
			fail("Returning to weapons must clear the previous target range")
			return
	if battle.snapshot() != before or rolls != before_rolls:
		fail("Cancelling an attack must leave HP, durability, action and RNG untouched")
		return
	attack.pressed.emit()
	await process_frame
	scene.target_selection.find_child("Weapon_9", true, false).pressed.emit()
	scene._show_cell(Vector2i(8, 21))
	await _key(KEY_ENTER)
	if not scene.busy or not scene.battle_view.playing or scene.map.selection_enabled:
		fail("Confirming a forecast must enter independent combat and lock map input")
		return
	var committed: Dictionary = battle.snapshot()
	var committed_rolls: int = rolls
	await _key(KEY_ENTER)
	await _key(KEY_ESCAPE)
	while scene.busy:
		await process_frame
	if scene.battle_view.visible or battle.unit(0)["action"] != 2:
		fail("Independent combat must finish and return to the map with the action consumed")
		return
	if battle.snapshot() != committed or rolls != committed_rolls:
		fail("Animation and repeated input must not resolve combat or consume randomness again")
		return
	if scene.menu_button.disabled or not scene.map.selection_enabled:
		fail("The map must unlock after the final battle frame")
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	print(
		"PASS battle UI: weapons, map targets, forecast, layered Back, combat lock, single settlement"
	)
	quit(0)


func _key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _roll(limit: int) -> int:
	rolls += 1
	return mini(50, limit - 1)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
