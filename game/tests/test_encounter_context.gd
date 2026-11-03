extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHAPTER))
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chapter["library"]))
	var route: Array = library["storyCommon"]["world"]["routes"][0]
	var session := Session.new()
	for step: int in [6, route.size()]:
		var party: Array = []
		var ids: Array[int] = load("res://app/chapter_deployment.gd").recruit_order(
			route, chapter["recruitByNode"], step, chapter["initialParty"]
		)
		for id: int in ids:
			party.append({"id": id, "classId": 0})
		var progress: Dictionary = {
			"chapterId": chapter["id"],
			"party": party,
			"route": 0,
			"worldStep": step,
			"worldNode": route[step - 1],
			"worldLocation": route[0],
			"completedBattle": "m%d" % int(route[step - 1]),
			"chapterCompleted": step == route.size()
		}
		var opened: Dictionary = session._world_context(
			chapter, library, "m18", [], {"encounter": true}, progress, false, true
		)
		if not opened["ok"] or opened["worldStep"] != step or opened["party"] != party:
			_fail(
				"Encounter entry must retain the roster and progress before and after chapter end"
			)
			return
		var invalid: Dictionary = progress.duplicate(true)
		invalid["worldLocation"] = 99
		if (
			session
			. _world_context(chapter, library, "m18", [], {"encounter": true}, invalid, false, true)["ok"]
		):
			_fail("An encounter cannot start at an unvisited world node")
			return
	print("PASS encounter world contexts: visited location, route, roster and chapter end")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
