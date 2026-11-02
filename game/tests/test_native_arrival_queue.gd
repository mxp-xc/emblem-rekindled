extends SceneTree

const Matrix = preload("res://tests/test_m3_content.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Contract = preload("res://app/chapter_story_contract.gd")
var _scene: Control
var _owned: String = ""
var _draws: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _roll)
	var opened: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m3", {"progress": prepared["progress"]}, _roll
	)
	if not _expect(opened["ok"], "Open real m3 assets for the isolated arrival contract fixture"):
		return
	var content: Dictionary = opened["content"].duplicate(true)
	content["story"]["turnEvents"] = [
		{
			"id": "native_fixture",
			"afterEnemyPhaseOfRound": 1,
			"unitIds": [63, 64, 65, 66],
			"arrivalMode": "nativeQueue",
			"sequence": "native_fixture"
		}
	]
	content["story"]["sequences"]["native_fixture"] = [
		{"kind": "dialogue", "text": {"sourceTextIndex": -1, "speakerId": 3, "text": "原生队列完成"}}
	]
	if not _contract(content):
		return
	_owned = "user://native_arrival_queue_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(_owned) or DirAccess.make_dir_absolute(_owned) != OK:
		fail("Claim a fresh owned arrival fixture directory")
		return
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_scene._set_menu_visible(true)
	_scene.menu_layer.show_page("settings")
	_scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	_scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	_scene._set_menu_visible(false)
	for with_sequence: bool in [true, false]:
		var current: Dictionary = content.duplicate(true)
		if not with_sequence:
			current["story"]["turnEvents"][0]["sequence"] = ""
		var battle := Battle.new(current, _roll, false)
		if not _expect(
			battle.restore_snapshot(_controlled(opened["battle"]))["ok"], "Restore source actors"
		):
			return
		_scene._adopt_content(current, battle)
		_scene.resume_battle(battle)
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(advanced["ok"] and advanced["events"].size() == 1, "One actual phase event"):
			return
		var event: Dictionary = advanced["events"][0]
		var expected: Array = [
			{"unit": 63, "from": Vector2i(6, 6), "to": Vector2i(6, 6), "revealed": true},
			{"unit": 64, "from": Vector2i(7, 6), "to": Vector2i(7, 5), "revealed": true},
			{"unit": 65, "from": Vector2i(10, 10), "to": Vector2i(10, 10), "revealed": false}
		]
		if not _expect(
			(
				event.get("arrivalMode") == "nativeQueue"
				and event.get("arrivalQueue") == expected
				and event["arrivals"].size() == 2
				and battle.unit(65)["hp"] > 0
				and not battle.unit(65)["visible"]
				and not battle.unit(66)["visible"]
			),
			"Full source-order queue retains blocked live65 and skips dead66: " + str(event)
		):
			return
		var committed: Dictionary = battle.snapshot()
		var random_state: int = battle._rng.state
		_draws = 0
		_scene._present_phase_events(advanced["events"])
		var saw_queue: bool = false
		var saw_dialogue: bool = false
		var deadline: int = Time.get_ticks_msec() + 6000
		while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
			saw_queue = saw_queue or _scene.story_player._arrival_queue_updates_remaining > 0
			if _scene.story_player.dialogue.visible:
				saw_dialogue = true
				if not _expect(
					(
						_scene.story_player._arrival_queue_updates_remaining == 0
						and _shown(63)
						and _shown(64)
						and not _shown(65)
					),
					"Follow-up dialogue waits for the entire native queue, including its blocked actor"
				):
					return
				_scene.story_player.advance()
			if not _expect(
				(
					battle.snapshot() == committed
					and battle._rng.state == random_state
					and _draws == 0
				),
				"Arrival presentation is isolated from committed state and RNG"
			):
				return
			await process_frame
		if not _expect(
			(
				not _scene.story_player.visible
				and saw_queue
				and saw_dialogue == with_sequence
				and _shown(63)
				and _shown(64)
				and not _shown(65)
			),
			"Main must play an arrival queue even when its follow-up sequence is empty"
		):
			return
		var restored := Battle.new(current, _roll, false)
		_draws = 0
		if not _expect(
			(
				restored.restore_snapshot(JSON.parse_string(JSON.stringify(committed)))["ok"]
				and _draws == 0
				and Rounds.advance(restored)["events"].is_empty()
			),
			"Completed queued arrival survives JSON and never repeats or retries the blocked unit"
		):
			return
	_scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	_cleanup()
	print(
		"PASS native arrival queue: strict mode, source order, blocked actors, follow-up and JSON once"
	)
	quit(0)


func _contract(content: Dictionary) -> bool:
	var ids: Dictionary = {}
	for actor: Dictionary in content["units"]:
		ids[int(actor["id"])] = actor
	for defect: Variant in [null, "", "instant", 1, ["nativeQueue"]]:
		var story: Dictionary = content["story"].duplicate(true)
		story["turnEvents"][0]["arrivalMode"] = defect
		if not _expect(not _valid(story, content, ids), "Reject unknown/nonstring arrival modes"):
			return false
	for values: Array in [[], [63, 63], [63, 9999], [63, 64.5]]:
		var story: Dictionary = content["story"].duplicate(true)
		story["turnEvents"][0]["unitIds"] = values
		if not _expect(
			not _valid(story, content, ids), "Queued actors require declared unique integers"
		):
			return false
	var json_story: Dictionary = JSON.parse_string(JSON.stringify(content["story"]))
	return _expect(
		_valid(json_story, content, ids), "Actual JSON numeric actors keep their integer meaning"
	)


func _valid(story: Dictionary, content: Dictionary, ids: Dictionary) -> bool:
	return Contract.validate(
		story, content["entry"]["resourceDirectory"], ids, 22, 22, content["_deployments"]
	)


func _controlled(battle: RefCounted) -> Dictionary:
	var state: Dictionary = battle.snapshot()
	state["events"]["opening"] = true
	var points: Dictionary = {
		63: Vector2i(6, 6),
		64: Vector2i(7, 6),
		65: Vector2i(10, 10),
		68: Vector2i(7, 6),
		43: Vector2i(10, 10),
		69: Vector2i(9, 10),
		11: Vector2i(10, 9),
		10: Vector2i(10, 11),
		60: Vector2i(11, 10)
	}
	for actor: Dictionary in state["units"]:
		if actor["faction"] != 0:
			actor["visible"] = points.has(int(actor["id"])) and actor["id"] not in [63, 64, 65]
			actor["hp"] = actor["maxHp"] if points.has(int(actor["id"])) else 0
			actor["flags"] = 0 if actor["visible"] else 1
		if points.has(int(actor["id"])):
			var point: Vector2i = points[int(actor["id"])]
			actor["x"] = point.x
			actor["y"] = point.y
	return state


func _shown(identity: int) -> bool:
	for actor: Dictionary in _scene.map.visible_units():
		if actor["id"] == identity:
			return true
	return false


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _cleanup() -> void:
	if _owned.is_empty():
		return
	for filename: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(filename))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		fail(message)
	return condition


func fail(message: String) -> void:
	push_error(message)
	Engine.time_scale = 1
	_cleanup()
	quit(1)
