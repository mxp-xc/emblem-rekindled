extends SceneTree

const Session = preload("res://app/chapter_session.gd")


func _initialize() -> void:
	var session := Session.new()
	for source: Dictionary in [{}, {"new": true, "progress": {}}, {"new": false}]:
		if session.open("user://unavailable_chapter.json", "", source)["ok"]:
			fail("A source must name exactly one valid opening intent")
			return
	var chapter: Dictionary = {
		"id": "test_chapter",
		"firstBattle": "m0",
		"initialParty": [0],
		"recruitByNode": {"0": 9, "1": 6, "2": 7}
	}
	var library: Dictionary = {"storyCommon": {"world": {"routes": [[0, 1, 2, 3]]}}}
	var progress: Dictionary = {
		"chapterId": "test_chapter",
		"completedBattle": "m1",
		"worldNode": 1,
		"worldStep": 2,
		"route": 0,
		"party": [{"id": 6, "classId": 8}, {"id": 9, "classId": 4}, {"id": 0, "classId": 0}]
	}
	var records: Array = [
		{"faction": 0, "sourceId": 6}, {"faction": 0, "sourceId": 0, "deploymentSlot": 0}
	]
	chapter = JSON.parse_string(JSON.stringify(chapter))
	library = JSON.parse_string(JSON.stringify(library))
	progress = JSON.parse_string(JSON.stringify(progress))
	records = JSON.parse_string(JSON.stringify(records))
	var before: Dictionary = progress.duplicate(true)
	var entry: Dictionary = session._world_context(
		chapter, library, "m2", records, {}, progress, false
	)
	var completed: Dictionary = session._world_context(
		chapter, library, "m1", records, {}, progress, true
	)
	if (
		not entry["ok"]
		or not completed["ok"]
		or entry["worldStep"] != 2
		or completed["worldStep"] != 1
		or entry["party"].map(func(unit: Dictionary) -> int: return int(unit["id"])) != [0, 9, 6]
		or completed["party"].map(func(unit: Dictionary) -> int: return int(unit["id"])) != [0, 9]
		or completed["classes"] != {0: 8}
		or progress != before
	):
		fail(
			"Completed and next-entry contexts must preserve route, roster order and current classes"
		)
		return
	var first_progress: Dictionary = progress.duplicate(true)
	first_progress["completedBattle"] = "m0"
	first_progress["worldNode"] = 0
	first_progress.erase("worldStep")
	first_progress["party"] = progress["party"].filter(
		func(unit: Dictionary) -> bool: return unit["id"] != 6
	)
	var first_context: Dictionary = session._world_context(
		chapter, library, "m0", records, {}, first_progress, true
	)
	if (
		not first_context["ok"]
		or first_context["worldStep"] != 0
		or not first_context["party"].is_empty()
	):
		fail(
			"Legacy first-world records must resolve the completed first map with no inherited slots"
		)
		return
	for changes: Dictionary in [
		{"route": -1},
		{"route": 1},
		{"worldStep": 0},
		{"worldStep": 4},
		{"worldStep": 1.5},
		{"worldNode": 2},
		{"completedBattle": "m0"},
		{"party": [{"id": 0, "classId": 0}, {"id": 9, "classId": 4}]},
		{"party": [{"id": 0, "classId": 0}, {"id": 9, "classId": 4}, {"id": 9, "classId": 4}]}
	]:
		var invalid: Dictionary = progress.duplicate(true)
		invalid.merge(changes, true)
		var preserved: Dictionary = invalid.duplicate(true)
		if (
			session._world_context(chapter, library, "m2", records, {}, invalid, false)["ok"]
			or invalid != preserved
		):
			fail("Invalid route, frontier or roster must fail without mutating the supplied source")
			return
	print(
		"PASS chapter sources: exclusive intent, route frontier, recruit order and completed context"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
