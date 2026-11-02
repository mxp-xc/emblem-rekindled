extends SceneTree

const Matrix = preload("res://tests/test_m4_content.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const Session = preload("res://app/chapter_session.gd")
var _scene: Control
var _owned: String = ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var started: int = Time.get_ticks_msec()
	_owned = "user://test_m4_flow_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(_owned) or DirAccess.make_dir_absolute(_owned) != OK:
		fail("m4 Main test needs a newly owned record directory")
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
	if not await _world_entry():
		return
	for boundary: Dictionary in [
		{"round": 3, "reuse": false, "class": 36},
		{"round": 4, "reuse": true, "class": 28},
		{"round": 10, "reuse": false, "class": 32}
	]:
		var opened: Dictionary = prepare_boundary(boundary["round"], boundary["reuse"])
		if not _expect(opened["ok"], "Prepare controlled legal m4: " + str(opened.get("error"))):
			return
		_scene._adopt_content(opened["content"], opened["battle"])
		_scene.resume_battle(opened["battle"])
		var old_frame: PackedByteArray = PackedByteArray()
		if boundary["reuse"]:
			old_frame = _scene.map.animation_frames[105][0].get_image().get_data()
		_scene._end_turn()
		var saw_queue: bool = false
		var deadline: int = Time.get_ticks_msec() + 10000
		while _scene.busy and Time.get_ticks_msec() < deadline:
			saw_queue = saw_queue or _scene.story_player._arrival_queue_updates_remaining > 0
			_drive()
			await process_frame
			if _scene.story_player.world_ready:
				break
		if not _expect(saw_queue, "First end_phase result must present its actual clone event"):
			return
		if boundary["round"] == 10:
			if not _expect(
				(
					_scene.story_player.world_ready
					and _scene.world_progress["completedBattle"] == "m4"
					and _scene.world_progress["gold"] == opened["initialGold"] + 1000
				),
				"Entering round11 finishes survival immediately and saves the fixed-route world"
			):
				return
			continue
		var actor: Dictionary = _scene.battle.unit(105)
		if not _expect(
			(
				not _scene.busy
				and actor["visible"]
				and actor["classId"] == boundary["class"]
				and _scene.battle.round_number == boundary["round"] + 1
			),
			"An empty automatic queue still binds and displays the actual new generation"
		):
			return
		if boundary["reuse"]:
			if not _expect(
				(
					_scene.map.animation_frames[105][0].get_image().get_data() != old_frame
					and _scene.battle.snapshot()["warehouse"].has(opened["oldItem"])
				),
				"Same ID changes its actual map frame family while preserving the old opaque item"
			):
				return
			if not _information(actor) or not await _clone_combat():
				return
		if not await _save_restore():
			return
	_scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	_cleanup()
	print(
		"PASS actual m4 Main: world entry, first-result waves, rebind, clone combat, cold and round11"
	)
	print("PASS m4 Main elapsed_ms=%d at temporary speed32" % (Time.get_ticks_msec() - started))
	quit(0)


# Reusable QA boundary: all state is obtained through real Session and phase commands.
# Quiet/HP0 and the item transfer below are explicit controlled fixtures, not natural play.
static func prepare_boundary(round_number: int, reuse: bool = false) -> Dictionary:
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _zero)
	if not prepared["ok"]:
		return prepared
	var opened: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m4", {"progress": prepared["progress"]}, _zero
	)
	if not opened["ok"]:
		return opened
	var battle: RefCounted = opened["battle"]
	while battle.round_number < round_number:
		var advanced: Dictionary = Rounds.advance(battle)
		if not advanced["ok"]:
			return advanced
	var state: Dictionary = battle.snapshot()
	var old_item: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if reuse and actor["id"] == 105:
			old_item = actor["inventory"].pop_front()
			state["warehouse"].append(old_item.duplicate(true))
			actor["equippedInstanceId"] = ""
		if actor["faction"] == 0:
			actor["hp"] = actor["maxHp"]
			actor["visible"] = true
			actor["flags"] &= ~65
		else:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 65
	state["events"]["opening"] = true
	var restored: Dictionary = Session.new().open(Matrix.CHAPTER, "m4", {"snapshot": state}, _zero)
	if restored["ok"]:
		restored["oldItem"] = old_item
		restored["initialGold"] = state["gold"]
	return restored


func _world_entry() -> bool:
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[0], _zero)
	if not _expect(prepared["ok"], "Prepare actual m3 completed route0 world"):
		return false
	var previous: Dictionary = Session.new().completed_content(Matrix.CHAPTER, prepared["progress"])
	if not _expect(previous["ok"], "Resolve actual m3 frontier"):
		return false
	_scene._adopt_content(previous["content"])
	await _scene._show_completed_progress(prepared["progress"])
	_scene.story_player.world_node_requested.emit(4)
	var seen: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.current_text_index >= 0:
			seen[story.current_text_index] = true
		if story.commander.visible:
			if not _expect(story.commander.draft["commander"] == 8, "Opening offers recruit8"):
				return false
			story.commander.commit()
		elif story.choices.visible:
			story.choices.get_child(0).pressed.emit()
		else:
			_drive()
		await process_frame
		if _scene.content["entry"]["battleId"] == "m4" and not _scene.busy:
			break
	return _expect(
		(
			_scene.content["entry"]["battleId"] == "m4"
			and not _scene.busy
			and seen.has(464)
			and seen.has(518)
			and seen.has(519)
			and seen.has(520)
			and seen.has(160)
			and _scene.battle.event_completed("opening")
		),
		"Legal world travel, original opening/objective and commander precede playable m4"
	)


func _information(actor: Dictionary) -> bool:
	_scene.selected_unit = 105
	_scene._show_information()
	var image: Image = load(actor["sprite"]).get_image()
	var expected: Image = image.get_region(image.get_used_rect())
	var actual: Image = _scene.unit_information._portrait.texture.get_image()
	var correct: bool = (
		_scene.unit_information._identity.text == actor["name"] + " " + actor["className"]
		and actual.get_size() == expected.get_size()
		and actual.get_data() == expected.get_data()
	)
	_scene.unit_information.hide()
	return _expect(
		correct, "Main information resolves the new source name/class and actual sprite crop"
	)


func _clone_combat() -> bool:
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 8:
			actor["x"] = 10
			actor["y"] = 10
		if actor["id"] == 105:
			actor["x"] = 10
			actor["y"] = 11
	if not _expect(
		_scene.battle.restore_snapshot(state)["ok"], "Actual clone duel positions remain legal"
	):
		return false
	_scene.resume_battle(_scene.battle)
	var preview: Dictionary = _scene.battle.attack_preview(8, 105)
	if not _expect(
		_scene.battle_clips.preload_pair(preview)["ok"], "Recycled family has real battle clips"
	):
		return false
	var result: Dictionary = _scene.battle.attack_unit(8, 105)
	if not _expect(result["ok"], "Actual command attacks the recycled clone"):
		return false
	_scene._present_player_action(result)
	var saw_battle: bool = false
	var deadline: int = Time.get_ticks_msec() + 8000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		saw_battle = saw_battle or _scene.battle_view.playing
		_drive()
		await process_frame
	return _expect(
		saw_battle and not _scene.busy and _scene.battle.outcome.is_empty(),
		"Main plays actual independent combat against the new family without an early survival win"
	)


func _save_restore() -> bool:
	if not _expect(_scene.battle_store.write(_scene.battle)["ok"], "Save the owned clone battle"):
		return false
	var state: Dictionary = _scene.battle.snapshot()
	var frame: PackedByteArray = _scene.map.animation_frames[105][0].get_image().get_data()
	_scene._show_title()
	_scene.load_game()
	await process_frame
	return _expect(
		(
			_scene.battle.snapshot() == state
			and _scene.map.animation_frames[105][0].get_image().get_data() == frame
			and not _scene.story_player.visible
		),
		"Main cold restore preserves clone algebra/current frame without replaying its wave"
	)


func _drive() -> void:
	if _scene.story_player.dialogue.visible:
		_scene.story_player.advance()
	if _scene.action_feedback.current_step.get("kind") == "tutorial":
		_scene.action_feedback.go_back()


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
