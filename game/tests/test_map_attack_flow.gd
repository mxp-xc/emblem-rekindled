extends SceneTree

const Session = preload("res://app/chapter_session.gd")
var _draws: int = 0
var _record_directory: String = ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var owned_directory: String = "user://test_map_attack_flow_%d" % Time.get_ticks_usec()
	if (
		DirAccess.dir_exists_absolute(owned_directory)
		or DirAccess.make_dir_absolute(owned_directory) != OK
	):
		fail("Scene integration must own a new isolated record directory")
		return
	_record_directory = owned_directory
	scene.store.path = _record_directory.path_join("settings.json")
	scene.battle_store.path = _record_directory.path_join("battle_save.json")
	scene.title_screen.prologue.hide()
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	var speed: Button = scene.menu_layer.find_child("GameSpeed", true, false)
	speed.pressed.emit()
	scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	if Engine.time_scale != 32:
		fail("The flow fixture must accelerate through the actual session-speed setting")
		return
	var session := Session.new()
	var opened: Dictionary = session.open(
		"res://content/chapter_1/chapter.json", "", {"new": true}, _roll
	)
	for next_battle: String in ["m1", "m2"]:
		if not opened["ok"]:
			fail("The map-action flow must start from real chapter content")
			return
		opened["battle"].win_with_assistance()
		var completed: Dictionary = opened["battle"].complete_victory(0)
		if not completed["ok"]:
			fail("The configured world route must produce a valid m2 frontier")
			return
		opened = session.open(
			"res://content/chapter_1/chapter.json",
			next_battle,
			{"progress": completed["progress"]},
			_roll
		)
	if not opened["ok"]:
		fail("The actual m2 player mage must be available through its world entry")
		return
	scene._adopt_content(opened["content"], opened["battle"])
	var battle: RefCounted = opened["battle"]
	var initial: Dictionary = battle.snapshot()
	initial["round"] = 3
	for actor: Dictionary in initial["units"]:
		if actor["id"] == 7:
			actor["x"] = 17
			actor["y"] = 9
			actor["inventory"] = [
				{"id": "map-flow:wind", "templateId": 50, "durability": 14},
				{"id": "map-flow:quake", "templateId": 46, "durability": 5}
			]
			actor["equippedInstanceId"] = "map-flow:wind"
		elif actor["id"] == 33:
			actor["x"] = 19
			actor["y"] = 9
		elif actor["id"] == 32:
			actor["x"] = 19
			actor["y"] = 10
	if not battle.restore_snapshot(initial)["ok"]:
		fail("The integration fixture must begin with a validated actual-map snapshot")
		return
	# The world entry and mage are real m2 content; only the held magic and
	# target positions are controlled so the UI flow is short and repeatable.
	scene.resume_battle(battle)
	scene.selected_unit = 7
	_draws = 0
	var before: Dictionary = battle.snapshot()
	scene._unit_intent("attack", {})
	scene.target_selection.find_child("Weapon_50", true, false).pressed.emit()
	await process_frame
	if scene.target_selection.page != "targets":
		fail("Area magic must retain the real target-selection page")
		return
	scene._show_cell(Vector2i(19, 9))
	await process_frame
	if scene.target_selection.page != "map_forecast" or scene.map.affected_cells.is_empty():
		fail("Main must route area magic into its multi-target forecast and affected-cell overlay")
		return
	scene.target_selection.go_back()
	scene.target_selection.go_back()
	if battle.snapshot() != before or _draws != 0:
		fail(
			"Area preview and both Back steps must not equip, consume, act or draw combat randomness"
		)
		return
	scene.target_selection.find_child("Weapon_50", true, false).pressed.emit()
	scene._show_cell(Vector2i(19, 9))
	scene.target_selection.find_child("Confirm", true, false).pressed.emit()
	await process_frame
	if not scene.map_attack_player.playing or scene.battle_view.visible:
		fail(
			"Confirmed map magic must use the real tactical-map player and never the independent view"
		)
		return
	if not await _wait_for_action(scene):
		return
	if battle.unit(7)["inventory"][0]["durability"] != 13 or battle.unit(7)["action"] != 2:
		fail("The full area flow must commit exactly one cast and then release tactical input")
		return
	if scene.map.presentation_offset != Vector2.ZERO or scene.target_selection.visible:
		fail("Finished playback must clear presentation offsets and its modal selector")
		return
	if not battle.restore_snapshot(initial)["ok"]:
		fail("The second controlled flow must restore the same validated stable snapshot")
		return
	scene.resume_battle(battle)
	scene.selected_unit = 7
	scene._unit_intent("attack", {})
	scene.target_selection.find_child("Weapon_46", true, false).pressed.emit()
	await process_frame
	if scene.target_selection.page != "map_forecast" or scene.target_selection.target_id != -1:
		fail("All-hostile magic must open a complete preview without inventing a primary target")
		return
	scene.target_selection.go_back()
	if scene.target_selection.page != "items" or battle.unit(7)["action"] != 0:
		fail("Back from all-hostile preview must retain the selected item without committing")
		return
	scene.target_selection.find_child("Weapon_46", true, false).pressed.emit()
	scene.target_selection.find_child("Confirm", true, false).pressed.emit()
	if not await _wait_for_action(scene):
		return
	var quake: Array = battle.unit(7)["inventory"].filter(
		func(item: Dictionary) -> bool: return item["id"] == "map-flow:quake"
	)
	if (
		quake.size() != 1
		or quake[0]["durability"] != 4
		or scene.map.presentation_offset != Vector2.ZERO
	):
		fail("Earthquake must consume once and restore a stable map after its original shake/flash")
		return
	var automatic: Dictionary = initial.duplicate(true)
	for actor: Dictionary in automatic["units"]:
		if actor["id"] == 35:
			actor["inventory"] = [{"id": "map-flow:auto-quake", "templateId": 46, "durability": 5}]
			actor["equippedInstanceId"] = "map-flow:auto-quake"
			actor["visible"] = true
			actor["flags"] &= ~1
		elif actor["id"] in [0, 7, 82]:
			actor["visible"] = true
			actor["flags"] &= ~1
		else:
			actor["visible"] = false
			actor["flags"] |= 1
	if not battle.restore_snapshot(automatic)["ok"]:
		fail("The automatic-flow boundary must restore a valid stable player phase")
		return
	scene.resume_battle(battle)
	scene._end_turn()
	if not await _wait_for_action(scene):
		return
	if (
		battle.phase != 0
		or battle.round_number != 4
		or battle.unit(35)["inventory"][0]["durability"] != 4
	):
		fail(
			"The real enemy-phase loop must cast its all-hostile plan and return to the next round"
		)
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	if not _cleanup_records():
		quit(1)
		return
	print(
		"PASS map attack flow: actual Main, area/all-hostile preview, Back, cast and tactical playback"
	)
	quit(0)


func _wait_for_action(scene: Control) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	var saw_map_player: bool = false
	while scene.busy and Time.get_ticks_msec() < deadline:
		saw_map_player = saw_map_player or scene.map_attack_player.playing
		if scene.action_feedback.current_step.get("kind") == "tutorial":
			# The assisted frontier has not read the normal first-XP tutorial.
			# Advance its existing Back interaction instead of suppressing it.
			scene.action_feedback.go_back()
		if scene.battle_view.visible:
			fail("A map-attack flow must never enter the independent battle view")
			return false
		await process_frame
	if scene.busy or not saw_map_player:
		fail("A committed map action must finish its player and release input")
		return false
	return true


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func fail(message: String) -> void:
	push_error(message)
	_cleanup_records()
	quit(1)


func _cleanup_records() -> bool:
	if _record_directory.is_empty() or not DirAccess.dir_exists_absolute(_record_directory):
		return true
	for name: String in DirAccess.get_files_at(_record_directory):
		if DirAccess.remove_absolute(_record_directory.path_join(name)) != OK:
			push_error("Cannot remove an owned map-attack test record: " + name)
			return false
	if DirAccess.remove_absolute(_record_directory) != OK:
		push_error("Cannot remove the owned map-attack test record directory")
		return false
	_record_directory = ""
	return true
