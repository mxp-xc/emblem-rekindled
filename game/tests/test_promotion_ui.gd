extends SceneTree

var _scene: Control
var _draws: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	var opened: Dictionary = _m1()
	if not _expect(opened["ok"], "Open first actually reachable crest battle"):
		return
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.title_screen.prologue.hide()
	_scene._set_menu_visible(true)
	_scene.menu_layer.show_page("settings")
	_scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	_scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	_scene._set_menu_visible(false)
	if not await _manual() or not await _automatic_and_battle():
		return
	_scene.queue_free()
	await process_frame
	print(
		"PASS promotion Main: cancellation, merged feedback, automatic rebind and new-class battle"
	)
	quit(0)


func _m1() -> Dictionary:
	var session: RefCounted = load("res://app/chapter_session.gd").new()
	var opened: Dictionary = session.open(
		"res://content/chapter_1/chapter.json", "", {"new": true}, _roll
	)
	if not opened["ok"]:
		return opened
	var won: Dictionary = opened["battle"].win_with_assistance()
	if not won["ok"]:
		return won
	var completed: Dictionary = opened["battle"].complete_victory(0)
	if not completed["ok"]:
		return completed
	var next: Dictionary = session.open(
		"res://content/chapter_1/chapter.json", "m1", {"progress": completed["progress"]}, _roll
	)
	if not next["ok"]:
		return next
	var arrived: Dictionary = load("res://tests/test_m4_events.gd").advance(next["battle"])
	if not arrived["ok"]:
		return arrived
	if not (
		next["battle"].event_completed("allied_arrival")
		and next["battle"].unit(0)["visible"]
		and next["battle"].unit(9)["visible"]
	):
		return {"ok": false, "error": "M1_ALLIED_ARRIVAL_REQUIRED"}
	return next


func _manual() -> bool:
	var battle: RefCounted = _scene.battle
	battle.complete_event("level_tutorial")
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["level"] = 10
			actor["experience"] = 37
			actor["proficiency"] = 55
			actor["maxHp"] = 60
			actor["hp"] = 55
			actor["attributes"]["strength"] = 30
			actor["inventory"] = [
				{"id": "promotion:sword", "templateId": 9, "durability": 7},
				{"id": "promotion:crest", "templateId": 76, "durability": 1},
				{"id": "promotion:shield", "templateId": 65, "durability": 2}
			]
			actor["equippedInstanceId"] = "promotion:sword"
	var restored: Dictionary = battle.restore_snapshot(state)
	if not restored["ok"]:
		print("MANUAL_RESTORE_DIAGNOSTIC ", restored)
	if not _expect(restored["ok"], "Manual promotion boundary validates"):
		return false
	_scene.resume_battle(battle)
	_scene.selected_unit = 0
	var before: Dictionary = battle.snapshot()
	_draws = 0
	_scene._unit_intent("inventory", {})
	var items: Control = _scene.item_actions
	var use: Button = items.find_child("Use", true, false)
	if use == null:
		print(
			"PROMOTION_READINESS ",
			{
				"unit": battle.unit(0),
				"phase": battle.phase,
				"outcome": battle.outcome,
				"options": battle.item_options(0),
				"actions": battle.actions_for(0),
				"owner": _scene._active_navigation_target()
			}
		)
		_expect(false, "Prepared m1 actor must have a usable item operation")
		return false
	use.pressed.emit()
	var crest: Button = items.find_child("Item_76", true, false)
	if not _expect(crest != null, "Level10 crest is offered through real item operations"):
		return false
	crest.pressed.emit()
	crest.pressed.emit()
	if not _expect(items.page == "confirm", "Crest uses the existing item confirmation"):
		return false
	await _key(KEY_ESCAPE)
	if not _expect(
		items.page == "items" and battle.snapshot() == before and _draws == 0,
		"Cancel promotion preserves exact unit and held-item state"
	):
		return false
	crest = items.find_child("Item_76", true, false)
	crest.pressed.emit()
	crest.pressed.emit()
	root.size = Vector2i(1280, 720)
	for frame: int in range(8):
		await process_frame
	await _key(KEY_ENTER)
	var after: Dictionary = battle.unit(0)
	if not _expect(
		(
			_scene.busy
			and after["classId"] == 1
			and after["level"] == 10
			and after["experience"] == 37
			and after["proficiency"] == 55
			and after["hp"] == 55
			and after["maxHp"] == 64
			and after["attributes"]["strength"] == 32
			and after["equippedInstanceId"] == "promotion:sword"
			and (
				after["inventory"]
				== [
					{"id": "promotion:sword", "templateId": 9, "durability": 7},
					{"id": "promotion:shield", "templateId": 65, "durability": 2}
				]
			)
			and _draws == 0
		),
		"Manual promotion retains training/current HP and other opaque items without RNG"
	):
		return false
	if not await _finish(battle.snapshot()):
		return false
	_scene._show_information()
	return _expect(
		(
			_profile_class(0) == 1
			and _scene.unit_information.visible
			and _scene.unit_information.get("_identity").text.contains(battle.unit(0)["className"])
		),
		"Map content and unit information bind the promoted class"
	)


func _automatic_and_battle() -> bool:
	var opened: Dictionary = _m1()
	if not _expect(opened["ok"], "Fresh chapter opens for independent automatic boundary"):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	var battle: RefCounted = opened["battle"]
	battle.complete_event("level_tutorial")
	var state: Dictionary = battle.snapshot()
	var caster_cell := Vector2i(battle.unit(9)["x"], battle.unit(9)["y"])
	var adjacent := Vector2i(battle.unit(0)["x"], battle.unit(0)["y"])
	if absi(adjacent.x - caster_cell.x) + absi(adjacent.y - caster_cell.y) != 1:
		adjacent = _free_neighbor(state["units"], caster_cell, 0)
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["level"] = 9
			actor["experience"] = 99
			actor["inventory"] = [
				{"id": "automatic:heal", "templateId": 53, "durability": 20},
				{"id": "automatic:crest", "templateId": 76, "durability": 1},
				{"id": "automatic:new-magic", "templateId": 40, "durability": 10}
			]
			actor["equippedInstanceId"] = ""
		elif actor["id"] == 0:
			actor["x"] = adjacent.x
			actor["y"] = adjacent.y
	if not _expect(battle.restore_snapshot(state)["ok"], "Automatic threshold state validates"):
		return false
	_scene.resume_battle(battle)
	_draws = 0
	var result: Dictionary = battle.heal_unit(9, 0, "automatic:heal")
	if not _expect(
		result["ok"] and battle.unit(9)["classId"] == 5 and _draws == 9,
		"Actual heal crosses threshold with one heal draw and eight growth draws"
	):
		return false
	_scene._present_player_action(result)
	if (
		not await _finish(battle.snapshot())
		or not _expect(_profile_class(9) == 5, "Auto rebinds class5")
	):
		return false
	# Controlled next-action boundary tests the newly legal weapon in a real clip.
	state = battle.snapshot()
	var target_id: int = -1
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 2 and actor["visible"] and actor["id"] < 80:
			target_id = actor["id"]
			break
	if not _expect(target_id >= 0, "Actual m1 has an ordinary enemy for the new weapon"):
		return false
	var combat_cell: Vector2i = _free_neighbor(state["units"], caster_cell, target_id)
	if not _expect(combat_cell != caster_cell, "New-weapon boundary has a free adjacent cell"):
		return false
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["action"] = 0
			actor["attributes"]["magic"] = 30
			actor["attributes"]["skill"] = 30
		elif actor["id"] == target_id:
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["x"] = combat_cell.x
			actor["y"] = combat_cell.y
			actor["hp"] = 1
			actor["attributes"]["magic"] = 0
	if not _expect(battle.restore_snapshot(state)["ok"], "Promoted next-action state validates"):
		return false
	_scene.resume_battle(battle)
	if not _expect(
		battle.equip_unit(9, "automatic:new-magic")["ok"],
		"New stage1 equipment capability is usable"
	):
		return false
	var preview: Dictionary = battle.attack_preview(9, target_id)
	if not _expect(
		preview["ok"] and _scene.battle_clips.preload_pair(preview)["ok"],
		"New actual promoted family preloads its independent magic battle"
	):
		return false
	var attacked: Dictionary = battle.attack_unit(9, target_id)
	if not _expect(attacked["ok"], "New-class ordinary battle resolves"):
		return false
	_scene._present_player_action(attacked)
	return await _finish(battle.snapshot())


func _profile_class(id: int) -> int:
	for actor: Dictionary in _scene.content["units"]:
		if actor["id"] == id:
			return int(actor["classId"])
	return -1


func _free_neighbor(actors: Array, origin: Vector2i, ignored_id: int) -> Vector2i:
	var bounds := Rect2i(0, 0, _scene.content["map"]["width"], _scene.content["map"]["height"])
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		var candidate: Vector2i = origin + offset
		if not bounds.has_point(candidate):
			continue
		var occupied: bool = false
		for actor: Dictionary in actors:
			if actor["id"] != ignored_id and actor["visible"]:
				occupied = occupied or Vector2i(actor["x"], actor["y"]) == candidate
		if not occupied:
			return candidate
	return origin


func _finish(committed: Dictionary) -> bool:
	var saw_summary: bool = false
	var deadline: int = Time.get_ticks_msec() + 12000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		if _scene.action_feedback.current_step.get("kind") == "summary":
			saw_summary = true
			_scene.action_feedback.go_back()
		await process_frame
	return _expect(
		saw_summary and not _scene.busy and _scene.battle.snapshot() == committed,
		"Merged growth/promotion feedback completes once without another business mutation"
	)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(1)
	return value
