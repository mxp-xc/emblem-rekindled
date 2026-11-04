extends SceneTree

const Matrix = preload("res://tests/test_m12_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
var _scene: Control
var _owned: String = ""
var _finished: bool = false
var _success: bool = false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	_owned = "user://m12_opening_flow_%d" % Time.get_ticks_usec()
	if not _expect(DirAccess.make_dir_absolute(_owned) == OK, "Claim fresh Main records"):
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
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[1], _zero)
	if not _expect(prepared["ok"], "Prepare actual empty-slot route3 opening"):
		return
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m12", prepared["source"], _zero)
	if not _expect(opened["ok"], "Open actual m12 Main opening: " + str(opened.get("error"))):
		return
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	_scene.busy = true
	_play_opening()
	var seen: Array[int] = []
	var commander_seen: bool = false
	var deadline: int = Time.get_ticks_msec() + 15000
	while not _finished and Time.get_ticks_msec() < deadline:
		var story: Control = _scene.story_player
		if story.dialogue.visible:
			if story.current_text_index not in seen:
				seen.append(story.current_text_index)
			story.advance()
		if story.commander.visible:
			commander_seen = true
			if not _expect(
				story.commander.draft["commander"] == 9,
				"Native formalParty default commander9 excludes temporary95/96"
			):
				return
			story.commander.commit()
		await process_frame
	if not _expect(
		(
			_finished
			and _success
			and commander_seen
			and seen == [151, 588, 589, 590, 168]
			and _scene.battle.event_completed("opening")
		),
		"Actual Main completes588/589/590,target168 and formalParty commander in order"
	):
		return
	var expected: Dictionary = _scene.battle.snapshot()
	if not _expect(
		_scene.battle_store.write(_scene.battle)["ok"], "Write actual completed opening"
	):
		return
	_scene._show_title()
	_scene.load_game()
	await process_frame
	if not _expect(
		_scene.battle.snapshot() == expected and not _scene.story_player.visible,
		"Main cold load preserves opening once marker without replay"
	):
		return
	_scene.queue_free()
	await process_frame
	_cleanup()
	print("PASS m12 Main opening588/589/590/168,formal commander,cold load")
	quit(0)


func _play_opening() -> void:
	_success = await _scene._play_opening()
	if _success:
		_scene.resume_battle(_scene.battle)
	_finished = true


# Public commands produce all results after this explicitly controlled boundary.
# Earlier prefixes follow Matrix.prepare; no claim of natural whole-chapter play.
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
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m12", prepared["source"], _zero)
	if not opened["ok"]:
		return opened
	while opened["battle"].round_number < round_number:
		var advanced: Dictionary = Rounds.advance(opened["battle"])
		if not advanced["ok"]:
			return advanced
	var state: Dictionary = opened["battle"].snapshot()
	state["events"]["opening"] = true
	if mode in ["ordinary", "boss", "victory", "required"]:
		duel_state(state, 41 if mode == "required" else 89, mode != "ordinary", mode == "required")
		if mode == "victory":
			for actor: Dictionary in state["units"]:
				if actor["faction"] == 2 and actor["id"] != 89 and actor["visible"]:
					actor["hp"] = 0
					actor["visible"] = false
					actor["flags"] |= 1
	elif mode == "magic":
		for actor: Dictionary in state["units"]:
			if actor["faction"] != 2:
				actor["hp"] = 60
				actor["maxHp"] = 60
	elif mode == "repair":
		duel_state(state, 1, false)
		for actor: Dictionary in state["units"]:
			if actor["id"] == 1:
				actor["inventory"] = [
					{"id": "m12:controlled:repair", "templateId": 57, "durability": 4}
				]
				actor["equippedInstanceId"] = ""
			if actor["id"] == 0:
				actor["inventory"][0]["durability"] = 1
	return Session.new().open(Matrix.CHAPTER, "m12", {"snapshot": state}, _zero)


static func duel_state(
	state: Dictionary, target: int, lethal: bool, required: bool = false
) -> void:
	var occupied: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [0, target] and actor["visible"] and actor["hp"] > 0:
			occupied[Vector2i(actor["x"], actor["y"])] = true
	var cell := Vector2i(-1, -1)
	for y: int in range(26):
		for x: int in range(24):
			if not occupied.has(Vector2i(x, y)) and not occupied.has(Vector2i(x, y + 1)):
				cell = Vector2i(x, y)
				break
		if cell.x >= 0:
			break
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [0, target]:
			continue
		actor["x"] = cell.x
		actor["y"] = cell.y + (0 if actor["id"] == 0 else 1)
		actor["visible"] = true
		actor["flags"] &= ~1
		actor["action"] = 0
		actor["hp"] = 1 if lethal and actor["id"] == (0 if required else target) else 60
		actor["maxHp"] = 60
		for key: String in actor["attributes"]:
			actor["attributes"][key] = (
				(30 if actor["id"] == (target if required else 0) else 0)
				if lethal
				else (30 if key in ["defense", "magic"] else 0)
			)
		if actor["id"] == 0:
			actor["inventory"] = [{"id": "m12:controlled:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m12:controlled:sword"


static func _zero(_limit: int) -> int:
	return 0


func _cleanup() -> void:
	if _owned.is_empty():
		return
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		_cleanup()
		quit(1)
	return condition
