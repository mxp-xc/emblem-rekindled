extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _directory: String = ""
var _draws: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var owned: String = "user://test_retirement_flow_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(owned) or DirAccess.make_dir_absolute(owned) != OK:
		fail("Retirement flow needs a fresh owned record directory")
		return
	_directory = owned
	scene.store.path = owned.path_join("settings.json")
	scene.battle_store.path = owned.path_join("continue.json")
	scene.title_screen.prologue.hide()
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	var opened: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, _roll)
	for sample: Dictionary in [
		{"battle": "m1", "hero": 6, "boss": 81, "first": 496, "death": 497, "distance": 2},
		{"battle": "m2", "hero": 7, "boss": 82, "first": 503, "death": 504, "distance": 1}
	]:
		opened["battle"].win_with_assistance()
		var completed: Dictionary = opened["battle"].complete_victory(0)
		opened = Session.new().open(
			CHAPTER, sample["battle"], {"progress": completed["progress"]}, _roll
		)
		if not opened["ok"] or not _directions(opened, sample):
			return
		if not await _main_flow(scene, opened, sample, false):
			return
		if not await _main_flow(scene, opened, sample, false, true):
			return
	# A small authored-style fixture exercises the future two-stage seam on the
	# already available m2 assets. It is not an implementation or acceptance of m3.
	if not await _main_flow(
		scene,
		opened,
		{"battle": "m2", "hero": 7, "boss": 82, "first": 503, "death": 504, "distance": 1},
		true
	):
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	if not _cleanup():
		quit(1)
		return
	print(
		"PASS retirement flow: real m1/m2, both ordinary directions, B4/JSON, death phases and rewards"
	)
	quit(0)


func _controlled(opened: Dictionary, sample: Dictionary, lethal: bool) -> Dictionary:
	var state: Dictionary = opened["battle"].snapshot()
	state["events"]["opening"] = true
	for unit: Dictionary in state["units"]:
		if unit["id"] not in [sample["hero"], sample["boss"], 0]:
			continue
		if unit["id"] == 0:
			unit["x"] = 13
			unit["y"] = 12
			continue
		unit["x"] = 10
		unit["y"] = 10 + (sample["distance"] if unit["id"] == sample["boss"] else 0)
		unit["maxHp"] = 60
		unit["hp"] = 1 if lethal and unit["id"] == sample["boss"] else 60
		for key: String in unit["attributes"]:
			unit["attributes"][key] = 30 if unit["id"] == sample["hero"] and lethal else 0
		if not lethal:
			unit["attributes"]["defense"] = 30
			unit["attributes"]["magic"] = 30
	return state


func _directions(opened: Dictionary, sample: Dictionary) -> bool:
	for enemy_starts: bool in [false, true]:
		var battle: RefCounted = Battle.new(opened["content"], _roll, false)
		if not _expect(
			battle.restore_snapshot(_controlled(opened, sample, false))["ok"],
			"Both original boss directions use a legal stable controlled battle"
		):
			return false
		if enemy_starts and not _enemy_phase(battle):
			return false
		var result: Dictionary = battle.attack_unit(
			sample["boss"] if enemy_starts else sample["hero"],
			sample["hero"] if enemy_starts else sample["boss"]
		)
		if not _expect(
			(
				result["ok"]
				and result["storyBefore"] == ["boss_first_combat"]
				and result["retirements"].is_empty()
			),
			"Boss attacking or defending triggers the actual first-combat sequence once"
		):
			return false
		if enemy_starts:
			while battle.automatic_actor() >= 0:
				battle.wait_unit(battle.automatic_actor())
			if not _expect(
				battle.end_phase()["ok"], "Return the controlled enemy attack to player phase"
			):
				return false
		var store := Store.new(opened["content"], _directory.path_join("unused.json"))
		var encoded: Dictionary = store.encode(battle)
		if not _expect(encoded["ok"], "A nonlethal original first combat remains savable"):
			return false
		_draws = 0
		var loaded: Dictionary = store.decode(
			JSON.parse_string(JSON.stringify(encoded["record"])), _roll
		)
		if not _expect(
			loaded["ok"] and _draws == 0 and loaded["battle"].snapshot() == battle.snapshot(),
			"Actual boss flag and once markers survive JSON without initialization draws"
		):
			return false
		var legacy: Dictionary = _controlled(opened, sample, false)
		for unit: Dictionary in legacy["units"]:
			if unit["id"] == sample["boss"]:
				unit["flags"] |= 4
		battle = Battle.new(opened["content"], _roll, false)
		if not _expect(
			battle.restore_snapshot(legacy)["ok"], "Restore a native B4-only old snapshot"
		):
			return false
		result = battle.attack_unit(sample["hero"], sample["boss"])
		if not _expect(
			(
				result["ok"]
				and result["storyBefore"].is_empty()
				and not battle.event_completed("boss_first_combat")
			),
			"A native B4 marker suppresses the dialogue without inventing a new once marker"
		):
			return false
	return true


func _enemy_phase(battle: RefCounted) -> bool:
	if not _expect(battle.end_phase()["ok"], "Begin the actual automatic phase"):
		return false
	while battle.phase != 2:
		while battle.automatic_actor() >= 0:
			battle.wait_unit(battle.automatic_actor())
		if not _expect(battle.end_phase()["ok"], "Reach actual enemy phase"):
			return false
	return true


func _main_flow(
	scene: Control,
	opened: Dictionary,
	sample: Dictionary,
	two_stages: bool,
	enemy_starts: bool = false
) -> bool:
	var content: Dictionary = opened["content"].duplicate(true)
	if two_stages:
		content["story"]["sequences"]["after_fixture"] = [
			{"kind": "dialogue", "text": {"sourceTextIndex": -1, "speakerId": 0, "text": "退场后示例"}}
		]
		for event: Dictionary in content["story"]["combatEvents"]:
			if event["trigger"] == "unitDeath":
				event["afterRetirement"] = "after_fixture"
	var battle: RefCounted = Battle.new(content, _roll, false)
	if not _expect(
		battle.restore_snapshot(_controlled(opened, sample, true))["ok"],
		"Restore legal HP1 before actual Main combat"
	):
		return false
	if enemy_starts and not _enemy_phase(battle):
		return false
	scene._adopt_content(content, battle)
	scene.resume_battle(battle)
	var attacker: int = sample["boss"] if enemy_starts else sample["hero"]
	var defender: int = sample["hero"] if enemy_starts else sample["boss"]
	var preview: Dictionary = battle.attack_preview(attacker, defender)
	if not _expect(
		(
			scene.battle_clips.preload_pair(preview)["ok"]
			and scene.retirement_player.preflight()["ok"]
		),
		"Actual combat and map retirement resources must preload"
	):
		return false
	var result: Dictionary = battle.attack_unit(attacker, defender)
	if not _expect(
		result["ok"] and battle.unit(sample["boss"])["hp"] == 0,
		"The actual ordinary command must kill the HP1 boss"
	):
		return false
	var committed: Dictionary = battle.snapshot()
	scene._present_player_action(result)
	var saw_first: bool = false
	var saw_before: bool = false
	var saw_retirement: bool = false
	var saw_after: bool = false
	var saw_reward: bool = false
	var deadline: int = Time.get_ticks_msec() + 8000
	while not scene.story_player.world_ready and Time.get_ticks_msec() < deadline:
		var story: Control = scene.story_player
		if story.dialogue.visible:
			if story.current_text_index == sample["first"]:
				saw_first = true
			if story.current_text_index == sample["death"]:
				saw_before = true
				var body: Dictionary = _shown(scene, sample["boss"])
				if not _expect(
					(
						saw_first
						and body.get("hp") == 0
						and not battle.unit(sample["boss"])["visible"]
						and not saw_retirement
						and not saw_reward
						and battle.snapshot() == committed
					),
					"Death dialogue retains the HP0 display body without changing committed battle"
				):
					return false
				if not _expect(
					scene.map.view.center.is_equal_approx(Vector2(10.5, 10.5 + sample["distance"])),
					"The before dialogue focuses the actual boss location"
				):
					return false
			if two_stages and story.dialogue.full_text == "退场后示例":
				saw_after = true
				if not _expect(
					(
						saw_retirement
						and scene.retirement_player.model.tick >= 7
						and _shown(scene, sample["boss"]).is_empty()
						and not saw_reward
						and scene.map.view.center.is_equal_approx(Vector2(13.5, 12.5))
					),
					"After-retirement dialogue follows the seven-update gate and focuses its own speaker"
				):
					return false
			story.advance()
		if scene.retirement_player.playing:
			saw_retirement = true
			if not _expect(
				saw_before and _shown(scene, sample["boss"]).is_empty() and not saw_reward,
				"Map retirement hides the boss after the before dialogue and ahead of rewards"
			):
				return false
		if scene.action_feedback.playing:
			saw_reward = true
			if not _expect(
				saw_retirement and (not two_stages or saw_after),
				"Broken items, loot and XP are shown only after death presentation"
			):
				return false
			if scene.action_feedback.current_step.get("kind") == "tutorial":
				scene.action_feedback.go_back()
		if story.choices.visible and not story.world_active:
			story.choices.get_child(0).pressed.emit()
		await process_frame
	if not _expect(
		(
			scene.story_player.world_ready
			and saw_first
			and saw_before
			and saw_retirement
			and saw_reward
			and (not two_stages or saw_after)
		),
		"Actual Main death, rewards and normal victory must finish at the resident world"
	):
		return false
	var saved: Dictionary = scene.battle_store.read()
	return _expect(
		saved["ok"] and saved["progress"] == scene.world_progress,
		"The completed real death flow preserves its normal world record"
	)


func _shown(scene: Control, id: int) -> Dictionary:
	for unit: Dictionary in scene.map.visible_units():
		if unit["id"] == id:
			return unit
	return {}


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		fail(message)
	return condition


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
