extends SceneTree

const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var settings_path: String = "user://test_world_bonus_%d.json" % Time.get_ticks_usec()
	scene.store.path = settings_path
	scene.settings["bonus_battle_used"] = false
	if scene._bonus_available({"worldStep": 5}) or not scene._bonus_available({"worldStep": 6}):
		_fail("The bonus entry must unlock at the sixth world step")
		return
	var ids: Array[int] = [0, 9, 6, 7, 3, 8]
	var jobs: Array[int] = [0, 4, 20, 12, 16, 12]
	var party: Array = []
	for index: int in range(ids.size()):
		party.append({"id": ids[index], "sourceId": ids[index], "classId": jobs[index]})
	var content: Dictionary = Content.new().load_chapter(
		CHAPTER,
		"m18",
		{"party": party, "partyOrder": [9, 0, 6, 7, 3, 8], "route": 0, "worldStep": 6}
	)
	if not content.get("ok", false):
		_fail("Encounter fixture cannot load: " + str(content))
		return
	var template := Battle.new(content, _roll)
	var members: Array = []
	for id: int in ids:
		var actor: Dictionary = template.unit(id).duplicate(true)
		actor["x"] = 0
		actor["y"] = 0
		actor["flags"] = 0
		actor["action"] = 0
		actor["visible"] = true
		actor["hp"] = actor["maxHp"]
		members.append(actor)
	var progress: Dictionary = {
		"chapterId": "chapter_1",
		"completedBattle": "m10",
		"worldNode": 10,
		"worldStep": 6,
		"worldLocation": 10,
		"route": 0,
		"party": members,
		"warehouse": [],
		"gold": 7000,
		"commander": 0,
		"commandPolicy": 0,
		"chapterStats": {"rounds": 1, "playerRetirements": 0, "allyRetirements": 0}
	}
	scene.story_player.set("_tick_seconds", 0.001)
	await scene._show_completed_progress(progress)
	var now: int = Time.get_ticks_msec() + 10000
	var generated: bool = false
	for seed_value: int in range(500):
		scene._world_encounter_rng.seed = seed_value
		scene._world_encounter = {"lastCheckMs": now - 10000, "marker": null}
		scene._update_world_encounter(now)
		if scene._world_encounter["marker"] == {"node": 4, "classId": 32}:
			generated = true
			break
	if not generated or scene.story_player.get("_encounter_frames").is_empty():
		_fail("The world scheduler must display a generated native enemy sprite")
		return
	var probe: Node = load("res://app/playtest_probe.gd").new()
	probe._scene = scene
	var observed: Dictionary = probe._snapshot()
	probe.free()
	if (
		observed["worldEncounter"] != {"node": 4, "classId": 32}
		or observed["worldNodes"].is_empty()
	):
		_fail("Read-only platform diagnostics must expose the live marker and world node positions")
		return
	scene._world_encounter["lastCheckMs"] = Time.get_ticks_msec()
	scene._world_node(0)
	if not await _wait_for_battle(scene, "m18"):
		_fail("Travel must stop at the intermediate enemy and enter m18")
		return
	if scene.battle.snapshot()["campaign"]["encounterLocation"] != 4:
		_fail("The encounter snapshot must record the actual interrupted node")
		return
	scene.battle.win_with_assistance()
	scene._finish_outcome()
	if not await _wait_for_world(scene):
		_fail("Encounter victory must return to the world")
		return
	if (
		scene.world_progress["worldStep"] != 6
		or scene.world_progress["worldLocation"] != 4
		or scene.world_progress["completedBattle"] != "m10"
		or scene.world_progress["gold"] != 8000
	):
		_fail("Encounter victory must preserve mainline progress at the interrupted location")
		return
	scene.story_player.set("_tick_seconds", 0.001)
	scene._world_encounter["marker"] = {"node": 10, "classId": 16}
	scene.story_player.set_world_encounter(scene._world_encounter["marker"])
	scene._world_node(5)
	for unused: int in range(100):
		await process_frame
		if scene.story_player.get("_travel_confirmation") and scene.story_player.choices.visible:
			scene.story_player.choice_selected.emit(0)
			break
	await process_frame
	if (
		scene._world_transitioning
		or scene.world_progress["worldLocation"] != 4
		or scene._world_encounter["marker"]["node"] != 10
	):
		_fail("Canceling travel must preserve the current location and encounter")
		return
	scene._world_node(5)
	if not await _wait_for_battle(scene, "m17"):
		_fail("Travel toward the next mainline battle must first stop at the intermediate enemy")
		return
	if scene.battle.snapshot()["campaign"]["encounterLocation"] != 10:
		_fail("The m17 encounter must start at the interrupted node")
		return
	scene.battle.win_with_assistance()
	scene._finish_outcome()
	if not await _wait_for_world(scene) or scene.world_progress["gold"] != 9000:
		_fail("The second encounter must return to the world with its reward")
		return
	if not await _check_completed_world(scene):
		return
	DirAccess.remove_absolute(settings_path)
	scene.queue_free()
	await process_frame
	print("PASS world encounter: scheduler, marker, intermediate travel, battle and return")
	quit(0)


func _check_completed_world(scene: Control) -> bool:
	var ids: Array[int] = [0, 9, 6, 7, 3, 8, 2, 4]
	var jobs: Array[int] = [0, 4, 20, 12, 16, 12, 8, 8]
	var party: Array = []
	for index: int in range(ids.size()):
		party.append({"id": ids[index], "sourceId": ids[index], "classId": jobs[index]})
	var loaded: Dictionary = Content.new().load_chapter(
		CHAPTER,
		"m18",
		{"party": party, "partyOrder": [9, 0, 6, 7, 3, 8, 2, 4], "route": 0, "worldStep": 10}
	)
	if not loaded.get("ok", false):
		_fail("Completed-world encounter fixture cannot load")
		return false
	var template := Battle.new(loaded, _roll)
	var members: Array = []
	for id: int in ids:
		var actor: Dictionary = template.unit(id).duplicate(true)
		actor["x"] = 0
		actor["y"] = 0
		actor["flags"] = 0
		actor["action"] = 0
		actor["visible"] = true
		actor["hp"] = actor["maxHp"]
		members.append(actor)
	var statistics: Dictionary = {"rounds": 1, "playerRetirements": 0, "allyRetirements": 0}
	var sorted: Array = members.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	var rows: Array = []
	for actor: Dictionary in sorted:
		rows.append({"id": actor["id"], "level": actor["level"], "power": 0})
	var result: Dictionary = {
		"party": rows, "gold": 7000, "totalPower": 0, "chapterStats": statistics
	}
	var progress: Dictionary = {
		"chapterId": "chapter_1",
		"completedBattle": "m15",
		"worldNode": 15,
		"worldStep": 10,
		"worldLocation": 15,
		"route": 0,
		"party": members,
		"warehouse": [],
		"gold": 7000,
		"commander": 0,
		"commandPolicy": 0,
		"chapterStats": statistics,
		"chapterCompleted": true,
		"chapterResult": result
	}
	var previous: Dictionary = load("res://app/chapter_session.gd").new().completed_content(
		CHAPTER, progress
	)
	if not previous.get("ok", false):
		_fail("Completed-world fixture cannot restore its terminal content")
		return false
	scene._adopt_content(previous["content"])
	scene.story_player.set("_tick_seconds", 0.001)
	await scene._show_completed_progress(progress)
	scene._world_encounter["marker"] = {"node": 11, "classId": 32}
	scene.story_player.set_world_encounter(scene._world_encounter["marker"])
	scene._world_node(6)
	if not await _wait_for_battle(scene, "m18"):
		_fail("A completed world must allow an encounter during travel")
		return false
	scene.battle.win_with_assistance()
	scene._finish_outcome()
	if not await _wait_for_world(scene):
		_fail("A postgame encounter must return without reopening the chapter result")
		return false
	if (
		scene.world_progress["worldStep"] != 10
		or scene.world_progress["worldLocation"] != 11
		or scene.world_progress["chapterResult"] != result
		or not scene.world_progress.get("chapterResultHistorical", false)
	):
		_fail("A postgame encounter must preserve the historical chapter result")
		return false
	scene.story_player._show_world_menu()
	if scene.story_player.choices.find_child("World_bonus", false, false) == null:
		_fail("The unused bonus must appear after the sixth world step")
		return false
	scene._world_action("bonus")
	for unused: int in range(100):
		await process_frame
		if scene.story_player.get("_travel_confirmation") and scene.story_player.choices.visible:
			scene.story_player.choice_selected.emit(0)
			break
	await process_frame
	if scene.settings.get("bonus_battle_used", false) or FileAccess.file_exists(scene.store.path):
		_fail("Canceling bonus entry must not consume it or write settings")
		return false
	scene._world_action("bonus")
	if not await _wait_for_battle(scene, "m19"):
		_fail("Confirming the bonus must open m19")
		return false
	var reloaded: Dictionary = (
		load("res://persistence/settings_store.gd").new(scene.store.path).read()
	)
	if not reloaded["ok"] or not reloaded["settings"]["bonus_battle_used"]:
		_fail("Entering m19 must persist the one-time flag")
		return false
	scene.battle.win_with_assistance()
	scene._finish_outcome()
	if not await _wait_for_world(scene):
		_fail("The bonus battle must return to the completed world")
		return false
	scene.story_player._show_world_menu()
	if (
		scene.story_player.choices.find_child("World_bonus", false, false) != null
		or scene.world_progress["worldLocation"] != 11
		or scene.world_progress["chapterResult"] != result
	):
		_fail("A used bonus must disappear and preserve the world and historical result")
		return false
	return true


func _wait_for_battle(scene: Control, battle_id: String) -> bool:
	for unused: int in range(2000):
		await create_timer(0.005).timeout
		if scene.story_player.dialogue.visible:
			scene.story_player.advance()
		elif scene.story_player.get("_travel_confirmation") and scene.story_player.choices.visible:
			scene.story_player.choice_selected.emit(1)
		if scene.content["entry"]["battleId"] == battle_id and scene.world_progress.is_empty():
			return true
	return false


func _wait_for_world(scene: Control) -> bool:
	for unused: int in range(2000):
		await create_timer(0.005).timeout
		if scene.story_player.dialogue.visible:
			scene.story_player.advance()
		if scene.story_player.world_active and scene.story_player.world_ready:
			return true
	return false


func _roll(_limit: int) -> int:
	return 0


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
