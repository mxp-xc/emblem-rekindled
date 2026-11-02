extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
const REWARD: int = 137

var _directory: String = ""
var _files: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var fixture: Dictionary = _make_fixture()
	if not _expect(fixture["ok"], "Configuration fixture must be prepared: " + str(fixture)):
		return
	var chapter_path: String = fixture["chapterPath"]
	var first: Dictionary = Session.new().open(chapter_path, "", {"new": true}, _roll)
	if not _expect(first["ok"], "The fixture must retain the real first-battle entry"):
		return
	var first_battle: RefCounted = first["battle"]
	if not _expect(first_battle.win_with_assistance()["ok"], "First battle must settle normally"):
		return
	var first_world: Dictionary = first_battle.complete_victory(0)
	if not _expect(first_world["ok"], "First battle must produce route-zero world progress"):
		return
	var second: Dictionary = Session.new().open(
		chapter_path, "m1", {"progress": first_world["progress"]}, _roll
	)
	if not _expect(second["ok"], "The real second battle must inherit the first world record"):
		return
	var second_battle: RefCounted = second["battle"]
	if not _expect(second_battle.win_with_assistance()["ok"], "Second battle must settle normally"):
		return
	var second_world: Dictionary = second_battle.complete_victory(0)
	if not _expect(second_world["ok"], "The real prefix must reach route-zero world step two"):
		return
	var progress: Dictionary = second_world["progress"]
	var original_progress: Dictionary = progress.duplicate(true)
	var opened: Dictionary = Session.new().open(chapter_path, "m2", {"progress": progress}, _roll)
	if not _expect(
		opened["ok"] and progress == original_progress,
		(
			"A new configuration alone must open without mutating inherited world progress: "
			+ str(opened.get("error", ""))
		)
	):
		return
	var battle: RefCounted = opened["battle"]
	var content: Dictionary = opened["content"]
	if not _expect(
		(
			content["entry"]["battleId"] == "m2"
			and content["story"]["battleName"]["text"] == "配置验收地图"
			and content["story"]["battleNumber"] == 3
			and content["unitOrder"].slice(0, 3) == [9, 0, 6]
			and _formal_ids(battle.snapshot()["units"]) == [0, 6, 7, 9]
			and battle.unit(7)["sourceId"] == 6
			and battle.unit(6)["sourceId"] == 6
		),
		"Configured entry must bind the actual roster and a distinct identity sharing an existing profile"
	):
		return
	var choices: Array = content["story"]["routeChoices"]
	if not _expect(
		choices.size() == 1 and choices[0]["routeIndex"] == 0 and choices[0]["nodeId"] == 3,
		"The configured battle must keep the current route and resolve its actual next node"
	):
		return
	for id: int in [0, 9, 6]:
		if not _expect(
			not battle.unit(id)["visible"], "The configured party starts hidden until its event"
		):
			return
	var advanced: Dictionary = _next_round(battle)
	if not _expect(advanced["ok"], "Configured turn event must run through real phase commands"):
		return
	var events: Array = advanced["events"]
	if not _expect(
		(
			events.size() == 1
			and events[0]["sequence"] == "configured_arrival"
			and events[0]["arrivals"].size() == 6
			and battle.event_completed("configured_arrival")
		),
		"The configuration must reveal its six bound slots and complete its once-only event"
	):
		return
	for id: int in [0, 9, 6]:
		if not _expect(
			battle.unit(id)["visible"], "The configured event must change real unit visibility"
		):
			return
	var saved_state: Dictionary = battle.snapshot()
	var save_path: String = _directory.path_join("continue.json")
	var store := Store.new(first["content"], save_path)
	if not _expect(
		store.write(battle, 23)["ok"],
		"The configured battle must write an isolated continue record"
	):
		return
	var cold_anchor: Dictionary = Content.new().load_chapter(chapter_path)
	if not _expect(
		cold_anchor["ok"], "Cold opening must reread the fixture's chapter registration"
	):
		return
	var cold_store := Store.new(cold_anchor, save_path)
	var continued: Dictionary = cold_store.read()
	if not _expect(
		(
			continued["ok"]
			and continued["content"]["entry"]["battleId"] == "m2"
			and continued["elapsedMinutes"] == 23
			and continued["battle"].snapshot() == saved_state
		),
		(
			"A fresh Store and Session must restore the configured battle and its event state exactly: "
			+ str(continued.get("error", ""))
		)
	):
		return
	var restored: RefCounted = continued["battle"]
	var later: Dictionary = _next_round(restored)
	if not _expect(
		(
			later["ok"]
			and later["events"].is_empty()
			and restored.event_completed("configured_arrival")
		),
		"The once-only configured event must remain completed after cold restoration"
	):
		return
	if not _expect(
		(
			restored.round_number == 3
			and restored.outcome.get("kind") == "victory"
			and restored.outcome.get("reason") == "survived"
		),
		"Entering the configured third round must trigger victory before another player command"
	):
		return
	var completed: Dictionary = restored.complete_victory(0)
	if not _expect(completed["ok"], "The configured battle must complete through Campaign rules"):
		return
	var world: Dictionary = completed["progress"]
	if not _expect(
		(
			world["completedBattle"] == "m2"
			and world["worldNode"] == 2
			and world["worldStep"] == 3
			and world["route"] == 0
			and _formal_ids(world["party"]) == [0, 6, 7, 9]
			and world["gold"] == progress["gold"] + REWARD
		),
		"Configured completion must retain route zero, four members and its configured reward"
	):
		return
	var repeated: Dictionary = restored.complete_victory(0)
	if not _expect(
		repeated["ok"] and repeated["alreadyComplete"] and repeated["progress"] == world,
		"Repeated completion must not grant the configuration's reward again"
	):
		return
	var before_write: Dictionary = world.duplicate(true)
	if not _expect(
		(
			cold_store.write_progress(world)["ok"]
			and cold_store.write_slot(2, world)["ok"]
			and world == before_write
		),
		"Configured world progress must write to isolated continue and named records without mutation"
	):
		return
	var world_store := Store.new(Content.new().load_chapter(chapter_path), save_path)
	for loaded: Dictionary in [world_store.read(), world_store.read_slot(2)]:
		if not _expect(
			(
				loaded["ok"]
				and loaded.has("progress")
				and not loaded.has("battle")
				and loaded["progress"]["completedBattle"] == "m2"
				and loaded["progress"]["worldNode"] == 2
				and loaded["progress"]["worldStep"] == 3
				and loaded["progress"]["route"] == 0
				and loaded["progress"]["gold"] == world["gold"]
				and _formal_ids(loaded["progress"]["party"]) == [0, 6, 7, 9]
			),
			"Cold world records must identify the configured completed map and its full party"
		):
			return
	if not _cleanup():
		quit(1)
		return
	print(
		"PASS configured battle: data-only entry, real event, cold continue, settlement and world slots"
	)
	quit(0)


func _make_fixture() -> Dictionary:
	var chapter: Variant = _json(CHAPTER)
	if not chapter is Dictionary or not chapter.get("battles") is Dictionary:
		return {"ok": false, "error": "Missing chapter registration"}
	var definition: Variant = _json(chapter["battles"].get("m1", ""))
	if not definition is Dictionary or not definition.get("profiles") is Dictionary:
		return {"ok": false, "error": "Missing real m1 definition"}
	var deployments: Variant = _json(definition.get("deployments", ""))
	var story: Variant = _json(definition.get("story", ""))
	if not deployments is Array or not story is Dictionary:
		return {"ok": false, "error": "Missing real m1 deployment or authored content"}
	var recruit: int = -1
	for index: int in range(deployments.size()):
		var record: Dictionary = deployments[index]
		if (
			record.get("sourceId") == 6
			and record.get("faction") == 0
			and not record.has("deploymentSlot")
		):
			if recruit >= 0 or record.get("classId") != 20:
				return {"ok": false, "error": "Unexpected m1 recruit source"}
			recruit = index
	if recruit < 0 or not definition["profiles"].has("source_6_job_20_faction_0"):
		return {"ok": false, "error": "The shared recruit presentation is not available"}
	deployments[recruit]["id"] = 7
	deployments[recruit]["formal"] = true
	definition["battleId"] = "m2"
	story["battleId"] = "m2"
	story["worldNode"] = 2
	story["battleName"] = _line("配置验收地图")
	story["objective"] = _line("配置验收：进入第3轮，0与7必须生还")
	story["outcomeRules"] = {
		"checks":
		[
			{"kind": "victory", "condition": "roundAfter", "round": 2},
			{"kind": "defeat", "condition": "requiredUnitFallen", "unitIds": [0, 7]}
		]
	}
	story["speakers"]["7"] = {"name": "配置成员7", "portraitId": 6}
	story["turnEvents"] = [
		{
			"id": "configured_arrival",
			"afterEnemyPhaseOfRound": 1,
			"deploymentSlots": [0, 1, 2, 3, 4, 5],
			"sequence": "configured_arrival"
		}
	]
	story["aiChanges"] = []
	story["combatEvents"] = []
	story["sequences"] = {
		"opening":
		[
			{"kind": "battleTitle", "text": _line("配置验收地图"), "sourceDurationUnits": 50},
			{"kind": "focus", "unitId": 7},
			{"kind": "dialogue", "text": {"sourceTextIndex": 490, "speakerId": 7}},
			{"kind": "objective", "text": story["objective"]},
			{"kind": "commanderSetup", "candidates": [7, 0], "defaultCommanderId": 7}
		],
		"configured_arrival":
		[
			{
				"kind": "parallelEntrances",
				"focus": [1, 15],
				"deploymentSlots": [0, 1, 2],
				"offset": [-3, 0]
			},
			{"kind": "dialogue", "text": {"sourceTextIndex": 493, "speakerId": 7}}
		],
		"victory":
		[
			{
				"kind": "routeChoice",
				"options": story["routeChoices"].duplicate(true),
				"whenWorldStep": 1
			},
			{"kind": "missionComplete", "text": _line("配置任务完成"), "goldReward": REWARD}
		]
	}
	var candidate: String = (
		"user://configured_battle_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	if DirAccess.dir_exists_absolute(candidate) or FileAccess.file_exists(candidate):
		return {"ok": false, "error": "Refuse to reuse an existing fixture directory"}
	var created: Error = DirAccess.make_dir_absolute(candidate)
	if created != OK:
		return {"ok": false, "error": "Cannot create fixture directory: " + error_string(created)}
	_directory = candidate
	for filename: String in [
		"chapter.json",
		"battle.json",
		"deployments.json",
		"story.json",
		"continue.json",
		"continue.json.tmp",
		"continue_slot_3.json",
		"continue_slot_3.json.tmp"
	]:
		_files.append(_directory.path_join(filename))
	var chapter_path: String = _directory.path_join("chapter.json")
	var battle_path: String = _directory.path_join("battle.json")
	var deployments_path: String = _directory.path_join("deployments.json")
	var story_path: String = _directory.path_join("story.json")
	chapter["battles"]["m2"] = battle_path
	definition["deployments"] = deployments_path
	definition["story"] = story_path
	for document: Array in [
		[chapter_path, chapter],
		[battle_path, definition],
		[deployments_path, deployments],
		[story_path, story]
	]:
		var file := FileAccess.open(document[0], FileAccess.WRITE)
		if file == null:
			return {"ok": false, "error": "Cannot write fixture: " + str(document[0])}
		file.store_string(JSON.stringify(document[1]))
		file.flush()
		var written: Error = file.get_error()
		file.close()
		if written != OK:
			return {"ok": false, "error": "Fixture write failed: " + error_string(written)}
	return {"ok": true, "chapterPath": chapter_path}


func _next_round(battle: RefCounted) -> Dictionary:
	var initial_round: int = battle.round_number
	var events: Array = []
	var unit_count: int = battle.snapshot()["units"].size()
	for phase_guard: int in range(4):
		if battle.phase != 0:
			for actor_guard: int in range(unit_count + 1):
				var actor: int = battle.automatic_actor()
				if actor < 0:
					break
				var waited: Dictionary = battle.wait_unit(actor)
				if not waited["ok"]:
					return waited
			if battle.automatic_actor() >= 0:
				return {"ok": false, "error": "Automatic phase did not finish"}
		var advanced: Dictionary = battle.end_phase()
		if not advanced["ok"]:
			return advanced
		events.append_array(advanced["events"])
		if battle.phase == 0 and battle.round_number > initial_round:
			return {"ok": true, "events": events}
	return {"ok": false, "error": "The round did not advance"}


func _formal_ids(units: Array) -> Array[int]:
	var result: Array[int] = []
	for unit: Dictionary in units:
		if unit.get("formal", false):
			result.append(int(unit["id"]))
	result.sort()
	return result


func _line(text: String) -> Dictionary:
	return {"sourceTextIndex": -1, "text": text, "speakerId": null}


func _json(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cleanup() -> bool:
	var success: bool = true
	for path: String in _files:
		if FileAccess.file_exists(path):
			var removed: Error = DirAccess.remove_absolute(path)
			if removed != OK:
				push_error(
					"Cannot remove owned fixture file: %s (%s)" % [path, error_string(removed)]
				)
				success = false
	if not _directory.is_empty():
		var removed: Error = DirAccess.remove_absolute(_directory)
		if removed != OK:
			push_error(
				(
					"Cannot remove owned fixture directory: %s (%s)"
					% [_directory, error_string(removed)]
				)
			)
			success = false
	return success


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		_cleanup()
		quit(1)
	return condition


func _roll(_limit: int) -> int:
	return 0
