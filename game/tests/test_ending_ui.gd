extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
var scene: Control
var archive: RefCounted
var route: int = 0
var route_sent: bool = false
var seen: Array[int] = []
var saw_game_over: bool = false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	Engine.time_scale = 16
	for chosen: int in [0, 2, 4, 6]:
		await _victory(chosen)
	for required: int in [0, 9]:
		await _defeat(required)
	Engine.time_scale = 1
	print(
		(
			"PASS ending UI: southern escape, four saved routes, one reward, "
			+ "both deaths/title/load old archive"
		)
	)
	quit(0)


func _open() -> void:
	scene = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.settings["music_enabled"] = false
	scene.player.stop()
	archive = Store.new(scene.content, "user://test_ending_ui_%d.json" % Time.get_ticks_usec())
	scene.battle_store = archive
	route_sent = false
	seen = []
	saw_game_over = false
	scene.story_player.dialogue.visibility_changed.connect(_record)
	var reader := Timer.new()
	reader.wait_time = 0.2
	reader.ignore_time_scale = true
	reader.timeout.connect(_read)
	scene.add_child(reader)
	reader.start()


func _victory(chosen: int) -> void:
	await _open()
	route = chosen
	var battle: RefCounted = Battle.new(scene.content, func(_limit: int) -> int: return 0)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = 8
			actor["y"] = 23
	if not battle.restore_snapshot(state)["ok"]:
		fail("The controlled pre-escape battle must be a valid stable state")
		return
	scene.resume_battle(battle)
	await _cell(Vector2i(8, 23))
	await _cell(Vector2i(8, 24))
	while scene.busy:
		await process_frame
	if not battle.outcome.is_empty():
		fail("Reaching the southern row does not win before finishing the action")
		return
	await process_frame
	await process_frame
	await _tap(scene.get_node("UnitStatus/Status/Actions/Wait").get_global_rect().get_center())
	await _world()
	if battle.outcome.get("reason") != "escaped":
		fail("The Root ending must come from the original southern-escape command")
		return
	var saved: Dictionary = archive.read()
	if (
		not saved["ok"]
		or not saved.has("progress")
		or saved["progress"]["route"] != chosen
		or saved["progress"]["gold"] != 6000
		or saved["progress"]["party"].size() != 2
	):
		fail("Every source route must reach the real ending and persist its exact progress once")
		return
	for index: int in [485, 486, 487, 488, 34]:
		if index not in seen:
			fail("Victory must show the source dialogue and completion notice: " + str(index))
			return
	var progress: Dictionary = saved["progress"]
	scene.story_player.choices.get_node("World_title").pressed.emit()
	await _title()
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	await _world()
	if archive.read()["progress"] != progress:
		fail("Loading completed progress must not settle the mission or award money again")
		return
	await _close()


func _defeat(required: int) -> void:
	await _open()
	var battle: RefCounted = Battle.new(scene.content, func(_limit: int) -> int: return 0)
	var previous: Dictionary = battle.snapshot()
	if not archive.write(battle)["ok"]:
		fail("The prior action-boundary archive must exist before the controlled death")
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(archive.path)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == required:
			actor["x"] = 8
			actor["y"] = 20
			actor["hp"] = 1
		elif actor["id"] == 59:
			actor["x"] = 8
			actor["y"] = 21
	if not battle.restore_snapshot(state)["ok"]:
		fail("The controlled required-person death boundary must restore")
		return
	scene.resume_battle(battle)
	battle.end_phase()
	while battle.automatic_actor() >= 0:
		var id: int = battle.automatic_actor()
		var began: Dictionary = battle.begin_automatic_action(id)
		if not began["ok"] or not battle.wait_unit(id)["ok"]:
			fail("The controlled allied phase must advance through legal commands")
			return
	battle.end_phase()
	var prepared: Dictionary = scene.battle_clips.preload_pair(battle.attack_preview(59, required))
	if not prepared["ok"]:
		fail("The actual enemy/required-person clip pair must preload")
		return
	var result: Dictionary = battle.attack_unit(59, required)
	if not result["ok"] or battle.outcome.get("kind") != "defeat":
		fail("The real controlled enemy strike must produce the required-person defeat")
		return
	scene._present_player_action(result)
	await _title()
	if not saw_game_over or FileAccess.get_file_as_bytes(archive.path) != original:
		fail("The timed game-over flow must return to title and preserve the previous archive")
		return
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	await process_frame
	if (
		scene.title_screen.visible
		or scene.story_player.visible
		or scene.busy
		or scene.battle.snapshot() != previous
	):
		fail("Reading after either required death must restore the exact prior stable battle")
		return
	await _close()


func _read() -> void:
	if not scene.story_player.visible:
		return
	if scene.story_player.world_active and scene.story_player.world_ready:
		return
	if not scene.story_player.dialogue.visible and not scene.story_player.choices.visible:
		return
	if scene.story_player.choices.visible:
		if route_sent:
			return
		route_sent = true
		for index: int in range(route / 2):
			_send_key(KEY_DOWN)
	_send_key(KEY_ENTER)


func _record() -> void:
	if scene.story_player.dialogue.is_visible_in_tree():
		var index: int = scene.story_player.current_text_index
		if index >= 0:
			seen.append(index)
		if scene.story_player.dialogue.full_text == "游戏结束":
			saw_game_over = true


func _world() -> void:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not (scene.story_player.world_active and scene.story_player.world_ready):
		if Time.get_ticks_msec() > deadline:
			fail("The completed route must enter the persistent world after its guide and reveal")
			return
		await process_frame


func _cell(cell: Vector2i) -> void:
	scene.map.view.focus_cell(cell)
	await process_frame
	await _tap(scene.map.view.screen_at(Vector2(cell) + Vector2(0.5, 0.5)))


func _tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = position
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _key(code: int) -> void:
	_send_key(code)
	await process_frame


func _send_key(code: int) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


func _title() -> void:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not scene.title_screen.visible:
		if Time.get_ticks_msec() > deadline:
			fail(
				(
					(
						"Ending title timeout: route=%d kind=%s world=%s ready=%s "
						+ "dialogue=%s choices=%s slots=%s text=%s"
					)
					% [
						route,
						str(scene.battle.outcome.get("kind", "none")),
						scene.story_player.world_active,
						scene.story_player.world_ready,
						scene.story_player.dialogue.visible,
						scene.story_player.choices.visible,
						scene.save_slots.visible,
						scene.story_player.dialogue.full_text
					]
				)
			)
			return
		await process_frame


func _close() -> void:
	DirAccess.remove_absolute(archive.path)
	scene.player.stop()
	scene.queue_free()
	await process_frame
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
