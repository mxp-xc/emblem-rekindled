extends SceneTree

const Matrix = preload("res://tests/test_m6_content.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
const Session = preload("res://app/chapter_session.gd")
var _scene: Control
var _owned: String = ""


func _initialize() -> void:
	call_deferred("run")


# Controlled Main integration: real domain commands and presentation, not platform input acceptance.
func run() -> void:
	var started: int = Time.get_ticks_msec()
	_owned = "user://test_m6_flow_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(_owned) or DirAccess.make_dir_absolute(_owned) != OK:
		fail("m6 Main requires a newly owned record directory")
		return
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_set_speed(32)
	if not await _enter() or not await _focus_timing() or not await _arrivals():
		return
	if not _boss_information() or not await _duel() or not await _save_restore():
		return
	if not await _recovery() or not await _retire_boss() or not await _last_enemy():
		return
	if not await _early_fixture():
		return
	_scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	_cleanup()
	print("PASS controlled m6 Main: real world cancel/entry, focus timing, south arrivals and boss")
	print(
		"PASS controlled m6 Main: combat, cold restore, ring81, all-enemy victory and both endings"
	)
	print(
		(
			"PASS m6 Main elapsed_ms=%d; focus/arrivals at1x, other presentation at32x"
			% (Time.get_ticks_msec() - started)
		)
	)
	quit(0)


# QA shares a phase0 boundary built with Matrix sources and actual wait/end-phase commands.
# HP0/quiet enemies are explicit controlled fixtures; hidden party slots retain their phase state.
static func prepare_boundary(context: Dictionary, round_number: int) -> Dictionary:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m6", prepared["source"], _zero)
	if not opened["ok"]:
		return opened
	while opened["battle"].round_number < round_number:
		var advanced: Dictionary = Rounds.advance(opened["battle"])
		if not advanced["ok"]:
			return advanced
	var state: Dictionary = opened["battle"].snapshot()
	state["events"]["opening"] = true
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 0:
			continue
		if actor["id"] in [33, 85]:
			actor["move"] = 0
		else:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
	return Session.new().open(Matrix.CHAPTER, "m6", {"snapshot": state}, _zero)


func _enter() -> bool:
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[2], _zero)
	if not _expect(
		prepared["ok"] and prepared.get("kind") == "reachable_world",
		"Prepare the actual m5 settlement on route2 before m6 step4"
	):
		return false
	var progress: Dictionary = prepared["progress"]
	var previous: Dictionary = Session.new().completed_content(Matrix.CHAPTER, progress)
	if not _expect(previous["ok"], "Resolve the real completed m5 content"):
		return false
	_scene._adopt_content(previous["content"])
	if not _expect(_scene.battle_store.write_progress(progress)["ok"], "Owned m5 world record"):
		return false
	await _scene._show_completed_progress(progress)
	var record: String = FileAccess.get_file_as_string(_scene.battle_store.path)
	_scene.story_player.world_node_requested.emit(6)
	if not _expect(_scene.story_player._travel_confirmation, "Main opens m6 travel confirmation"):
		return false
	_scene.story_player.go_back()
	await process_frame
	if not _expect(
		(
			not _scene._world_transitioning
			and _scene.story_player.world_ready
			and _scene.content["entry"]["battleId"] == "m5"
			and _scene.world_progress == progress
			and FileAccess.get_file_as_string(_scene.battle_store.path) == record
		),
		"Cancel returns to the same m5 world without changing its record"
	):
		return false
	_scene.story_player.world_node_requested.emit(6)
	var seen: Dictionary = {}
	var commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.current_text_index >= 0:
			seen[story.current_text_index] = true
		if story.commander.visible:
			commander = true
			if not _expect(story.commander.draft["commander"] == 4, "m6 offers commander4"):
				return false
			story.commander.commit()
		elif story._travel_confirmation:
			story.choices.get_child(0).pressed.emit()
		else:
			_drive()
		await process_frame
		if _scene.content["entry"]["battleId"] == "m6" and not _scene.busy:
			break
	return _expect(
		(
			_scene.content["entry"]["battleId"] == "m6"
			and not _scene.busy
			and commander
			and seen.has(542)
			and seen.has(543)
			and seen.has(162)
			and _scene.battle.commander_id == 4
			and _scene.battle.event_completed("opening")
		),
		"Actual m5 world travel plays542/543, objective162 and commander4 before playable m6"
	)


func _focus_timing() -> bool:
	# Replay only the two real source focus steps at1x, making both holds measurable.
	# The full opening above still passes through Main's normal travel/commander path.
	_set_speed(1)
	# Start timers on a new1x frame after the settings/menu layout has completed.
	await process_frame
	var state: Dictionary = _scene.battle.snapshot()
	var original: Vector2 = _scene.map.view.center
	_scene.map.view.focus_cell(Vector2i(5, 9))
	var first: Vector2 = _scene.map.view.center
	_scene.map.view.focus_cell(Vector2i(19, 17))
	var second: Vector2 = _scene.map.view.center
	_scene.map.view.center = original
	var steps: Array = _scene.content["story"]["sequences"]["opening"].slice(1, 3)
	var started: int = Time.get_ticks_msec()
	_scene.story_player.play(steps)
	if not _expect(
		_scene.map.view.center.is_equal_approx(first), "First focus5,9 is instantaneous"
	):
		return false
	var moved_at: int = -1
	var arrived_at: int = -1
	var first_changed: Vector2 = first
	var intermediate: Array[Vector2] = []
	var deadline: int = started + 12000
	while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
		var center: Vector2 = _scene.map.view.center
		if not center.is_equal_approx(first) and moved_at < 0:
			moved_at = Time.get_ticks_msec()
			first_changed = center
		if center.is_equal_approx(second) and arrived_at < 0:
			arrived_at = Time.get_ticks_msec()
		if not center.is_equal_approx(first) and not center.is_equal_approx(second):
			if center not in intermediate:
				intermediate.append(center)
		if not _expect(_scene.battle.snapshot() == state, "Focus playback leaves domain unchanged"):
			return false
		await process_frame
	var ended: int = Time.get_ticks_msec()
	var tick_ms: float = _scene.story_player._tick_seconds * 1000.0
	var passed: bool = _expect(
		(
			not _scene.story_player.visible
			and moved_at >= 0
			and arrived_at > moved_at
			and moved_at - started >= 22 * tick_ms - 100
			and intermediate.size() >= 2
			and ended - arrived_at >= 10 * tick_ms - 100
			and _scene.map.view.center.is_equal_approx(second)
		),
		(
			"Real focus holds5,9 for22 ticks, traverses multiple frames to19,17, then holds10 ticks; "
			+ (
				(
					"moved_ms=%d arrived_ms=%d ended_ms=%d tick_ms=%.2f intermediate=%d "
					+ "visible=%s first=%s second=%s actual=%s first_changed=%s"
				)
				% [
					moved_at - started,
					arrived_at - started,
					ended - started,
					tick_ms,
					intermediate.size(),
					_scene.story_player.visible,
					first,
					second,
					_scene.map.view.center,
					first_changed
				]
			)
		)
	)
	_set_speed(32)
	_scene.resume_battle(_scene.battle)
	return passed


func _arrivals() -> bool:
	# Six source ticks can finish within one32x process frame; sample the actual tween at1x.
	_set_speed(1)
	await process_frame
	var seen: Dictionary = {}
	var origins: Dictionary = {}
	var first_positions: Dictionary = {}
	var previous_positions: Dictionary = {}
	var moved: Dictionary = {}
	var declared: Dictionary = {}
	var focused: bool = false
	var original: Vector2 = _scene.map.view.center
	_scene.map.view.focus_cell(Vector2i(6, 18))
	var focus: Vector2 = _scene.map.view.center
	_scene.map.view.center = original
	for entrance: Dictionary in _scene.content["story"]["sequences"]["party_arrival"][0]["units"]:
		var from := Vector2(entrance["from"][0], entrance["from"][1])
		var to := Vector2(entrance["to"][0], entrance["to"][1])
		if not _expect(from - to == Vector2(0, 3), "Source entrance retains exact south offset0,3"):
			return false
		declared[int(entrance["unitId"])] = true
	while _scene.battle.round_number < 3:
		var advanced: Dictionary = Rounds.advance(_scene.battle)
		if not _expect(advanced["ok"], "Advance actual m6 using controlled wait commands"):
			return false
		var committed: Dictionary = _scene.battle.snapshot()
		_scene._present_phase_events(advanced["events"])
		var deadline: int = Time.get_ticks_msec() + 10000
		while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
			focused = focused or _scene.map.view.center.is_equal_approx(focus)
			for identity: int in _scene.content["slots"].values():
				if not _scene.map.presentation_positions.has(identity):
					continue
				var actor: Dictionary = _scene.battle.unit(identity)
				var position: Vector2 = _scene.map.presentation_positions[identity]
				var to := Vector2(actor["x"], actor["y"])
				if not first_positions.has(identity):
					first_positions[identity] = {"position": position, "to": to}
					# The first process-frame sample follows the tween's first update.
					if position.x == to.x and position.y > to.y and position.y <= to.y + 3:
						origins[identity] = true
				var previous: Vector2 = previous_positions.get(identity, position)
				if not _expect(
					position.x == to.x and position.y >= to.y and position.y <= previous.y,
					"Each actual south entrance moves north toward its own destination"
				):
					return false
				if position.y < previous.y:
					moved[identity] = true
				previous_positions[identity] = position
			var story: Control = _scene.story_player
			if story.dialogue.visible:
				seen[story.current_text_index] = true
				if story.current_text_index == 544:
					for identity: int in _scene.content["slots"].values():
						var actor: Dictionary = _scene.battle.unit(identity)
						var to := Vector2(actor["x"], actor["y"])
						if not _expect(
							(
								_shown(identity)
								and _scene.map.presentation_positions[identity].is_equal_approx(to)
							),
							"All seven slots reach their exact destinations before544"
						):
							return false
			_drive()
			if not _expect(
				_scene.battle.snapshot() == committed, "Arrival presentation never mutates domain"
			):
				return false
			await process_frame
		if not _expect(not _scene.story_player.visible, "South arrival presentation finishes"):
			return false
	var passed: bool = _expect(
		(
			declared.size() == 7
			and origins.size() == 7
			and moved.size() == 7
			and focused
			and seen.has(544)
			and seen.has(545)
			and _scene.battle.event_completed("party_arrival")
		),
		(
			"Round2 presents seven slots from south offset0,3 at focus6,18, then544/545; "
			+ (
				"origins=%s moved=%s focused=%s seen=%s first_positions=%s"
				% [origins.keys(), moved, focused, seen.keys(), first_positions]
			)
		)
	)
	_set_speed(32)
	_scene.resume_battle(_scene.battle)
	return passed


func _boss_information() -> bool:
	_scene.selected_unit = 85
	_scene._show_information()
	var actor: Dictionary = _scene.battle.unit(85)
	var items: Array[int] = []
	var ring: Dictionary = {}
	for held: Dictionary in actor["inventory"]:
		items.append(int(held["templateId"]))
		if held["templateId"] == 81:
			ring = held
	var portrait: Dictionary = _scene.content["interface"]["portraitByUnitId"]["85"]
	var image: Texture2D = load(
		_scene.content["entry"]["resourceDirectory"].path_join(
			_scene.content["story"]["images"]["portraits_16"]["texture"]
		)
	)
	var shown: Image = _scene.unit_information._portrait.texture.get_image()
	_scene.unit_information.show_page(2)
	var passed: bool = _expect(
		(
			actor["classId"] == 17
			and items == [19, 65, 81, 76]
			and ring.get("durability", -1) == 0
			and portrait["portraitId"] == 16
			and shown.get_data() == image.get_image().get_data()
			and _scene.unit_information._identity.text == actor["name"] + " " + actor["className"]
			and _scene.unit_information.body.get_node_or_null("Item_81") != null
		),
		"Main boss85 information shows portrait16, class17, items19/65/81 and drop76"
	)
	_scene.unit_information.hide()
	return passed


func _duel() -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [4, 85]:
			continue
		actor["x"] = 10
		actor["y"] = 10 if actor["id"] == 4 else 11
		actor["maxHp"] = 60
		actor["hp"] = 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = 30 if key == "defense" else 0
	if not _expect(_scene.battle.restore_snapshot(state)["ok"], "Controlled nonlethal boss duel"):
		return false
	_scene.resume_battle(_scene.battle)
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(4, 85))["ok"], "Boss clips"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(4, 85)
	if not _expect(result["ok"], "Real ordinary attack against boss85"):
		return false
	_scene._present_player_action(result)
	var seen: Dictionary = {}
	var saw_battle: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		if _scene.story_player.dialogue.visible:
			seen[_scene.story_player.current_text_index] = true
		saw_battle = saw_battle or _scene.battle_view.playing
		_drive()
		await process_frame
	return _expect(
		(
			saw_battle
			and seen.has(546)
			and not _scene.busy
			and _scene.battle.unit(85)["hp"] > 0
			and _scene.battle.outcome.is_empty()
			and _scene.battle.event_completed("boss_first_combat")
		),
		"Main presents546 and actual independent nonlethal combat once"
	)


func _save_restore() -> bool:
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Save the owned boss battle"):
		return false
	var state: Dictionary = _scene.battle.snapshot()
	_scene._show_title()
	_scene.load_game()
	await process_frame
	return _expect(
		(
			_scene.battle.snapshot() == state
			and not _scene.story_player.visible
			and _scene.battle.event_completed("boss_first_combat")
		),
		"Main cold read preserves boss inventory and first-combat event without replay"
	)


func _recovery() -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 85:
			actor["hp"] = 10
	if not _expect(_scene.battle.restore_snapshot(state)["ok"], "Controlled wounded boss"):
		return false
	_scene.resume_battle(_scene.battle)
	var inventory: Array = _scene.battle.unit(85)["inventory"].duplicate(true)
	var previous_round: int = _scene.battle.round_number
	var advanced: Dictionary = Rounds.advance(_scene.battle)
	if not _expect(advanced["ok"], "Actual new-round command applies boss ring81"):
		return false
	var committed: Dictionary = _scene.battle.snapshot()
	await _scene._present_phase_events(advanced["events"])
	await process_frame
	var boss: Dictionary = _scene.battle.unit(85)
	var minimum_hp: int = 10 + floori(float(boss["maxHp"]) * 10 / 100)
	var maximum_hp: int = 10 + floori(float(boss["maxHp"]) * 20 / 100)
	var passed: bool = _expect(
		(
			_scene.battle.round_number == previous_round + 1
			and boss["hp"] >= minimum_hp
			and boss["hp"] <= maximum_hp
			and boss["inventory"] == inventory
			and advanced["events"].is_empty()
			and _scene.battle.snapshot() == committed
			and not _scene.story_player.visible
			and not _scene.battle_view.playing
		),
		"Zero-durability81 restores actual boss HP on a new round without a separate presentation"
	)
	_scene.resume_battle(_scene.battle)
	return passed


func _retire_boss() -> bool:
	if not _prepare_kill(85, false):
		return false
	var result: Dictionary = _scene.battle.attack_unit(4, 85)
	if not _expect(
		result["ok"] and _scene.battle.outcome.is_empty(), "Boss death leaves other enemies alive"
	):
		return false
	_scene._present_player_action(result)
	var saw_before: bool = false
	var replayed_first: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.dialogue.visible:
			replayed_first = replayed_first or story.current_text_index == 546
			if story.current_text_index == 547:
				saw_before = true
				if not _expect(
					_shown(85) and not _scene.retirement_player.playing,
					"547 is visible before boss retirement/hide"
				):
					return false
		_drive()
		await process_frame
	return _expect(
		(
			saw_before
			and not replayed_first
			and not _scene.busy
			and not _shown(85)
			and _scene.battle.unit(33)["hp"] > 0
			and _scene.battle.outcome.is_empty()
		),
		"Boss547 and retirement finish while other enemies keep m6 in progress"
	)


func _last_enemy() -> bool:
	# Controlled remaining-enemy fixture; the final ordinary attack performs the real outcome check.
	if not _prepare_kill(33, true):
		return false
	var initial_gold: int = _scene.battle.gold
	var result: Dictionary = _scene.battle.attack_unit(4, 33)
	if not _expect(
		result["ok"] and _scene.battle.outcome.get("kind") == "victory",
		"The final visible enemy's real retirement triggers m6 victory"
	):
		return false
	var previous_record: String = FileAccess.get_file_as_string(_scene.battle_store.path)
	_scene._present_player_action(result)
	return await _settled_world(Matrix.CONTEXTS[2], initial_gold, previous_record)


func _prepare_kill(target: int, last: bool) -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if last and actor["faction"] == 2 and actor["id"] != target:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
		if actor["id"] == 4:
			actor["x"] = 10
			actor["y"] = 10
			actor["hp"] = actor["maxHp"]
			actor["action"] = 0
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 30
		if actor["id"] == target:
			actor["x"] = 10
			actor["y"] = 11
			actor["hp"] = 1
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 0
	if not _expect(_scene.battle.restore_snapshot(state)["ok"], "Controlled HP1 enemy boundary"):
		return false
	_scene.resume_battle(_scene.battle)
	return _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(4, target))["ok"],
		"Actual final enemy combat pair preloads"
	)


func _early_fixture() -> bool:
	# dr4 step2 cannot use a fabricated completed m7 record; enter the explicit domain snapshot.
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[4], _zero)
	if not _expect(
		(
			prepared["ok"]
			and prepared.get("kind") == "domain_fixture"
			and prepared["source"].has("snapshot")
		),
		"Step2 ending uses an explicitly labelled domain snapshot fixture"
	):
		return false
	var opened: Dictionary = prepare_boundary(Matrix.CONTEXTS[4], 3)
	if not _expect(opened["ok"], "Open the step2 controlled phase0 boundary"):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	var initial_gold: int = _scene.battle.gold
	var result: Dictionary = _scene.battle.win_with_assistance()
	if not _expect(result["ok"], "Controlled step2 assistance reaches real Main settlement"):
		return false
	var previous_record: String = FileAccess.get_file_as_string(_scene.battle_store.path)
	_scene._present_player_action(result)
	return await _settled_world(Matrix.CONTEXTS[4], initial_gold, previous_record)


func _settled_world(context: Dictionary, initial_gold: int, previous_record: String) -> bool:
	var seen: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 10000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		if _scene.story_player.dialogue.visible:
			seen[_scene.story_player.current_text_index] = true
		_drive()
		await process_frame
	var early: bool = context["step"] == 2
	if not _expect(
		(
			_scene.story_player.world_ready
			and seen.has(548)
			and seen.has(488) == early
			and seen.has(549) == (not early)
			and _scene.world_progress["route"] == context["route"]
			and _scene.world_progress["completedBattle"] == "m6"
			and _scene.world_progress["worldStep"] == context["step"] + 1
			and _scene.world_progress["gold"] == initial_gold + 1000
			and FileAccess.get_file_as_string(_scene.battle_store.path) == previous_record
		),
		"Main settles the fixed route and preserves the previous continue record"
	):
		return false
	var progress: Dictionary = _scene.world_progress.duplicate(true)
	if not _expect(_scene.battle_store.write_progress(progress)["ok"], "Explicitly save the world"):
		return false
	_scene._show_title()
	_scene.load_game()
	deadline = Time.get_ticks_msec() + 5000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	var again: Dictionary = _scene.battle_store.read()
	return _expect(
		(
			_scene.story_player.world_ready
			and _scene.world_progress == progress
			and not _scene.story_player.dialogue.visible
			and again["ok"]
			and again["progress"] == progress
		),
		"World cold read keeps the same reward/route without replaying settlement"
	)


func _set_speed(rate: int) -> void:
	_scene._set_menu_visible(true)
	_scene.menu_layer.show_page("settings")
	_scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	_scene.menu_layer.find_child("Speed_%d" % rate, true, false).pressed.emit()
	_scene._set_menu_visible(false)


func _drive() -> void:
	if _scene.story_player.dialogue.visible:
		_scene.story_player.advance()
	if _scene.action_feedback.current_step.get("kind") in ["tutorial", "summary"]:
		_scene.action_feedback.go_back()


func _shown(identity: int) -> bool:
	for actor: Dictionary in _scene.map.visible_units():
		if actor["id"] == identity:
			return true
	return false


static func _zero(_limit: int) -> int:
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		fail(message)
	return condition


func _cleanup() -> void:
	if _owned.is_empty():
		return
	for filename: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(filename))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func fail(message: String) -> void:
	push_error(message)
	Engine.time_scale = 1
	_cleanup()
	quit(1)
