extends SceneTree

const Matrix = preload("res://tests/test_m8_content.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const Session = preload("res://app/chapter_session.gd")
var _scene: Control
var _owned: String = ""


func _initialize() -> void:
	call_deferred("run")


# Controlled Main integration; platform input and natural full-battle acceptance are separate.
func run() -> void:
	await run_case(3, "arrival")


func run_case(context_index: int, mode: String) -> void:
	_owned = "user://test_m8_flow_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(_owned) or DirAccess.make_dir_absolute(_owned) != OK:
		fail("m8 Main requires a fresh owned record directory")
		return
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_set_speed(32)
	var context: Dictionary = Matrix.CONTEXTS[context_index]
	if not await _enter(context):
		return
	if mode == "arrival":
		if not await _arrivals():
			return
	elif mode == "combat":
		var duel: Dictionary = prepare_boundary(context, 3, "duel")
		if not _expect(duel["ok"], "Prepare actual m8 controlled duel"):
			return
		_scene._adopt_content(duel["content"], duel["battle"])
		_scene.resume_battle(duel["battle"])
		if not _information() or not await _duel(false) or not await _save_restore():
			return
		if not await _duel(true) or not await _summons() or not await _boss_ai():
			return
	elif mode == "ending":
		var opened: Dictionary = prepare_boundary(context, 3, "last")
		if not _expect(opened["ok"], "Prepare fixed-route ending with a real player summon"):
			return
		_scene._adopt_content(opened["content"], opened["battle"])
		_scene.resume_battle(opened["battle"])
		if not await _last_enemy(context):
			return
	else:
		fail("Unknown m8 Main test mode: " + mode)
		return
	_scene.queue_free()
	await process_frame
	_cleanup()
	print("PASS controlled m8 Main: selected route and requested actions")
	quit(0)


# Shared by the platform fixture generator. All mutations describe explicit
# controlled boundaries; no fixture claims naturally playing preceding combat.
static func prepare_boundary(
	context: Dictionary, round_number: int, mode: String = "quiet"
) -> Dictionary:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m8", prepared["source"], _zero)
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
		if actor["id"] in [45, 87]:
			actor["move"] = 0
		else:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
	if mode in ["duel", "boss"]:
		_duel_state(state, 87, mode == "boss")
	opened = Session.new().open(Matrix.CHAPTER, "m8", {"snapshot": state}, _zero)
	if not opened["ok"]:
		return opened
	if mode == "last":
		var held: String = staff_id(opened["battle"].unit(1))
		if held.is_empty() or not opened["battle"].has_method("summon_unit"):
			return {"ok": false, "error": "Missing actual player59 or summon runtime"}
		var summoned: Dictionary = opened["battle"].summon_unit(1, held)
		if not summoned["ok"]:
			return summoned
		state = opened["battle"].snapshot()
		for actor: Dictionary in state["units"]:
			if actor["faction"] == 2 and actor["id"] != 45:
				actor["hp"] = 0
				actor["visible"] = false
				actor["flags"] |= 65
		_duel_state(state, 45, true)
		state["events"]["boss_first_combat"] = true
		state["events"]["boss_death"] = true
		opened = Session.new().open(Matrix.CHAPTER, "m8", {"snapshot": state}, _zero)
	return opened


static func staff_id(actor: Dictionary) -> String:
	for held: Dictionary in actor["inventory"]:
		if held["templateId"] == 59:
			return held["id"]
	return ""


static func _duel_state(state: Dictionary, target: int, lethal: bool) -> void:
	# Move the real source13 sword1 into hero0's bag; do not invent held identity.
	var sword: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] == 13:
			for held: Dictionary in actor["inventory"]:
				if held["templateId"] == 1:
					sword = held
					actor["inventory"].erase(held)
					if actor["equippedInstanceId"] == held["id"]:
						actor["equippedInstanceId"] = ""
					break
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [0, target]:
			continue
		if actor["id"] == 0 and not sword.is_empty():
			actor["inventory"].push_front(sword)
			actor["equippedInstanceId"] = sword["id"]
		actor["visible"] = true
		actor["flags"] &= ~1
		actor["x"] = 10
		actor["y"] = 10 if actor["id"] == 0 else 11
		actor["maxHp"] = 60
		actor["hp"] = 1 if lethal and actor["id"] == target else 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = (
				(30 if actor["id"] == 0 else 0) if lethal else (30 if key == "defense" else 0)
			)


func _enter(context: Dictionary) -> bool:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not _expect(
		prepared["ok"] and prepared["kind"] == "reachable_world", "Use legal m7 completed world"
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
	_scene.story_player.world_node_requested.emit(8)
	if not _expect(_scene.story_player._travel_confirmation, "m8 opens travel confirmation"):
		return false
	_scene.story_player.go_back()
	await process_frame
	if not _expect(
		(
			_scene.world_progress == progress
			and _scene.story_player.world_ready
			and FileAccess.get_file_as_string(_scene.battle_store.path) == record
		),
		"Cancel m8 travel preserves the frontier and record"
	):
		return false
	_scene.story_player.world_node_requested.emit(8)
	var seen: Dictionary = {}
	var commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.current_text_index >= 0:
			seen[story.current_text_index] = true
		if story.commander.visible:
			commander = true
			if not _expect(story.commander.draft["commander"] == 1, "m8 offers commander1"):
				return false
			story.commander.commit()
		elif story._travel_confirmation:
			story.choices.get_child(0).pressed.emit()
		else:
			_drive()
		await process_frame
		if _scene.content["entry"]["battleId"] == "m8" and not _scene.busy:
			break
	return _expect(
		(
			_scene.content["entry"]["battleId"] == "m8"
			and not _scene.busy
			and commander
			and seen.has(560)
			and seen.has(561)
			and seen.has(164)
			and _scene.battle.event_completed("opening")
			and _scene.battle.commander_id == 1
		),
		"Legal world entry presents560/561/objective164 and commander1 before m8 input"
	)


func _arrivals() -> bool:
	_set_speed(1)
	var declared: Array = _scene.content["story"]["sequences"]["party_arrival"][0]["units"]
	if not _expect(declared.size() == 7, "m8 has seven old-slot entrances"):
		return false
	var south: Dictionary = {}
	var seen: Dictionary = {}
	while _scene.battle.round_number < 3:
		var advanced: Dictionary = Rounds.advance(_scene.battle)
		if not _expect(advanced["ok"], "Advance controlled waits to round2 event"):
			return false
		var committed: Dictionary = _scene.battle.snapshot()
		_scene._present_phase_events(advanced["events"])
		var deadline: int = Time.get_ticks_msec() + 10000
		while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
			var story: Control = _scene.story_player
			for entrance: Dictionary in declared:
				var identity: int = int(entrance["unitId"])
				if _scene.map.presentation_positions.has(identity):
					var position: Vector2 = _scene.map.presentation_positions[identity]
					var actor: Dictionary = _scene.battle.unit(identity)
					if position.y > actor["y"] and position.y <= actor["y"] + 3:
						south[identity] = true
			if story.dialogue.visible:
				seen[story.current_text_index] = true
				_drive()
			if not _expect(
				_scene.battle.snapshot() == committed, "Arrival visuals cannot mutate domain"
			):
				return false
			await process_frame
		if not _expect(not _scene.story_player.visible, "m8 arrival presentation finishes"):
			return false
	_set_speed(32)
	_scene.resume_battle(_scene.battle)
	return _expect(
		(
			south.size() == 7
			and seen.has(562)
			and seen.has(563)
			and seen.has(564)
			and _scene.battle.event_completed("party_arrival")
			and _scene.battle.unit(1)["x"] == 11
			and _scene.battle.unit(1)["y"] == 7
		),
		"Seven arrivals precede562/563/564;new1 stays at11,7"
	)


func _information() -> bool:
	_scene.selected_unit = 87
	_scene._show_information()
	_scene.unit_information.show_page(2)
	var actor: Dictionary = _scene.battle.unit(87)
	var portrait: Dictionary = _scene.content["interface"]["portraitByUnitId"]["87"]
	var image: Texture2D = load(
		_scene.content["entry"]["resourceDirectory"].path_join(
			_scene.content["story"]["images"]["portraits_18"]["texture"]
		)
	)
	var actual: Image = _scene.unit_information._portrait.texture.get_image()
	var correct: bool = (
		actor["name"] == "塔塔拉"
		and actor["classId"] == 5
		and portrait["portraitId"] == 18
		and actual.get_data() == image.get_image().get_data()
		and _scene.unit_information.body.get_node_or_null("Item_59") != null
	)
	_scene.unit_information.hide()
	return _expect(correct, "Boss87 information shows native name/portrait18/class5 and drop59")


func _duel(lethal: bool) -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	_duel_state(state, 87, lethal)
	if not _expect(_scene.battle.restore_snapshot(state)["ok"], "Restore controlled m8 duel"):
		return false
	_scene.resume_battle(_scene.battle)
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(0, 87))["ok"],
		"Actual m8 boss clips preload"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(0, 87)
	if not _expect(
		result["ok"] and _scene.battle.outcome.is_empty(), "Boss duel alone cannot win all-enemy m8"
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
				story.current_text_index == 566
				and not _expect(
					_shown(87) and not _scene.retirement_player.playing,
					"566 precedes boss retirement"
				)
			):
				return false
		_drive()
		await process_frame
	return _expect(
		(
			saw_battle
			and not _scene.busy
			and seen.has(565) == (not lethal)
			and seen.has(566) == lethal
			and _shown(87) == (not lethal)
			and _scene.battle.outcome.is_empty()
		),
		"Main plays565 once and566 before lethal retirement while other enemies remain"
	)


func _summons() -> bool:
	var opened: Dictionary = prepare_boundary(Matrix.CONTEXTS[3], 3)
	if not _expect(opened["ok"], "Prepare player59 Main boundary"):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	var before: Dictionary = _scene.battle.snapshot()
	var held: String = staff_id(_scene.battle.unit(1))
	_scene._show_unit_menu(Vector2i(11, 7))
	_scene.get_node("UnitStatus/Status/Actions/Heal").pressed.emit()
	_scene.target_selection.go_back()
	if not _expect(
		_scene.battle.snapshot() == before, "Cancel player59 list leaves battle unchanged"
	):
		return false
	_scene._unit_intent("heal", {})
	var view: Control = _scene.target_selection
	var selected: bool = false
	for index: int in range(view._items.size()):
		if view._items[index]["item"]["id"] == held:
			selected = true
			view.find_child("Staff_%d" % index, true, false).pressed.emit()
			break
	if not _expect(selected, "Actual59 is offered in the shared staff list"):
		return false
	var deadline: int = Time.get_ticks_msec() + 10000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		_drive()
		await process_frame
	var after: Dictionary = _scene.battle.snapshot()
	var bindings: Array = after.get("summonState", {}).get("bindings", [])
	if not _expect(
		(
			not _scene.busy
			and after["units"].size() == before["units"].size() + 1
			and bindings.size() == 1
			and _scene.battle.unit(1)["action"] == 2
		),
		"Selecting59 commits without target input and adds one presented summon"
	):
		return false
	var born: Dictionary = _scene.battle.unit(bindings[0]["unitId"])
	if not _expect(
		born["faction"] == 1 and not born["formal"] and _shown(born["id"]),
		"Player summon resolves actual ally family and is visible after ordinary movement"
	):
		return false
	return await _save_restore()


func _boss_ai() -> bool:
	var opened: Dictionary = prepare_boundary(Matrix.CONTEXTS[3], 3)
	if not _expect(opened["ok"], "Prepare actual Boss87 AI59 Main boundary"):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	var item: String = staff_id(_scene.battle.unit(87))
	_scene._end_turn()
	var deadline: int = Time.get_ticks_msec() + 15000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		_drive()
		await process_frame
	var bindings: Array = _scene.battle.snapshot().get("summonState", {}).get("bindings", [])
	if not _expect(
		not _scene.busy and _scene.battle.round_number == 4 and bindings.size() == 1,
		"Main enemy phase executes real Boss87 summon plan and returns to player round4"
	):
		return false
	var born: Dictionary = _scene.battle.unit(bindings[0]["unitId"])
	var remaining: int = -1
	for held: Dictionary in _scene.battle.unit(87)["inventory"]:
		if held["id"] == item:
			remaining = held["durability"]
	if not _expect(
		born["faction"] == 2 and born["id"] == 70 and _shown(70) and remaining == 9,
		"Boss AI consumes actual59 once and binds enemy70 presentation"
	):
		return false
	return await _save_restore()


func _save_restore() -> bool:
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Save only the owned m8 record"):
		return false
	var state: Dictionary = _scene.battle.snapshot()
	_scene._show_title()
	_scene.load_game()
	await process_frame
	return _expect(
		(
			_scene.battle.snapshot() == state
			and not _scene.story_player.visible
			and _scene.battle.snapshot()["events"] == state["events"]
		),
		"Main cold restore retains m8 events and inventory without opening/first-combat replay"
	)


func _last_enemy(context: Dictionary) -> bool:
	var initial_gold: int = _scene.battle.gold
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(0, 45))["ok"],
		"Last enemy pair resolves actual clips"
	):
		return false
	var summoned: Array[int] = []
	for actor: Dictionary in _scene.battle.snapshot()["units"]:
		if actor["faction"] == 1 and actor["visible"]:
			summoned.append(int(actor["id"]))
	if not _expect(not summoned.is_empty(), "Ending begins with an actual visible player summon"):
		return false
	var result: Dictionary = _scene.battle.attack_unit(0, 45)
	if not _expect(
		result["ok"] and _scene.battle.outcome.get("kind") == "victory",
		"Real last-enemy attack triggers m8 victory"
	):
		return false
	var previous_record: String = FileAccess.get_file_as_string(_scene.battle_store.path)
	_scene._present_player_action(result)
	return await _settled_world(context, initial_gold, summoned, previous_record)


func _settled_world(
	context: Dictionary, initial_gold: int, summoned: Array[int], previous_record: String
) -> bool:
	var seen: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 10000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		if _scene.story_player.dialogue.visible:
			seen[_scene.story_player.current_text_index] = true
		_drive()
		await process_frame
	if not _expect(
		(
			_scene.story_player.world_ready
			and seen.has(567)
			and seen.has(488) == (context["step"] == 2)
			and seen.has(568) == (context["step"] != 2)
			and _scene.world_progress["route"] == context["route"]
			and _scene.world_progress["worldStep"] == context["step"] + 1
			and _scene.world_progress["gold"] == initial_gold + 1000
			and _scene.world_progress["completedBattle"] == "m8"
			and FileAccess.get_file_as_string(_scene.battle_store.path) == previous_record
		),
		"m8 fixed route settles correct dialogue/1000 once"
	):
		return false
	for actor: Dictionary in _scene.world_progress["party"]:
		if not _expect(
			actor["id"] not in summoned and actor["formal"],
			"Summons never enter formal world party"
		):
			return false
	var progress: Dictionary = _scene.world_progress.duplicate(true)
	if not _expect(_scene.battle_store.write_progress(progress)["ok"], "Explicitly save the world"):
		return false
	if not _expect(
		_scene.battle_store.write_slot(1, progress)["ok"], "Write owned named world slot"
	):
		return false
	var named: Dictionary = _scene.battle_store.read_slot(1)
	_scene._show_title()
	_scene.load_game()
	deadline = Time.get_ticks_msec() + 5000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	return _expect(
		(
			named["ok"]
			and named["progress"] == progress
			and _scene.story_player.world_ready
			and _scene.world_progress == progress
			and not _scene.story_player.dialogue.visible
		),
		"Named/continue cold read retains route/reward without replay"
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
	_cleanup()
	quit(1)
