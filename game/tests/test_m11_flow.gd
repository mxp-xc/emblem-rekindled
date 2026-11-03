extends SceneTree

const Matrix = preload("res://tests/test_m11_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const GROUPS: Array = [[44, 45, 46], [56, 57, 58, 59], [47, 48, 49], [55, 61, 62, 63]]
var _scene: Control
var _owned: String
var _finished: bool = false
var _success: bool = false
var _started_ms: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if not await _begin_flow("opening"):
		return
	if not await _opening() or not await _round_two() or not await _cold():
		return
	await _end_flow()
	print("PASS m11 Main: opening50/580, four groups and stable cold records")
	quit(0)


func _begin_flow(segment: String) -> bool:
	_started_ms = Time.get_ticks_msec()
	_stage("run.begin")
	_owned = "user://m11_%s_flow_%d" % [segment, Time.get_ticks_usec()]
	if not _expect(DirAccess.make_dir_absolute(_owned) == OK, "Claim owned Main records"):
		return false
	root.size = Vector2i(720, 1280)
	_stage("scene.create.begin")
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_stage("scene.create.end")
	_scene.store.path = _owned.path_join("settings.json")
	_scene.battle_store.path = _owned.path_join("continue.json")
	_scene.title_screen.prologue.hide()
	_set_speed(32)
	return true


func _end_flow() -> void:
	_scene.queue_free()
	await process_frame
	_cleanup()


func _opening() -> bool:
	_stage("opening.prepare.begin")
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _zero)
	_stage("opening.prepare.end")
	if not _expect(prepared["ok"], "Prepare m11 opening context"):
		return false
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m11", prepared["source"], _zero)
	_stage("opening.session.end")
	if not _expect(opened["ok"], "Open actual m11 for Main opening"):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	_stage("opening.adopt.end")
	_scene.map.prepare_opening(_scene.content["story"]["initialBattlePresentation"])
	if not _expect(
		(
			_scene.map.presentation_positions.get(50) == Vector2(11, 13)
			and _scene.battle.unit(50)["x"] == 11
			and _scene.battle.unit(50)["y"] == 12
		),
		"50 starts at presentation11,13 while its final business cell is11,12"
	):
		return false
	_scene.busy = true
	_finished = false
	_stage("opening.play.begin")
	_play_opening()
	var seen: Dictionary = {}
	var commander: bool = false
	var deadline: int = Time.get_ticks_msec() + 15000
	while not _finished and Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.dialogue.visible:
			seen[story.current_text_index] = true
			if story.current_text_index == 580:
				if not _expect(
					(
						not story.dialogue.portrait.visible
						and not story.dialogue.speaker_label.visible
						and story.dialogue._tone == "enemy"
					),
					"580 has enemy tone without portrait or name plate"
				):
					return false
		if story.commander.visible:
			commander = true
			if not _expect(story.commander.draft["commander"] == 9, "Default commander is9"):
				return false
			story.commander.commit()
		else:
			_drive()
		await process_frame
	_stage("opening.play.end", {"seen": seen.keys(), "commanderSeen": commander})
	return _expect(
		(
			_finished
			and _success
			and commander
			and seen.has(580)
			and seen.has(581)
			and seen.has(582)
			and seen.has(167)
			and _scene.battle.event_completed("opening")
			and _scene.battle.unit(50)["y"] == 12
			and _scene.map.presentation_positions.is_empty()
		),
		"Main completes opening/target/commander and clears only presentation overrides"
	)


func _play_opening() -> void:
	_success = await _scene._play_opening()
	if _success:
		_scene.resume_battle(_scene.battle)
	_finished = true


func _round_two() -> bool:
	_stage("round2.advance.begin")
	var first: Dictionary = Rounds.advance(_scene.battle)
	var second: Dictionary = Rounds.advance(_scene.battle)
	_stage("round2.advance.end")
	if not _expect(first["ok"] and second["ok"], "Advance actual waiting phases to round2 event"):
		return false
	var events: Array = second["events"]
	var arrivals: int = 0
	for event: Dictionary in events:
		if event["kind"] == "reinforcements":
			arrivals += event["arrivals"].size()
	if not _expect(arrivals == 14, "Round2 returns14 actual successful arrivals"):
		return false
	_finished = false
	_scene.busy = true
	_stage("round2.present.begin")
	_present(events)
	var observed: Array[int] = []
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var visible: Array[int] = []
		for actor: Dictionary in _scene.map.visible_units():
			visible.append(int(actor["id"]))
		for index: int in range(GROUPS.size()):
			var count: int = 0
			for identity: int in GROUPS[index]:
				if identity in visible:
					count += 1
			if not _expect(
				count == 0 or count == GROUPS[index].size(), "Each group reveals together"
			):
				return false
			if count > 0 and index not in observed:
				if not _expect(
					index == observed.size(), "Four groups reveal in original focus order"
				):
					return false
				observed.append(index)
		if not _expect(
			114 not in visible and 115 not in visible, "Hidden clone templates stay hidden"
		):
			return false
		if _finished:
			break
		await process_frame
	_stage("round2.present.end", {"observed": observed})
	return _expect(
		_finished and _success and observed == [0, 1, 2, 3], "Main presents all four groups"
	)


func _present(events: Array) -> void:
	_success = await _scene._present_phase_events(events)
	_scene.busy = false
	_finished = true


func _cold() -> bool:
	_stage("cold.begin")
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Write isolated Main record"):
		return false
	var expected: Dictionary = _scene.battle.snapshot()
	_scene._show_title()
	_scene.load_game()
	await process_frame
	_stage("cold.end")
	return _expect(
		_scene.battle.snapshot() == expected and not _scene.story_player.visible,
		"Main cold load keeps completed opening/round2 without replay"
	)


func _boss_flow(context: Dictionary) -> bool:
	_stage("boss.prepare.begin", {"route": context["route"]})
	var opened: Dictionary = prepare_boundary(context, 1, "ordinary")
	_stage("boss.prepare.end", {"route": context["route"]})
	if not _expect(opened["ok"], "Open ordinary boss Main boundary"):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	if not await _combat(false, context):
		return false
	if not await _cold():
		return false
	var state: Dictionary = _scene.battle.snapshot()
	duel_state(state, 88, true)
	if not _expect(
		_scene.battle.restore_snapshot(state)["ok"], "Prepare boss lethal after first hook"
	):
		return false
	_scene.resume_battle(_scene.battle)
	if not await _combat(true, context):
		return false
	var progress: Dictionary = _scene.world_progress
	if not _expect(
		(
			progress["completedBattle"] == "m11"
			and progress["worldNode"] == 11
			and progress["worldStep"] == context["step"] + 1
			and progress["route"] == context["route"]
		),
		"Both Main endings reach the same node with current route and next step"
	):
		return false
	if not _expect(_scene.battle_store.write_slot(1, progress)["ok"], "Write owned named ending"):
		return false
	var cold: Dictionary = _scene.battle_store.read_slot(1)
	return _expect(cold["ok"] and cold["progress"] == progress, "Named ending cold read is exact")


func _combat(lethal: bool, context: Dictionary) -> bool:
	_stage("boss.attack.begin", {"route": context["route"], "lethal": lethal})
	var result: Dictionary = _scene.battle.attack_unit(0, 88)
	if not _expect(result["ok"], "Main controlled actual boss attack"):
		return false
	_scene._present_player_action(result)
	_stage("boss.presentation.begin", {"lethal": lethal})
	var seen: Dictionary = {}
	var saw_battle: bool = false
	var ending: int = 586 if context["step"] == 5 else 587
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		saw_battle = saw_battle or _scene.battle_view.playing
		if _scene.story_player.dialogue.visible and not _scene.story_player.world_active:
			var text: int = _scene.story_player.current_text_index
			seen[text] = true
			if not _expect(
				text in ([584, 585, ending, 34] if lethal else [583]),
				"Boss Main uses exact first/death/ending sequence without replay"
			):
				return false
		_drive()
		await process_frame
		if _scene.story_player.world_ready if lethal else not _scene.busy:
			break
	_stage("boss.presentation.end", {"lethal": lethal, "seen": seen.keys()})
	return _expect(
		(
			saw_battle
			and (
				(
					seen.has(584)
					and seen.has(585)
					and seen.has(ending)
					and seen.has(34)
					and _scene.story_player.world_ready
				)
				if lethal
				else seen.has(583) and not _scene.busy
			)
		),
		"Actual Main completes ordinary hook or boss retirement and settlement"
	)


# Controlled combat boundaries; results are produced by later real commands.
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
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m11", prepared["source"], _zero)
	if not opened["ok"]:
		return opened
	while opened["battle"].round_number < round_number:
		var advanced: Dictionary = Rounds.advance(opened["battle"])
		if not advanced["ok"]:
			return advanced
	var state: Dictionary = opened["battle"].snapshot()
	state["events"]["opening"] = true
	for actor: Dictionary in state["units"]:
		if actor["faction"] != 0:
			actor["move"] = 0
	if mode in ["ordinary", "boss", "revive", "required"]:
		duel_state(state, 88, mode != "ordinary")
		for actor: Dictionary in state["units"]:
			if mode == "revive" and actor["id"] == 88:
				actor["inventory"].append(
					{"id": "m11:controlled:ring", "templateId": 80, "durability": 1}
				)
			if mode == "required" and actor["id"] == 0:
				actor["hp"] = 1
				actor["attributes"]["defense"] = 0
				actor["attributes"]["strength"] = 0
				actor["attributes"]["speed"] = 0
				actor["attributes"]["luck"] = 0
			if mode == "required" and actor["id"] == 88:
				actor["hp"] = 60
				actor["attributes"]["strength"] = 30
				actor["attributes"]["defense"] = 30
				actor["attributes"]["skill"] = 30
				actor["attributes"]["speed"] = 30
				actor["attributes"]["luck"] = 30
	elif mode.begins_with("map"):
		map_state(state, int(mode.trim_prefix("map")) if mode != "map" else 49)
	var result: Dictionary = Session.new().open(Matrix.CHAPTER, "m11", {"snapshot": state}, _zero)
	if mode == "required" and result["ok"]:
		var preview: Dictionary = result["battle"].attack_preview(0, 88)
		if not preview["ok"]:
			return preview
		var counter: Dictionary = preview["forecasts"]["88"]
		var attack: Dictionary = preview["forecasts"]["0"]
		if (
			not counter["canAttack"]
			or int(counter["hit"]) != 100
			or int(counter["damage"]) < result["battle"].unit(0)["hp"]
			or int(attack["criticalDamage"]) >= result["battle"].unit(88)["hp"]
		):
			return {
				"ok": false,
				"error": "Required fixture must survive attack then guarantee lethal counter",
				"preview": preview
			}
	return result


static func duel_state(state: Dictionary, target: int, lethal: bool) -> void:
	var occupied: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [0, target] and actor["visible"] and actor["hp"] > 0:
			occupied[Vector2i(actor["x"], actor["y"])] = true
	var cell := Vector2i.ZERO
	for y: int in range(24):
		for x: int in range(23):
			if not occupied.has(Vector2i(x, y)) and not occupied.has(Vector2i(x, y + 1)):
				cell = Vector2i(x, y)
				break
		if cell != Vector2i.ZERO:
			break
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [0, target]:
			continue
		actor["visible"] = true
		actor["flags"] &= ~1
		actor["x"] = cell.x
		actor["y"] = cell.y + (0 if actor["id"] == 0 else 1)
		actor["maxHp"] = 60
		actor["hp"] = 1 if lethal and actor["id"] == target else 60
		actor["action"] = 0
		for key: String in actor["attributes"]:
			actor["attributes"][key] = (
				(30 if actor["id"] == 0 else 0) if lethal else (30 if key == "defense" else 0)
			)
		if actor["id"] == 0:
			actor["inventory"] = [{"id": "m11:controlled:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m11:controlled:sword"


static func map_state(state: Dictionary, template: int = 49) -> void:
	duel_state(state, 88, true)
	var boss_cell := Vector2i.ZERO
	var caster_cell := Vector2i.ZERO
	var occupied: Dictionary = {}
	for actor: Dictionary in state["units"]:
		var cell := Vector2i(actor["x"], actor["y"])
		if actor["id"] == 88:
			boss_cell = cell
		if actor["id"] != 8 and actor["visible"] and actor["hp"] > 0:
			occupied[cell] = true
	for y: int in range(25):
		for x: int in range(23):
			var cell := Vector2i(x, y)
			if absi(x - boss_cell.x) + absi(y - boss_cell.y) == 2 and not occupied.has(cell):
				caster_cell = cell
				break
		if caster_cell != Vector2i.ZERO:
			break
	for actor: Dictionary in state["units"]:
		if actor["id"] == 8:
			actor["inventory"] = [
				{"id": "m11:controlled:map", "templateId": template, "durability": 3}
			]
			actor["equippedInstanceId"] = "m11:controlled:map"
			actor["attributes"]["magic"] = 30
			actor["attributes"]["skill"] = 30
			actor["x"] = caster_cell.x
			actor["y"] = caster_cell.y
		if actor["id"] == 88:
			actor["attributes"]["magic"] = 0
			actor["attributes"]["speed"] = 0
			actor["attributes"]["luck"] = 0


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
	if _owned.is_empty():
		return
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _stage(stage: String, details: Dictionary = {}) -> void:
	var row: Dictionary = {"stage": stage, "elapsedMs": Time.get_ticks_msec() - _started_ms}
	row.merge(details)
	if is_instance_valid(_scene):
		row["busy"] = _scene.busy
		var story: Control = _scene.story_player
		if is_instance_valid(story):
			row["text"] = story.current_text_index
			row["dialogue"] = story.dialogue.visible
			row["reading"] = story.dialogue.reading
			row["commander"] = story.commander.visible
			row["worldReady"] = story.world_ready
		row["battlePlaying"] = _scene.battle_view.playing
		row["feedback"] = _scene.action_feedback.current_step
	print("M11_FLOW_STAGE ", row)


func _expect(value: bool, message: String) -> bool:
	if not value:
		_stage("assertion.failed", {"message": message})
		push_error(message)
		_cleanup()
		quit(1)
	return value
