extends SceneTree

const Matrix = preload("res://tests/test_m3_content.gd")
const Session = preload("res://app/chapter_session.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
const GROUPS: Array = [[63, 64, 65, 66], [38, 48, 49], [44, 30, 47, 107, 108, 109, 110]]
var _scene: Control
var _owned: String = ""
var _draws: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var started: int = Time.get_ticks_msec()
	root.size = Vector2i(720, 1280)
	_owned = "user://test_m3_flow_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(_owned) or DirAccess.make_dir_absolute(_owned) != OK:
		fail("m3 Main flow needs a newly owned record directory")
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
	# Both step1 choices start from m0's actual representative route2 record.
	# Native route3/step1 is a valid controlled domain context, not an m0 UI choice.
	for sample: Dictionary in [
		{"context": 0, "route": 0}, {"context": 1, "route": 3}, {"context": 1, "route": 2}
	]:
		var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[sample["context"]], _roll)
		if not _expect(prepared["ok"], "Prepare the actual m3 world frontier: " + str(prepared)):
			return
		if not await _enter(prepared["progress"]):
			return
		if sample["context"] == 0 and not await _round_two():
			return
		if not await _death_and_world(sample["route"]):
			return
	_scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	if not _cleanup():
		quit(1)
		return
	print("PASS actual m3 Main: world entry, groups, two-stage death, both branches/fixed route")
	print("PASS m3 Main elapsed_ms=%d at temporary speed32" % (Time.get_ticks_msec() - started))
	quit(0)


func _enter(progress: Dictionary) -> bool:
	var completed: Dictionary = Session.new().completed_content(CHAPTER, progress)
	if not _expect(completed["ok"], "Resolve the preceding completed map before travel"):
		return false
	_scene._adopt_content(completed["content"])
	var saved_frontier: Dictionary = _scene.battle_store.write_progress(progress)
	if not _expect(saved_frontier["ok"], "Save the owned frontier: " + str(saved_frontier)):
		return false
	await _scene._show_completed_progress(progress)
	_scene.story_player.world_node_requested.emit(3)
	var seen: Dictionary = {}
	var saw_commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.current_text_index >= 0:
			seen[story.current_text_index] = true
		if story.commander.visible:
			saw_commander = true
			if not _expect(story.commander.draft["commander"] == 3, "m3 defaults to recruit3"):
				return false
			story.commander.commit()
		elif story.dialogue.visible:
			story.advance()
		elif story.choices.visible:
			story.choices.get_child(0).pressed.emit()
		await process_frame
		if _scene.content["entry"]["battleId"] == "m3" and not _scene.busy:
			break
	if not _expect(
		(
			_scene.content["entry"]["battleId"] == "m3"
			and not _scene.busy
			and saw_commander
			and seen.has(463)
			and seen.has(509)
			and seen.has(510)
			and seen.has(159)
			and _scene.battle.event_completed("opening")
			and _scene.world_progress.is_empty()
		),
		"World travel, original opening/objective and commander precede playable m3: " + str(seen)
	):
		return false
	var saved: Dictionary = _scene.battle_store.read()
	return _expect(
		saved["ok"] and saved["battle"].snapshot() == _scene.battle.snapshot(),
		"World entry saves the complete m3 battle before enabling input"
	)


func _round_two() -> bool:
	var battle: RefCounted = _scene.battle
	var events: Array = []
	# Controlled phase boundary: legal waits skip AI actions, not a natural full-map fight.
	while battle.round_number < 3:
		while battle.automatic_actor() >= 0:
			if not _expect(battle.wait_unit(battle.automatic_actor())["ok"], "Wait a phase actor"):
				return false
		var advanced: Dictionary = battle.end_phase()
		if not _expect(advanced["ok"], "Advance the real m3 phase boundary"):
			return false
		events.append_array(advanced["events"])
	if not _expect(events.size() == 1, "Round2 produces one real reinforcement event"):
		return false
	var committed: Dictionary = battle.snapshot()
	var random_state: int = battle._rng.state
	_draws = 0
	_scene._present_phase_events(events)
	var saw: Dictionary = {}
	var group_counts: Array = []
	var deadline: int = Time.get_ticks_msec() + 8000
	while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
		var visible: Array = []
		for actor: Dictionary in _scene.map.visible_units():
			visible.append(int(actor["id"]))
		var prefix: int = 0
		for group: Array in GROUPS:
			var count: int = 0
			for identity: int in group:
				count += int(identity in visible)
				var actor: Dictionary = battle.unit(identity)
				var displayed: Vector2 = _scene.map.presentation_positions.get(
					identity, Vector2(actor["x"], actor["y"])
				)
				if not _expect(
					displayed == Vector2(actor["x"], actor["y"]),
					"Instant enemy reveals retain their actual deployed cells on every frame"
				):
					return false
			if not _expect(count == 0 or count == group.size(), "Each group appears in one step"):
				return false
			prefix += count
		if not _expect(prefix in [0, 4, 7, 14], "Retain the original group order"):
			return false
		if group_counts.is_empty() or group_counts.back() != prefix:
			group_counts.append(prefix)
		var index: int = _scene.story_player.current_text_index
		if _scene.story_player.dialogue.visible:
			saw[index] = true
			if index == 511:
				if not _expect(prefix == 14, "All three groups appear before 511"):
					return false
				for identity: int in _scene.content["slots"].values():
					if not _expect(
						identity not in visible, "Party stays masked until its entrance"
					):
						return false
			if index in [512, 513]:
				for identity: int in _scene.content["slots"].values():
					var actor: Dictionary = battle.unit(identity)
					if not _expect(
						(
							identity in visible
							and (
								_scene.map.presentation_positions[identity]
								== Vector2(actor["x"], actor["y"])
							)
						),
						"Actual slot occupants land before the party dialogues"
					):
						return false
			_scene.story_player.advance()
		if not _expect(
			battle.snapshot() == committed and battle._rng.state == random_state and _draws == 0,
			"Pure presentation"
		):
			return false
		await process_frame
	if not _expect(
		(
			not _scene.story_player.visible
			and saw.has(511)
			and saw.has(512)
			and saw.has(513)
			and group_counts.has(4)
			and group_counts.has(7)
			and group_counts.has(14)
		),
		"Main reveals three groups then completes north entrance: " + str(group_counts)
	):
		return false
	_scene.resume_battle(battle)
	if not _expect(_scene.battle_store.write(battle)["ok"], "Save the arrival frontier"):
		return false
	var snapshot: Dictionary = battle.snapshot()
	_scene._show_title()
	_scene.load_game()
	await process_frame
	return _expect(
		_scene.battle.snapshot() == snapshot and not _scene.story_player.visible,
		"Restoring completed arrivals cannot replay a reveal or dialogue"
	)


func _death_and_world(selected_route: int) -> bool:
	var battle: RefCounted = _scene.battle
	# HP1 and cleared foes are an explicit controlled boundary, not natural play.
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 2 and actor["id"] != 83:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
		if actor["id"] == 0:
			actor["x"] = 13
			actor["y"] = 12
			actor["visible"] = true
			actor["flags"] &= ~1
		if actor["id"] not in [3, 83]:
			continue
		actor["x"] = 10
		actor["y"] = 10 if actor["id"] == 3 else 11
		actor["maxHp"] = 60
		actor["hp"] = 60 if actor["id"] == 3 else 1
		for key: String in actor["attributes"]:
			actor["attributes"][key] = 30 if actor["id"] == 3 else 0
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore the legal HP1 boss boundary"):
		return false
	_scene.resume_battle(battle)
	var preview: Dictionary = battle.attack_preview(3, 83)
	if not _expect(
		_scene.battle_clips.preload_pair(preview)["ok"], "Real 3/83 pair has real clips"
	):
		return false
	var result: Dictionary = battle.attack_unit(3, 83)
	if not _expect(
		result["ok"] and battle.outcome.get("kind") == "victory",
		"Actual ordinary combat kills the final visible enemy"
	):
		return false
	_scene._present_player_action(result)
	var observed: Array[int] = []
	var saw_retirement: bool = false
	var choice_count: int = 0
	var deadline: int = Time.get_ticks_msec() + 8000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.dialogue.visible:
			var index: int = story.current_text_index
			if index in [514, 515, 516, 517] and index not in observed:
				observed.append(index)
			if index == 515 or index == 516:
				var before: bool = index == 515
				var cell := Vector2(10.5, 11.5) if before else Vector2(13.5, 12.5)
				if not _expect(
					(
						_shown(83) == before
						and saw_retirement != before
						and _scene.map.view.center.is_equal_approx(cell)
					),
					"515 focuses the visible HP0 boss; 516 follows retirement and focuses Alm"
				):
					return false
			story.advance()
		if _scene.retirement_player.playing:
			saw_retirement = true
		if _scene.action_feedback.current_step.get("kind") == "tutorial":
			_scene.action_feedback.go_back()
		if story.choices.visible and not story.world_active:
			choice_count += 1
			var routes: Array = _scene.content["story"]["routeChoices"]
			for index: int in range(routes.size()):
				if int(routes[index]["routeIndex"]) == selected_route:
					story.choices.get_child(index).pressed.emit()
					break
		await process_frame
	var branching: bool = int(state["campaign"]["worldStep"]) == 1
	if not _expect(
		(
			_scene.story_player.world_ready
			and observed.slice(0, 3) == [514, 515, 516]
			and observed.has(517) == branching
			and choice_count == int(branching)
		),
		"Boss/death presentation precedes branch-only 517 or the fixed route: " + str(observed)
	):
		return false
	var progress: Dictionary = _scene.world_progress.duplicate(true)
	var saved: Dictionary = _scene.battle_store.read()
	if not _expect(
		(
			progress["completedBattle"] == "m3"
			and progress["route"] == selected_route
			and saved["ok"]
			and saved["progress"] == progress
		),
		"m3 world keeps the actual selected/fixed route and matching continue record"
	):
		return false
	_scene._show_title()
	_scene.load_game()
	await process_frame
	return _expect(
		_scene.world_progress == progress and _scene.story_player.world_ready,
		"Loading completed m3 keeps its world frontier without replaying choices/rewards"
	)


func _shown(identity: int) -> bool:
	for actor: Dictionary in _scene.map.visible_units():
		if actor["id"] == identity:
			return true
	return false


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		fail(message)
	return condition


func _cleanup() -> bool:
	if _owned.is_empty():
		return true
	for filename: String in DirAccess.get_files_at(_owned):
		if DirAccess.remove_absolute(_owned.path_join(filename)) != OK:
			return false
	if DirAccess.remove_absolute(_owned) != OK:
		return false
	_owned = ""
	return true


func fail(message: String) -> void:
	push_error(message)
	Engine.time_scale = 1
	_cleanup()
	quit(1)
