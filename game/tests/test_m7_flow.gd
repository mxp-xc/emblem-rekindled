extends SceneTree

const Matrix = preload("res://tests/test_m7_content.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const Session = preload("res://app/chapter_session.gd")
var _scene: Control
var _owned: String = ""


func _initialize() -> void:
	call_deferred("run")


# Controlled Main integration; platform input and natural full-battle acceptance are separate.
func run() -> void:
	var started: int = Time.get_ticks_msec()
	_owned = "user://test_m7_flow_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(_owned) or DirAccess.make_dir_absolute(_owned) != OK:
		fail("m7 Main requires a newly owned record directory")
		return
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_set_speed(32)
	if not await _enter(Matrix.CONTEXTS[4]) or not await _arrivals():
		return
	if not _information() or not await _duel(false) or not await _save_restore():
		return
	if not await _staff() or not await _duel(true) or not await _last_enemy():
		return
	# Repeat only the ending boundary for the other early branch and fixed route.
	for ending: Dictionary in [
		{"context": Matrix.CONTEXTS[4], "choice": 6, "route": 7},
		{"context": Matrix.CONTEXTS[3], "choice": 4, "route": 4}
	]:
		var opened: Dictionary = prepare_boundary(ending["context"], 3)
		if not _expect(opened["ok"], "Prepare a declared m7 ending boundary"):
			return
		_scene._adopt_content(opened["content"], opened["battle"])
		_scene.resume_battle(opened["battle"])
		var initial_gold: int = _scene.battle.gold
		var result: Dictionary = _scene.battle.win_with_assistance()
		if not _expect(result["ok"], "Assistance enters the existing m7 victory sequence"):
			return
		_scene._present_player_action(result)
		if not await _settled_world(
			ending["context"], initial_gold, ending["choice"], ending["route"]
		):
			return
	_scene.queue_free()
	await process_frame
	_cleanup()
	print("PASS controlled m7 Main: world cancel/entry, commander5, south and nativeQueue arrivals")
	print("PASS controlled m7 Main: boss/info/combat/retirement, staff55, cold and three endings")
	print(
		(
			"PASS m7 Main elapsed_ms=%d; arrivals at1x, other presentation32x"
			% (Time.get_ticks_msec() - started)
		)
	)
	quit(0)


# QA shares real Session sources and wait/end-phase commands. Quiet/HP0 units are controlled.
static func prepare_boundary(context: Dictionary, round_number: int) -> Dictionary:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m7", prepared["source"], _zero)
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
		if actor["id"] in [44, 86, 107, 108, 109, 110]:
			actor["move"] = 0
		else:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
	return Session.new().open(Matrix.CHAPTER, "m7", {"snapshot": state}, _zero)


func _enter(context: Dictionary) -> bool:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not _expect(
		prepared["ok"] and prepared["kind"] == "reachable_world", "Use legal m0 route6 world"
	):
		return false
	var progress: Dictionary = prepared["progress"]
	var previous: Dictionary = Session.new().completed_content(Matrix.CHAPTER, progress)
	if not _expect(previous["ok"], "Resolve the real completed frontier"):
		return false
	_scene._adopt_content(previous["content"])
	if not _expect(
		_scene.battle_store.write_progress(progress)["ok"], "Write the owned world record"
	):
		return false
	await _scene._show_completed_progress(progress)
	var record: String = FileAccess.get_file_as_string(_scene.battle_store.path)
	_scene.story_player.world_node_requested.emit(7)
	if not _expect(_scene.story_player._travel_confirmation, "m7 opens travel confirmation"):
		return false
	_scene.story_player.go_back()
	await process_frame
	if not _expect(
		(
			_scene.world_progress == progress
			and _scene.story_player.world_ready
			and FileAccess.get_file_as_string(_scene.battle_store.path) == record
		),
		"Cancel m7 travel preserves the frontier and record"
	):
		return false
	_scene.story_player.world_node_requested.emit(7)
	var seen: Dictionary = {}
	var commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.current_text_index >= 0:
			seen[story.current_text_index] = true
		if story.commander.visible:
			commander = true
			if not _expect(story.commander.draft["commander"] == 5, "m7 offers commander5"):
				return false
			story.commander.commit()
		elif story._travel_confirmation:
			story.choices.get_child(0).pressed.emit()
		else:
			_drive()
		await process_frame
		if _scene.content["entry"]["battleId"] == "m7" and not _scene.busy:
			break
	return _expect(
		(
			_scene.content["entry"]["battleId"] == "m7"
			and not _scene.busy
			and commander
			and seen.has(550)
			and seen.has(551)
			and seen.has(163)
			and _scene.battle.event_completed("opening")
			and _scene.battle.commander_id == 5
		),
		"Legal world entry presents550/551/objective163 and commander5 before m7 input"
	)


func _arrivals() -> bool:
	_set_speed(1)
	await process_frame
	var seen: Dictionary = {}
	var south: Dictionary = {}
	var queue_seen: bool = false
	var declared: Array = _scene.content["story"]["sequences"]["party_arrival"][0]["units"]
	if not _expect(declared.size() == 6, "m7 has six existing deployment-slot entrances"):
		return false
	for entrance: Dictionary in declared:
		if not _expect(
			(
				(
					(
						Vector2i(entrance["from"][0], entrance["from"][1])
						- Vector2i(entrance["to"][0], entrance["to"][1])
					)
					== Vector2i(0, 3)
				)
				and entrance["unitId"] != 5
			),
			"Six old slots retain south offset0,+3 and exclude new recruit5"
		):
			return false
	while _scene.battle.round_number < 5:
		var advanced: Dictionary = Rounds.advance(_scene.battle)
		if not _expect(advanced["ok"], "Advance m7 through real controlled waits"):
			return false
		var committed: Dictionary = _scene.battle.snapshot()
		_scene._present_phase_events(advanced["events"])
		var deadline: int = Time.get_ticks_msec() + 10000
		while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
			var story: Control = _scene.story_player
			queue_seen = queue_seen or story._arrival_queue_updates_remaining > 0
			for entrance: Dictionary in declared:
				var identity: int = int(entrance["unitId"])
				if _scene.map.presentation_positions.has(identity):
					var position: Vector2 = _scene.map.presentation_positions[identity]
					var actor: Dictionary = _scene.battle.unit(identity)
					if (
						position.x == actor["x"]
						and position.y > actor["y"]
						and position.y <= actor["y"] + 3
					):
						south[identity] = true
			if story.dialogue.visible:
				seen[story.current_text_index] = true
				if story.current_text_index == 552:
					for entrance: Dictionary in declared:
						if not _expect(_shown(int(entrance["unitId"])), "All old slots precede552"):
							return false
				if story.current_text_index == 556:
					if not _expect(
						story._arrival_queue_updates_remaining == 0,
						"556 follows the complete native queue"
					):
						return false
				_drive()
			if not _expect(
				_scene.battle.snapshot() == committed, "Arrival playback does not change domain"
			):
				return false
			await process_frame
		if not _expect(not _scene.story_player.visible, "m7 arrival presentation finishes"):
			return false
	_set_speed(32)
	_scene.resume_battle(_scene.battle)
	return _expect(
		(
			south.size() == 6
			and queue_seen
			and seen.has(552)
			and seen.has(553)
			and seen.has(554)
			and seen.has(555)
			and seen.has(556)
			and _scene.battle.event_completed("party_arrival")
			and _scene.battle.event_completed("monster_arrival")
		),
		"Main presents six south arrivals and native107..110 before552..556 exactly once"
	)


func _information() -> bool:
	_scene.selected_unit = 86
	_scene._show_information()
	_scene.unit_information.show_page(2)
	var actor: Dictionary = _scene.battle.unit(86)
	var portrait: Dictionary = _scene.content["interface"]["portraitByUnitId"]["86"]
	var image: Texture2D = load(
		_scene.content["entry"]["resourceDirectory"].path_join(
			_scene.content["story"]["images"]["portraits_17"]["texture"]
		)
	)
	var actual: Image = _scene.unit_information._portrait.texture.get_image()
	var correct: bool = (
		actor["name"] == "希撒斯"
		and actor["classId"] == 17
		and portrait["portraitId"] == 17
		and actual.get_data() == image.get_image().get_data()
		and _scene.unit_information.body.get_node_or_null("Item_76") != null
	)
	_scene.unit_information.hide()
	return _expect(correct, "Boss86 information shows native name/portrait17/class17 and drop76")


func _duel(lethal: bool) -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [5, 86]:
			continue
		actor["x"] = 10
		actor["y"] = 10 if actor["id"] == 5 else 11
		actor["maxHp"] = 60
		actor["hp"] = 1 if lethal and actor["id"] == 86 else 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = (
				(30 if actor["id"] == 5 else 0) if lethal else (30 if key == "defense" else 0)
			)
	if not _expect(_scene.battle.restore_snapshot(state)["ok"], "Restore controlled m7 boss duel"):
		return false
	_scene.resume_battle(_scene.battle)
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(5, 86))["ok"],
		"Actual m7 boss clips preload"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(5, 86)
	if not _expect(
		result["ok"] and _scene.battle.outcome.is_empty(), "Boss duel alone cannot win all-enemy m7"
	):
		return false
	_scene._present_player_action(result)
	var seen: Dictionary = {}
	var saw_battle: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		saw_battle = saw_battle or _scene.battle_view.playing
		if story.dialogue.visible:
			seen[story.current_text_index] = true
			if (
				story.current_text_index == 558
				and not _expect(
					_shown(86) and not _scene.retirement_player.playing,
					"558 precedes boss retirement"
				)
			):
				return false
		_drive()
		await process_frame
	return _expect(
		(
			saw_battle
			and not _scene.busy
			and seen.has(557) == (not lethal)
			and seen.has(558) == lethal
			and _shown(86) == (not lethal)
			and _scene.battle.outcome.is_empty()
		),
		"Main plays557 once and558 before lethal retirement while other enemies remain"
	)


func _staff() -> bool:
	# Controlled transfer of the actual held55 from source44; no fresh item template is invented.
	var state: Dictionary = _scene.battle.snapshot()
	var staff: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] == 44:
			for held: Dictionary in actor["inventory"]:
				if held["templateId"] == 55:
					staff = held
					actor["inventory"].erase(held)
					break
	for actor: Dictionary in state["units"]:
		if actor["id"] in [0, 9]:
			actor["x"] = 8 if actor["id"] == 0 else 9
			actor["y"] = 11
			actor["action"] = 0
		if actor["id"] == 9:
			actor["inventory"].append(staff)
	if not _expect(
		not staff.is_empty() and _scene.battle.restore_snapshot(state)["ok"],
		"Actual source44 staff55 controlled transfer"
	):
		return false
	_scene.resume_battle(_scene.battle)
	_scene._show_unit_menu(Vector2i(9, 11))
	_scene.get_node("UnitStatus/Status/Actions/Heal").pressed.emit()
	var view: Control = _scene.target_selection
	for index: int in range(view._items.size()):
		if view._items[index]["item"]["id"] == staff["id"]:
			view.find_child("Staff_%d" % index, true, false).pressed.emit()
	_scene._show_cell(Vector2i(8, 11))
	var saw_ability: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		var step: Dictionary = _scene.action_feedback.current_step
		if not _expect(step.get("kind") != "healing", "m7 force staff uses no healing circle"):
			return false
		saw_ability = saw_ability or step.get("secondLine") == "能力提升"
		_drive()
		await process_frame
	return _expect(
		saw_ability and not _scene.busy and (_scene.battle.unit(0)["flags"] & 40) == 8,
		"Main staff55 casts its actual m7 held instance and shows ability feedback"
	)


func _save_restore() -> bool:
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Save only the owned m7 record"):
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
		"Main cold restore retains m7 events and inventory without opening/first-combat replay"
	)


func _last_enemy() -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 2 and actor["id"] != 44:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
		if actor["id"] in [5, 44]:
			actor["x"] = 10
			actor["y"] = 10 if actor["id"] == 5 else 11
			actor["hp"] = actor["maxHp"] if actor["id"] == 5 else 1
			actor["action"] = 0
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 30 if actor["id"] == 5 else 0
	if not _expect(_scene.battle.restore_snapshot(state)["ok"], "Controlled final visible enemy"):
		return false
	_scene.resume_battle(_scene.battle)
	var initial_gold: int = _scene.battle.gold
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(5, 44))["ok"],
		"Actual last-enemy combat clips preload"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(5, 44)
	if not _expect(
		result["ok"] and _scene.battle.outcome.get("kind") == "victory",
		"Last visible enemy's real attack triggers m7 victory"
	):
		return false
	_scene._present_player_action(result)
	return await _settled_world(Matrix.CONTEXTS[4], initial_gold, 8, 6)


func _settled_world(context: Dictionary, initial_gold: int, choice: int, route: int) -> bool:
	var seen: Dictionary = {}
	var choice_seen: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.dialogue.visible:
			seen[story.current_text_index] = true
		if story.choices.visible and not story.world_active:
			choice_seen = true
			var options: Array = _scene.content["story"]["routeChoices"]
			for index: int in range(options.size()):
				if int(options[index]["nodeId"]) == choice:
					story.choices.get_child(index).pressed.emit()
					break
		else:
			_drive()
		await process_frame
	var saved: Dictionary = _scene.battle_store.read()
	if not _expect(
		(
			_scene.story_player.world_ready
			and seen.has(559) == (context["step"] == 1)
			and choice_seen == (context["step"] == 1)
			and _scene.world_progress["route"] == route
			and _scene.world_progress["worldStep"] == context["step"] + 1
			and _scene.world_progress["gold"] == initial_gold + 1000
			and _scene.world_progress["completedBattle"] == "m7"
			and saved["ok"]
			and saved["progress"] == _scene.world_progress
		),
		"m7 step1 chooses6/8→route7/6; later steps keep route and settle1000 once"
	):
		return false
	var progress: Dictionary = _scene.world_progress.duplicate(true)
	_scene._show_title()
	_scene.load_game()
	deadline = Time.get_ticks_msec() + 5000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	return _expect(
		(
			_scene.story_player.world_ready
			and _scene.world_progress == progress
			and not _scene.story_player.dialogue.visible
		),
		"World cold read preserves the branch/reward without replay"
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
	if _scene.action_feedback.current_step.get("kind") == "tutorial":
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
	_cleanup()
	quit(1)
