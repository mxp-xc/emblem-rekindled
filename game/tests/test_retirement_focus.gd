extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _directory: String = ""
var _draws: int = 0
var _finished: bool = false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.content_scale_size = Vector2i(240, 320)
	root.size = Vector2i(240, 320)
	await process_frame
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var owned: String = "user://test_retirement_focus_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(owned) or DirAccess.make_dir_absolute(owned) != OK:
		fail("Retirement focus needs a fresh owned record directory")
		return
	_directory = owned
	scene.store.path = owned.path_join("settings.json")
	scene.battle_store.path = owned.path_join("continue.json")
	scene.title_screen.prologue.hide()
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	scene.menu_layer.find_child("Speed_4", true, false).pressed.emit()
	var opened: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, _roll)
	for id: String in ["m1", "m2"]:
		opened["battle"].win_with_assistance()
		var completed: Dictionary = opened["battle"].complete_victory(0)
		opened = Session.new().open(CHAPTER, id, {"progress": completed["progress"]}, _roll)
		if not opened["ok"]:
			fail("The focus fixture must enter the actual m2 content")
			return
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 7:
			actor["x"] = 10
			actor["y"] = 10
			actor["hp"] = 1
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 0
		elif actor["id"] == 33:
			actor["x"] = 12
			actor["y"] = 10
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["hp"] = 60
			actor["maxHp"] = 60
			for key: String in actor["attributes"]:
				actor["attributes"][key] = 30
			actor["inventory"] = [{"id": "silent:counter", "templateId": 31, "durability": 10}]
			actor["equippedInstanceId"] = "silent:counter"
	if not battle.restore_snapshot(state)["ok"]:
		fail("The HP1 attacker and its counter opponent must restore as legal m2 units")
		return
	scene._adopt_content(opened["content"], battle)
	scene.resume_battle(battle)
	# Both physical and logical window sizes are narrow, so later Main layouts
	# preserve this actual tactical viewport during the presentation.
	scene.map.set_zoom(6)
	scene._targeting_intent("target_highlight", {"target": 33, "action": "attack"})
	var viewport := Rect2(scene.map.view.viewport_origin, scene.map.view.viewport_size)
	if viewport.size != Vector2(240, 275):
		fail(
			"The focus case must use a genuinely narrow logical tactical viewport: " + str(viewport)
		)
		return
	if viewport.has_point(scene.map.view.screen_at(Vector2(10.5, 10.5))):
		fail("The narrow high-zoom target view must initially leave the attacker offscreen")
		return
	if not scene.battle_clips.preload_pair(battle.attack_preview(7, 33))["ok"]:
		fail("The controlled counter pair must have actual registered ordinary combat clips")
		return
	var result: Dictionary = battle.attack_unit(7, 33)
	var counter_kill: bool = false
	for strike: Dictionary in result.get("strikes", []):
		if strike["counter"] and strike["defender"] == 7 and strike["hpAfter"] == 0:
			counter_kill = true
	if (
		not result["ok"]
		or not result["storyBefore"].is_empty()
		or result["retirements"] != [{"unitId": 7, "beforeRetirement": [], "afterRetirement": []}]
		or not counter_kill
	):
		fail("Expected a silent counter death: " + str(result))
		return
	var committed: Dictionary = battle.snapshot()
	_draws = 0
	_play(scene, result)
	var saw_effect: bool = false
	var deadline: int = Time.get_ticks_msec() + 5000
	while not _finished and Time.get_ticks_msec() < deadline:
		if scene.retirement_player.playing:
			saw_effect = true
			if not scene.map.view.center.is_equal_approx(Vector2(10.5, 10.5)):
				fail(
					"A silent counter death must focus the dead attacker before starting map effects"
				)
				return
			for kind: String in ["bomb", "smoke"]:
				var timeline: RefCounted = scene.retirement_player.model
				var index: int = timeline.effect_frame(kind)
				if index < 0:
					continue
				var frame: Dictionary = scene.content["battleArt"]["effects"][kind]["frames"][index]
				var point: Vector2 = scene.map.view.screen_at(timeline.effect_anchor(kind) / 24)
				point += Vector2(frame["offsetX"], frame["offsetY"]) * scene.map.view.zoom
				var effect := Rect2(
					point, Vector2(frame["width"], frame["height"]) * scene.map.view.zoom
				)
				if not viewport.grow(0.1).encloses(effect):
					fail("Silent death effects stay inside the narrow map viewport")
					return
		await process_frame
	if not _finished or not saw_effect or _draws != 0 or battle.snapshot() != committed:
		fail(
			"Death camera and effects must finish without changing committed state or gameplay RNG"
		)
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	if not _cleanup():
		quit(1)
		return
	print(
		"PASS retirement focus: silent counter death, narrow viewport, visible FX, immutable state"
	)
	quit(0)


func _play(scene: Control, result: Dictionary) -> void:
	await scene._present_action_visuals(result)
	_finished = true


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _cleanup() -> bool:
	if _directory.is_empty():
		return true
	for name: String in DirAccess.get_files_at(_directory):
		if DirAccess.remove_absolute(_directory.path_join(name)) != OK:
			return false
	if DirAccess.remove_absolute(_directory) != OK:
		return false
	_directory = ""
	return true


func fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
