extends SceneTree

const Matrix = preload("res://tests/test_m10_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
var _scene: Control
var _started_ms: int = 0
var _verified_entry_sources: Dictionary = {}
var _owned: String


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if not await _begin_flow("battle"):
		return
	if not _adopt(_prepare(Matrix.CONTEXTS[0], "ordinary")) or not _information():
		return
	_stage("ordinary", "begin")
	if not await _attack(90, false) or not await _save_restore():
		return
	_stage("ordinary", "end")
	_stage("boss", "begin")
	var state: Dictionary = _scene.battle.snapshot()
	duel_state(state, 90, true)
	if not _expect(
		_scene.battle.restore_snapshot(state)["ok"], "Prepare lethal boss after first575"
	):
		return
	_scene.resume_battle(_scene.battle)
	if not await _attack(90, true) or not await _save_restore():
		return
	_stage("boss", "end")
	_stage("revival", "begin")
	if not await _revival():
		return
	_stage("revival", "end")
	_stage("map", "begin")
	if not await _map51():
		return
	_stage("map", "end")
	_stage("AI", "begin")
	if not await _ai_summons():
		return
	_stage("AI", "end")
	await _end_flow()
	print("PASS m10 battle Main: boss575/576,80 revival,map51,AI59,information and cold saves")
	quit(0)


func _begin_flow(segment: String) -> bool:
	_started_ms = Time.get_ticks_msec()
	_stage("run", "begin")
	_owned = "user://m10_%s_flow_%d" % [segment, Time.get_ticks_usec()]
	if DirAccess.make_dir_absolute(_owned) != OK:
		fail("Fresh m10 Main record directory required")
		return false
	root.size = Vector2i(720, 1280)
	_stage("scene.create", "begin")
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_stage("scene.create", "end")
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_set_speed(32)
	return true


func _end_flow() -> void:
	_stage("run", "end")
	_scene.queue_free()
	await process_frame
	_cleanup()


func _prepare(context: Dictionary, mode: String) -> Dictionary:
	var name: String = "prepare.route%d.%s" % [context["route"], mode]
	_stage(name, "begin")
	var source: Dictionary = _verified_entry_sources.get(int(context["route"]), {}).duplicate(true)
	if source.is_empty():
		var prepared: Dictionary = Matrix.prepare(context, _zero)
		if not prepared["ok"]:
			_stage(name, "end")
			return prepared
		source = prepared["source"].duplicate(true)
	var result: Dictionary = prepare_boundary(context, 2, mode, source)
	if result["ok"]:
		# Cache only the immutable prefix input after a real Session opening succeeds.
		_verified_entry_sources[int(context["route"])] = source.duplicate(true)
	_stage(name, "end")
	return result


func _stage(name: String, edge: String) -> void:
	var row: Dictionary = {
		"stage": name, "edge": edge, "elapsedMs": Time.get_ticks_msec() - _started_ms
	}
	if is_instance_valid(_scene):
		row["busy"] = _scene.busy
		var story: Control = _scene.story_player
		if is_instance_valid(story):
			row["currentText"] = story.current_text_index
			row["worldActive"] = story.world_active
			row["worldReady"] = story.world_ready
	print("M10_FLOW_STAGE ", row)


# Explicit controlled boundaries shared by the platform record generator.
static func prepare_boundary(
	context: Dictionary, round_number: int, mode: String = "quiet", prepared_source: Dictionary = {}
) -> Dictionary:
	var prepared: Dictionary = (
		{"ok": true, "source": prepared_source.duplicate(true)}
		if not prepared_source.is_empty()
		else Matrix.prepare(context, _zero)
	)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m10", prepared["source"], _zero)
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
		if actor["id"] not in [90, 39, 36]:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 1
	if mode in ["ordinary", "boss"]:
		duel_state(state, 90, mode == "boss")
	elif mode in ["revive", "last"]:
		for actor: Dictionary in state["units"]:
			if actor["faction"] == 2 and actor["id"] != 39:
				actor["hp"] = 0
				actor["visible"] = false
				actor["flags"] |= 1
		duel_state(state, 39, true)
	elif mode == "map":
		map_state(state)
	elif mode == "ai":
		for actor: Dictionary in state["units"]:
			if actor["id"] == 90:
				actor["hp"] = 0
				actor["visible"] = false
				actor["flags"] |= 1
	opened = Session.new().open(Matrix.CHAPTER, "m10", {"snapshot": state}, _zero)
	if not opened["ok"]:
		return opened
	if mode == "last":
		var knocked: Dictionary = opened["battle"].attack_unit(0, 39)
		if not knocked["ok"] or knocked.get("revivals", []).size() != 1:
			return {"ok": false, "error": "Expected actual80 revival before last-enemy boundary"}
		state = opened["battle"].snapshot()
		duel_state(state, 39, true)
		opened = Session.new().open(Matrix.CHAPTER, "m10", {"snapshot": state}, _zero)
	return opened


static func duel_state(state: Dictionary, target: int, lethal: bool) -> void:
	for actor: Dictionary in state["units"]:
		if int(actor["id"]) not in [0, target]:
			continue
		actor["visible"] = true
		actor["flags"] &= ~1
		actor["x"] = 13
		actor["y"] = 12 if actor["id"] == 0 else 13
		actor["maxHp"] = 60
		actor["hp"] = 1 if lethal and actor["id"] == target else 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = (
				(30 if actor["id"] == 0 else 0) if lethal else (30 if key == "defense" else 0)
			)
		if actor["id"] == 0:
			actor["inventory"] = [{"id": "m10:controlled:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m10:controlled:sword"


static func map_state(state: Dictionary) -> void:
	state["round"] = 2
	var lightning: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] == 90:
			for held: Dictionary in actor["inventory"]:
				if held["templateId"] == 51:
					lightning = held
					actor["inventory"].erase(held)
					actor["equippedInstanceId"] = ""
					break
	for actor: Dictionary in state["units"]:
		if actor["id"] == 8:
			actor["x"] = 10
			actor["y"] = 10
			actor["inventory"].append(lightning)
			actor["equippedInstanceId"] = lightning["id"]
			actor["attributes"]["magic"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] in [90, 39]:
			actor["x"] = 12
			actor["y"] = 10 if actor["id"] == 90 else 11
			actor["hp"] = 1
			actor["attributes"]["magic"] = 0
			actor["attributes"]["speed"] = 0
			actor["attributes"]["luck"] = 0


func _adopt(opened: Dictionary) -> bool:
	if not _expect(opened["ok"], "Open declared m10 boundary: " + str(opened.get("error"))):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	return true


func _enter(context: Dictionary) -> bool:
	var entry_name: String = "entry.route%d" % context["route"]
	_stage(entry_name + ".prepare", "begin")
	var prepared: Dictionary = Matrix.prepare(context, _zero)
	_stage(entry_name + ".prepare", "end")
	if not _expect(
		prepared["ok"] and prepared["kind"] == "reachable_world", "Use real m4 settlement world"
	):
		return false
	var previous: Dictionary = Session.new().completed_content(Matrix.CHAPTER, prepared["progress"])
	if not _expect(previous["ok"], "Resolve legal m4 completed frontier"):
		return false
	_scene._adopt_content(previous["content"])
	if not _expect(
		_scene.battle_store.write_progress(prepared["progress"])["ok"],
		"Write owned m4 world record"
	):
		return false
	await _scene._show_completed_progress(prepared["progress"])
	var record: String = FileAccess.get_file_as_string(_scene.battle_store.path)
	_scene.story_player.world_node_requested.emit(10)
	if not _expect(_scene.story_player._travel_confirmation, "m10 travel asks confirmation"):
		return false
	_scene.story_player.go_back()
	if not _expect(
		FileAccess.get_file_as_string(_scene.battle_store.path) == record,
		"Travel cancel keeps world record"
	):
		return false
	_stage(entry_name + ".travel", "begin")
	_scene.story_player.world_node_requested.emit(10)
	var saw_opening: Dictionary = {}
	var saw_objective: bool = false
	var saw_commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		saw_objective = saw_objective or story.current_text_index == 166
		if story.dialogue.is_visible_in_tree():
			saw_opening[story.current_text_index] = true
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
		if _scene.content["entry"]["battleId"] == "m10" and not _scene.busy:
			break
	_stage(entry_name + ".travel", "end")
	var entered: bool = _expect(
		(
			_scene.content["entry"]["battleId"] == "m10"
			and not _scene.busy
			and saw_objective
			and saw_opening.has(572)
			and saw_opening.has(573)
			and saw_opening.has(574)
			and saw_commander
			and _scene.battle.commander_id == 9
		),
		"Legal world entry finishes tour/objective/commander before input"
	)
	if entered:
		# Reuse only the immutable zero-roll source whose legal entry just passed.
		# Each controlled mode still opens its own Session and executes its commands.
		_verified_entry_sources[int(context["route"])] = prepared["source"].duplicate(true)
	return entered


func _information() -> bool:
	_scene.selected_unit = 90
	_scene._show_information()
	_scene.unit_information.show_page(2)
	var valid: bool = (
		_scene.battle.unit(90)["classId"] == 13
		and _scene.unit_information.body.get_node_or_null("Item_76") != null
	)
	_scene.unit_information.hide()
	return _expect(valid, "Mara native class13 information exposes51/59/drop76")


func _attack(target: int, lethal: bool) -> bool:
	var winning: bool = (
		target == 39
		and lethal
		and _scene.battle.unit(39)["inventory"].all(
			func(item: Dictionary) -> bool: return item["templateId"] != 80
		)
	)
	var expected_text: int = 578 if _scene.battle.snapshot()["campaign"]["worldStep"] == 5 else 579
	if not _expect(
		_scene.battle_clips.preload_pair(_scene.battle.attack_preview(0, target))["ok"],
		"Actual ordinary pair preloads"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(0, target)
	if not _expect(result["ok"], "Controlled real attack executes"):
		return false
	_scene._present_player_action(result)
	var saw_battle: bool = false
	var forbidden: bool = false
	var seen: Dictionary = {}
	var guidance: bool = false
	var deadline: int = Time.get_ticks_msec() + 15000
	while (
		_scene.busy
		and not (winning and _scene.story_player.world_ready)
		and Time.get_ticks_msec() < deadline
	):
		saw_battle = saw_battle or _scene.battle_view.playing
		var story: Control = _scene.story_player
		var panel: Control = story.dialogue
		if panel.is_visible_in_tree():
			var text: int = story.current_text_index
			if story.world_active:
				var expected_guidance: String = "进度已保留。菜单可记录、读取存档；已亮起的地点是队伍的下一目标。"
				var valid: bool = (
					winning
					and text == -1
					and not panel.notice_mode
					and panel.full_text == expected_guidance
				)
				guidance = guidance or valid
				forbidden = forbidden or not valid
			else:
				seen[text] = true
				var allowed: Array = (
					[577, expected_text, 34]
					if winning
					else ([576] if lethal and target == 90 else ([575] if target == 90 else []))
				)
				forbidden = forbidden or text not in allowed
		_drive()
		await process_frame
	var completed: bool = _scene.story_player.world_ready if winning else not _scene.busy
	if not _expect(
		saw_battle and completed and not forbidden,
		"Ordinary/boss/victory phases obey exact dialogue contract"
	):
		return false
	if winning:
		return _expect(
			seen.has(577) and seen.has(expected_text) and seen.has(34) and guidance,
			"Victory shows577,correct578/579,mission34 then separate world guidance"
		)
	return _expect(
		(
			(seen.has(575) if not lethal and target == 90 else true)
			and (seen.has(576) if lethal and target == 90 else true)
			and _scene.battle.outcome.is_empty()
		),
		"Boss-only death or80 revival does not clear remaining enemies"
	)


func _revival() -> bool:
	if not _adopt(_prepare(Matrix.CONTEXTS[0], "revive")):
		return false
	if not await _attack(39, true):
		return false
	var actor: Dictionary = _scene.battle.unit(39)
	return (
		_expect(
			(
				actor["visible"]
				and actor["hp"] == actor["maxHp"]
				and actor["inventory"].all(
					func(item: Dictionary) -> bool: return item["templateId"] != 80
				)
			),
			"Main80 revival retains visible fullHP unit and consumes ring once"
		)
		and await _save_restore()
	)


func _map51() -> bool:
	if not _adopt(_prepare(Matrix.CONTEXTS[0], "map")):
		return false
	var held: String = ""
	for item: Dictionary in _scene.battle.unit(8)["inventory"]:
		if item["templateId"] == 51:
			held = item["id"]
	var result: Dictionary = _scene.battle.cast_map_attack(8, held, 90)
	if not _expect(
		result["ok"] and result.get("revivals", []).size() == 1, "Actual51 commits map80 revival"
	):
		return false
	_scene._present_player_action(result)
	var saw_map: bool = false
	var deadline: int = Time.get_ticks_msec() + 15000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		saw_map = saw_map or _scene.map_attack_player.playing
		if not _expect(
			(
				not _scene.battle_view.playing
				and not _scene.story_player.dialogue.is_visible_in_tree()
			),
			"Map51 uses no ordinary battle or575/576 dialogue"
		):
			return false
		_drive()
		await process_frame
	return (
		_expect(
			(
				saw_map
				and not _scene.busy
				and _scene.battle.unit(39)["visible"]
				and not _scene.battle.event_completed("boss_first_combat")
				and not _scene.battle.event_completed("boss_death")
			),
			"Map51 excludes ordinary hooks and binds revived39"
		)
		and await _save_restore()
	)


func _ai_summons() -> bool:
	if not _adopt(_prepare(Matrix.CONTEXTS[0], "ai")):
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
				and state.get("summonState", {}).get("bindings", []).size() == 1
				and _scene.battle.round_number == 3
			),
			"Actual source36 uses59 through Main enemy AI"
		)
		and await _save_restore()
	)


func _save_restore() -> bool:
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Write owned m10 continue"):
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
			and progress["completedBattle"] == "m10"
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
