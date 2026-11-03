extends SceneTree

const Matrix = preload("res://tests/test_m9_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
var _scene: Control
var _owned: String


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await run_case("cycles")


func run_case(mode: String) -> void:
	_owned = "user://m9_flow_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		fail("Fresh m9 Main record directory required")
		return
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_set_speed(32)
	if not await _enter(
		Matrix.CONTEXTS[2] if mode in ["ending4", "ending6"] else Matrix.CONTEXTS[1]
	):
		return
	if mode == "cycles":
		if not await _cycles():
			return
	elif mode == "combat":
		var ordinary: Dictionary = prepare_boundary(Matrix.CONTEXTS[1], 3, "ordinary")
		if (
			not _adopt(ordinary)
			or not _information()
			or not await _attack(31, false)
			or not await _save_restore()
		):
			return
		var first: Dictionary = prepare_boundary(Matrix.CONTEXTS[1], 3, "first")
		if not _adopt(first) or not await _attack(31, true) or not await _save_restore():
			return
	elif mode == "summons":
		if not await _ai_summons():
			return
	else:
		var context: Dictionary = Matrix.CONTEXTS[2 if mode == "ending6" else 0]
		if not _adopt(prepare_boundary(context, 3, "last")):
			return
		var gold: int = _scene.battle.gold
		if not await _attack(32, true) or not await _settled(context, gold):
			return
	_scene.queue_free()
	await process_frame
	_cleanup()
	print("PASS m9 Main flow: ", mode)
	quit(0)


# Explicit controlled boundaries, shared by the platform record generator.
static func prepare_boundary(
	context: Dictionary, round_number: int, mode: String = "quiet"
) -> Dictionary:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m9", prepared["source"], _zero)
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
		actor["move"] = 0
		if actor["id"] in [31, 32]:
			actor["x"] = 1 if actor["id"] == 31 else 18
			actor["y"] = 1 if actor["id"] == 31 else 18
			if mode in ["ai", "mixed"]:
				actor["inventory"] = actor["inventory"].filter(
					func(item: Dictionary) -> bool: return int(item["templateId"]) == 59
				)
				actor["equippedInstanceId"] = ""
	if mode in ["ordinary", "first", "last"]:
		if mode == "last":
			for actor: Dictionary in state["units"]:
				if int(actor["id"]) == 31:
					actor["hp"] = 0
					actor["visible"] = false
					actor["flags"] |= 1
		duel_state(state, 32 if mode == "last" else 31, mode != "ordinary")
	return Session.new().open(Matrix.CHAPTER, "m9", {"snapshot": state}, _zero)


static func duel_state(state: Dictionary, target: int, lethal: bool) -> void:
	for actor: Dictionary in state["units"]:
		if int(actor["id"]) not in [0, target]:
			continue
		actor["visible"] = true
		actor["flags"] &= ~1
		actor["x"] = 9
		actor["y"] = 9 if int(actor["id"]) == 0 else 10
		actor["hp"] = 1 if lethal and int(actor["id"]) == target else 60
		actor["maxHp"] = 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = (
				(30 if int(actor["id"]) == 0 else 0) if lethal else (30 if key == "defense" else 0)
			)
		if int(actor["id"]) == 0:
			actor["inventory"] = [{"id": "m9:controlled:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m9:controlled:sword"


func _adopt(opened: Dictionary) -> bool:
	if not _expect(opened["ok"], "Open declared m9 boundary: " + str(opened.get("error"))):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	return true


func _enter(context: Dictionary) -> bool:
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	if not _expect(
		prepared["ok"] and prepared["kind"] == "reachable_world", "Use real m2 settlement world"
	):
		return false
	var previous: Dictionary = Session.new().completed_content(Matrix.CHAPTER, prepared["progress"])
	if not _expect(previous["ok"], "Resolve legal m2 completed frontier"):
		return false
	_scene._adopt_content(previous["content"])
	if not _expect(
		_scene.battle_store.write_progress(prepared["progress"])["ok"],
		"Write owned m2 world record"
	):
		return false
	await _scene._show_completed_progress(prepared["progress"])
	var record: String = FileAccess.get_file_as_string(_scene.battle_store.path)
	_scene.story_player.world_node_requested.emit(9)
	if not _expect(_scene.story_player._travel_confirmation, "m9 travel asks confirmation"):
		return false
	_scene.story_player.go_back()
	if not _expect(
		FileAccess.get_file_as_string(_scene.battle_store.path) == record,
		"Travel cancel keeps world record"
	):
		return false
	_scene.story_player.world_node_requested.emit(9)
	var saw_objective: bool = false
	var saw_commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		saw_objective = saw_objective or story.current_text_index == 165
		if story.commander.visible:
			saw_commander = true
			if not _expect(
				story.commander.draft["commander"] == 9,
				"First real party candidate9 is default commander"
			):
				return false
			story.commander.commit()
		elif story._travel_confirmation:
			story.choices.get_child(0).pressed.emit()
		else:
			_drive()
		await process_frame
		if _scene.content["entry"]["battleId"] == "m9" and not _scene.busy:
			break
	return _expect(
		(
			_scene.content["entry"]["battleId"] == "m9"
			and not _scene.busy
			and saw_objective
			and saw_commander
			and _scene.battle.commander_id == 9
		),
		"Legal world entry finishes tour/objective/commander before input"
	)


func _cycles() -> bool:
	for previous: int in [1, 2]:
		var advanced: Dictionary = Rounds.advance(_scene.battle)
		if not _expect(advanced["ok"], "Advance controlled Main waits"):
			return false
		var before: Dictionary = _scene.battle.snapshot()
		if not await _scene._present_phase_events(advanced["events"]):
			return _expect(false, "Present native clone arrivals")
		if not _expect(
			_scene.battle.snapshot() == before, "Queue presentation never mutates committed battle"
		):
			return false
	_scene.resume_battle(_scene.battle)
	return await _save_restore()


func _information() -> bool:
	_scene.selected_unit = 31
	_scene._show_information()
	_scene.unit_information.show_page(2)
	var valid: bool = (
		_scene.battle.unit(31)["classId"] == 5
		and _scene.unit_information.body.get_node_or_null("Item_59") != null
	)
	_scene.unit_information.hide()
	return _expect(valid, "Actual target31 information exposes its held59")


func _attack(target: int, lethal: bool) -> bool:
	var expected_text: int = (
		570 if _scene.battle.snapshot().get("campaign", {}).get("worldStep") == 5 else 571
	)
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(0, target))["ok"],
		"Actual m9 ordinary pair preloads"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(0, target)
	if not _expect(result["ok"], "Controlled real attack executes"):
		return false
	if not _expect(
		(
			_scene.battle.outcome.get("kind") == "victory"
			if target == 32 and lethal
			else _scene.battle.outcome.is_empty()
		),
		"One target alone continues; retiring both wins while other enemies remain"
	):
		return false
	_scene._present_player_action(result)
	var winning: bool = target == 32 and lethal
	var saw_battle: bool = false
	var saw_forbidden: bool = false
	var first_forbidden: Dictionary = {}
	var seen: Dictionary = {}
	var saw_guidance: bool = false
	var deadline: int = Time.get_ticks_msec() + 15000
	while (
		_scene.busy
		and not (winning and _scene.story_player.world_ready)
		and Time.get_ticks_msec() < deadline
	):
		saw_battle = saw_battle or _scene.battle_view.playing
		var panel: Control = _scene.story_player.dialogue
		if panel.is_visible_in_tree():
			var text_index: int = _scene.story_player.current_text_index
			var forbidden: bool
			if _scene.story_player.world_active:
				var guidance: String = "进度已保留。菜单可记录、读取存档；已亮起的地点是队伍的下一目标。"
				forbidden = (
					not winning
					or text_index != -1
					or panel.notice_mode
					or panel.full_text != guidance
				)
				saw_guidance = saw_guidance or not forbidden
			else:
				seen[text_index] = true
				forbidden = (
					not winning
					or (
						text_index != 34
						if panel.notice_mode
						else text_index not in [569, expected_text]
					)
				)
			saw_forbidden = saw_forbidden or forbidden
			if forbidden and first_forbidden.is_empty():
				first_forbidden = {
					"parentVisible": _scene.story_player.visible,
					"isVisibleInTree": panel.is_visible_in_tree(),
					"noticeMode": panel.notice_mode,
					"textIndex": text_index,
					"worldActive": _scene.story_player.world_active,
					"text": panel.full_text
				}
		_drive()
		await process_frame
	# Main deliberately remains busy in its world screen; victory completes at
	# world_ready, while ordinary tactical input completes when busy clears.
	var completed: bool = _scene.story_player.world_ready if winning else not _scene.busy
	var dialogue_contract: bool = (
		not winning
		or (
			seen.has(569)
			and seen.has(expected_text)
			and seen.has(34)
			and saw_guidance
			and not _scene.story_player.dialogue.is_visible_in_tree()
		)
	)
	if not (saw_battle and completed and not saw_forbidden and dialogue_contract):
		print(
			"M9_ATTACK_DIAGNOSTIC ",
			{
				"target": target,
				"lethal": lethal,
				"saw_battle": saw_battle,
				"busy": _scene.busy,
				"worldReady": _scene.story_player.world_ready,
				"seen": seen,
				"firstForbidden": first_forbidden
			}
		)
	return _expect(
		saw_battle and completed and not saw_forbidden and dialogue_contract,
		"Combat has no boss dialogue; victory shows its exact dialogue and missionComplete34"
	)


func _ai_summons() -> bool:
	if not _adopt(prepare_boundary(Matrix.CONTEXTS[1], 2, "ai")):
		return false
	_scene._end_turn()
	var deadline: int = Time.get_ticks_msec() + 15000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		_drive()
		await process_frame
	var state: Dictionary = _scene.battle.snapshot()
	return (
		_expect(
			(
				not _scene.busy
				and state.get("summonState", {}).get("bindings", []).size() == 2
				and state["cloneState"]["bindings"].size() == 2
				and _scene.battle.round_number == 3
			),
			"Both actual summoners use59 alongside the periodic clone wave"
		)
		and await _save_restore()
	)


func _save_restore() -> bool:
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Write owned m9 continue"):
		return false
	var expected: Dictionary = _scene.battle.snapshot()
	_scene._show_title()
	_scene.load_game()
	await process_frame
	return _expect(
		_scene.battle.snapshot() == expected and not _scene.story_player.visible,
		"Main cold read preserves all dynamic families and opening markers"
	)


func _settled(context: Dictionary, initial_gold: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not _scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		_drive()
		await process_frame
	var progress: Dictionary = _scene.world_progress
	if not _expect(
		(
			_scene.story_player.world_ready
			and progress["route"] == context["route"]
			and progress["worldStep"] == context["step"] + 1
			and progress["gold"] == initial_gold + 1000
			and progress["completedBattle"] == "m9"
		),
		"Fixed route ending awards1000 and reaches world"
	):
		return false
	if not _expect(
		_scene.battle_store.write_slot(1, progress)["ok"], "Write owned named world record"
	):
		return false
	var cold: Dictionary = _scene.battle_store.read_slot(1)
	return _expect(
		cold["ok"] and cold["progress"] == progress,
		"Named world cold read retains exact route and reward"
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


static func _zero(_limit: int) -> int:
	return 0


func _cleanup() -> void:
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)


func _expect(value: bool, message: String) -> bool:
	if not value:
		fail(message)
	return value


func fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
