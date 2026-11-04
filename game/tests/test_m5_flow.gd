extends SceneTree

const Matrix = preload("res://tests/test_m5_content.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
const Session = preload("res://app/chapter_session.gd")
var _scene: Control
var _owned: String = ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await run_cases([{"context": 3, "route": 5, "target": 46, "events": true}])


func run_cases(samples: Array) -> void:
	var started: int = Time.get_ticks_msec()
	_owned = "user://test_m5_flow_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(_owned) or DirAccess.make_dir_absolute(_owned) != OK:
		fail("m5 Main requires a newly owned record directory")
		return
	root.size = Vector2i(720, 1280)
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
	for sample: Dictionary in samples:
		if not await _enter(Matrix.CONTEXTS[sample["context"]]):
			return
		if sample["events"] and not await _arrivals():
			return
		if not _identities() or not await _duel(sample["target"]) or not await _save_restore():
			return
		if not await _boss_and_world(sample["route"]):
			return
	_scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	_cleanup()
	print("PASS actual m5 Main: selected travel, events, battles, cold and route")
	print("PASS m5 Main elapsed_ms=%d at temporary speed32" % (Time.get_ticks_msec() - started))
	quit(0)


# QA reuses this short, validated phase0 boundary. Slot visibility stays as the
# actual source phase requires; this does not make hidden arrivals visible early.
static func prepare_boundary(context: Dictionary, round_number: int) -> Dictionary:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m5", {"progress": prepared["progress"]}, _zero
	)
	if not opened["ok"]:
		return opened
	while opened["battle"].round_number < round_number:
		var advanced: Dictionary = Rounds.advance(opened["battle"])
		if not advanced["ok"]:
			return advanced
	var state: Dictionary = opened["battle"].snapshot()
	state["events"]["opening"] = true
	for actor: Dictionary in state["units"]:
		if actor["faction"] == 0 or actor["id"] in [64, 65, 66, 67, 68, 69]:
			continue
		if actor["id"] in [18, 46, 70, 84]:
			actor["move"] = 0
		else:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
	return Session.new().open(Matrix.CHAPTER, "m5", {"snapshot": state}, _zero)


func _enter(context: Dictionary) -> bool:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not _expect(prepared["ok"], "Prepare a legal m0/m4 frontier for m5"):
		return false
	var previous: Dictionary = Session.new().completed_content(Matrix.CHAPTER, prepared["progress"])
	if not _expect(previous["ok"], "Resolve the actual preceding completed map"):
		return false
	_scene._adopt_content(previous["content"])
	if not _expect(
		_scene.battle_store.write_progress(prepared["progress"])["ok"], "Owned frontier"
	):
		return false
	await _scene._show_completed_progress(prepared["progress"])
	_scene.story_player.world_node_requested.emit(5)
	var seen: Dictionary = {}
	var commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.current_text_index >= 0:
			seen[story.current_text_index] = true
		if story.commander.visible:
			commander = true
			if not _expect(story.commander.draft["commander"] == 2, "m5 offers new recruit2"):
				return false
			story.commander.commit()
		elif story.choices.visible:
			story.choices.get_child(0).pressed.emit()
		else:
			_drive()
		await process_frame
		if _scene.content["entry"]["battleId"] == "m5" and not _scene.busy:
			break
	return _expect(
		(
			_scene.content["entry"]["battleId"] == "m5"
			and not _scene.busy
			and commander
			and seen.has(465)
			and seen.has(532)
			and seen.has(533)
			and seen.has(161)
			and _scene.battle.event_completed("opening")
		),
		"Actual world travel, source opening/objective and commander precede playable m5"
	)


func _arrivals() -> bool:
	var seen: Dictionary = {}
	while _scene.battle.round_number < 4:
		var advanced: Dictionary = Rounds.advance(_scene.battle)
		if not _expect(advanced["ok"], "Advance actual m5 using controlled wait commands"):
			return false
		var committed: Dictionary = _scene.battle.snapshot()
		_scene._present_phase_events(advanced["events"])
		var deadline: int = Time.get_ticks_msec() + 8000
		while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
			var story: Control = _scene.story_player
			if story.dialogue.visible:
				seen[story.current_text_index] = true
				if story.current_text_index == 538:
					if not _expect(
						story._arrival_queue_updates_remaining == 0, "538 follows the whole queue"
					):
						return false
					for identity: int in [64, 65, 66, 67, 68, 69]:
						if not _expect(
							_shown(identity),
							"Each actual random reinforcement is visible before538"
						):
							return false
				_drive()
			if not _expect(
				_scene.battle.snapshot() == committed, "Presentation never mutates domain"
			):
				return false
			await process_frame
		if not _expect(not _scene.story_player.visible, "Both arrival sequences finish"):
			return false
	_scene.resume_battle(_scene.battle)
	return _expect(
		seen.has(534) and seen.has(535) and seen.has(536) and seen.has(537) and seen.has(538),
		"Original side entrance dialogues and native queue follow-up all play through Main"
	)


func _identities() -> bool:
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Matrix.CHAPTER))
	var definition: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(chapter["battles"]["m5"])
	)
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chapter["library"]))
	var classes: Array[String] = []
	for identity: int in [46, 70]:
		_scene.selected_unit = identity
		_scene._show_information()
		var actor: Dictionary = _scene.battle.unit(identity)
		if not _expect(
			(
				actor["sourceId"] == 46
				and actor["classId"] == (8 if identity == 46 else 24)
				and _scene.unit_information._actor["id"] == identity
				and (
					_scene.unit_information._identity.text
					== actor["name"] + " " + actor["className"]
				)
			),
			"Main information independently selects each actual identity sharing source46"
		):
			return false
		var recipe: String = "source_46_job_%d_faction_2" % actor["classId"]
		var profile: Dictionary = library["profiles"][definition["profiles"][recipe]]
		var source: Texture2D = load(profile["unit"]["sprite"])
		var original: Image = source.get_image()
		var expected: Image = original.get_region(original.get_used_rect())
		var shown: Image = _scene.unit_information._portrait.texture.get_image()
		if not _expect(
			shown.get_size() == expected.get_size() and shown.get_data() == expected.get_data(),
			"Each source46 identity shows its independently declared fallback image"
		):
			return false
		classes.append(profile["unit"]["className"])
		_scene.unit_information.hide()
	return _expect(
		classes == ["刀斧手", "信徒"], "Source46 identities retain their distinct original classes"
	)


func _duel(target: int) -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [2, target]:
			continue
		actor["x"] = 10
		actor["y"] = 10 if actor["id"] == 2 else 11
		actor["maxHp"] = 60
		actor["hp"] = 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = 30 if key == "defense" else 0
	if not _expect(
		_scene.battle.restore_snapshot(state)["ok"], "Controlled nonlethal source46 duel"
	):
		return false
	_scene.resume_battle(_scene.battle)
	var preview: Dictionary = _scene.battle.attack_preview(2, target)
	if not _expect(
		_scene.battle_clips.preload_pair(preview)["ok"], "Actual source46 pair preloads"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(2, target)
	if not _expect(result["ok"], "Real source46 ordinary command succeeds"):
		return false
	_scene._present_player_action(result)
	var saw_battle: bool = false
	var deadline: int = Time.get_ticks_msec() + 8000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		saw_battle = saw_battle or _scene.battle_view.playing
		_drive()
		await process_frame
	return _expect(
		saw_battle and not _scene.busy and _scene.battle.outcome.is_empty(), "Real duel finishes"
	)


func _boss_and_world(route: int) -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [46, 70]:
			actor["x"] = 8 if actor["id"] == 46 else 6
			actor["y"] = 9 if actor["id"] == 46 else 11
		if actor["id"] == 2:
			actor["x"] = 10
			actor["y"] = 10
			actor["hp"] = 60
			actor["maxHp"] = 60
			actor["action"] = 0
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 30
		if actor["id"] == 84:
			actor["x"] = 10
			actor["y"] = 11
			actor["hp"] = 1
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 0
	if not _expect(
		_scene.battle.restore_snapshot(state)["ok"], "Legal HP1 boss with other enemies alive"
	):
		return false
	_scene.resume_battle(_scene.battle)
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(2, 84))["ok"], "Boss clips"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(2, 84)
	if not _expect(
		result["ok"] and _scene.battle.outcome.get("kind") == "victory", "Boss retirement wins"
	):
		return false
	var other_enemies_alive: bool = (
		_scene.battle.unit(46)["hp"] > 0 and _scene.battle.unit(70)["hp"] > 0
	)
	_scene._present_player_action(result)
	var seen: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 8000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.dialogue.visible:
			seen[story.current_text_index] = true
			if story.current_text_index == 540:
				if not _expect(
					_shown(84) and not _scene.retirement_player.playing,
					"540 precedes boss retirement"
				):
					return false
		if story.choices.visible and not story.world_active:
			var options: Array = _scene.content["story"]["routeChoices"]
			for index: int in range(options.size()):
				if int(options[index]["routeIndex"]) == route:
					story.choices.get_child(index).pressed.emit()
					break
		_drive()
		await process_frame
	var early: bool = int(state["campaign"]["worldStep"]) == 1
	var saved: Dictionary = _scene.battle_store.read()
	if not _expect(
		(
			_scene.story_player.world_ready
			and seen.has(539)
			and seen.has(540)
			and seen.has(541) == early
			and _scene.world_progress["route"] == route
			and _scene.world_progress["worldStep"] == int(state["campaign"]["worldStep"]) + 1
			and other_enemies_alive
			and saved["ok"]
			and saved.has("battle")
		),
		"Boss settlement preserves other enemies and the previously saved battle"
	):
		return false
	var progress: Dictionary = _scene.world_progress.duplicate(true)
	if not _expect(_scene.battle_store.write_progress(progress)["ok"], "Explicitly save the world"):
		return false
	var restored: Dictionary = _scene.battle_store.read()
	return _expect(
		restored["ok"] and restored.has("progress") and restored["progress"] == progress,
		"Cold world read preserves the selected route and completed progress"
	)


func _save_restore() -> bool:
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Save both source46 identities"):
		return false
	var state: Dictionary = _scene.battle.snapshot()
	_scene._show_title()
	_scene.load_game()
	await process_frame
	return _expect(
		_scene.battle.snapshot() == state, "Main cold restore keeps both distinct source46 actors"
	)


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
