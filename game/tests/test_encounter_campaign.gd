extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	var session := Session.new()
	var first: Dictionary = session.open(CHAPTER, "", {"new": true}, _roll)
	first["battle"].win_with_assistance()
	var progress: Dictionary = first["battle"].complete_victory(0)["progress"]
	var second: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _roll)
	if not second["ok"]:
		_fail("The mainline fixture must open")
		return
	var content: Dictionary = second["content"].duplicate(true)
	content["story"]["encounter"] = true
	content["story"]["commanderMode"] = "none"
	content["story"]["worldNode"] = 10
	content["story"]["routeChoices"] = []
	content["entry"]["initialParty"] = [0, 9]
	content["entry"]["recruitByNode"] = {}
	for group: String in ["units", "spawns"]:
		for actor: Dictionary in content[group]:
			if actor["id"] == 6:
				actor["formal"] = false
	progress["worldNode"] = 10
	progress["worldStep"] = 6
	progress["worldLocation"] = 0
	progress["completedBattle"] = "m10"
	progress["commander"] = 0
	for actor: Dictionary in progress["party"]:
		actor["x"] = 2
		actor["y"] = 3
	content["inheritedParty"] = progress["party"].duplicate(true)
	var encounter := Battle.new(content, _roll)
	if not encounter.begin_from_progress(progress)["ok"]:
		_fail("Encounter must inherit a visited world and its party")
		return
	var state: Dictionary = encounter.snapshot()
	var restored := Battle.new(content, _roll, false)
	if not restored.restore_snapshot(state)["ok"] or restored.snapshot() != state:
		_fail("Encounter snapshot must preserve route, location and prior map positions")
		return
	var invalid: Dictionary = state.duplicate(true)
	invalid["campaign"]["encounterPositions"].pop_back()
	if Battle.new(content, _roll, false).restore_snapshot(invalid)["ok"]:
		_fail("A snapshot missing a party member's previous position must be rejected")
		return
	if not restored.win_with_assistance()["ok"]:
		_fail("Encounter fixture must be winnable")
		return
	var result: Dictionary = restored.complete_victory(0)
	if not result["ok"]:
		_fail("Encounter victory must settle")
		return
	var world: Dictionary = result["progress"]
	if (
		world["worldStep"] != 6
		or world["worldNode"] != 10
		or world["worldLocation"] != 0
		or world["completedBattle"] != "m10"
		or world["gold"] != progress["gold"] + 1000
		or world["commander"] != 0
	):
		_fail("Encounter settlement must preserve mainline state and award the encounter gold")
		return
	for actor: Dictionary in world["party"]:
		if actor["x"] != 2 or actor["y"] != 3:
			_fail("Returning to the previous map must restore its original party positions")
			return
	content["story"]["worldNode"] = 15
	progress["worldNode"] = 15
	progress["worldStep"] = 10
	progress["completedBattle"] = "m15"
	progress["chapterCompleted"] = true
	var rows: Array = []
	for id: int in [0, 9]:
		for actor: Dictionary in progress["party"]:
			if actor["id"] == id:
				rows.append({"id": id, "level": actor["level"], "power": 0})
	progress["chapterResult"] = {
		"party": rows,
		"gold": progress["gold"],
		"totalPower": 0,
		"chapterStats": progress["chapterStats"].duplicate(true)
	}
	var postgame := Battle.new(content, _roll)
	if not postgame.begin_from_progress(progress)["ok"]:
		_fail("Encounter must accept a completed chapter and its result")
		return
	var postgame_state: Dictionary = postgame.snapshot()
	postgame_state["chapterStats"]["rounds"] += 1
	var forged: Dictionary = postgame_state.duplicate(true)
	forged["campaign"]["chapterResult"]["totalPower"] = 1
	if Battle.new(content, _roll, false).restore_snapshot(forged)["ok"]:
		_fail("A restored encounter must reject a malformed historical chapter result")
		return
	var postgame_restored := Battle.new(content, _roll, false)
	if not postgame_restored.restore_snapshot(postgame_state)["ok"]:
		_fail("A postgame encounter snapshot must keep the historical chapter result")
		return
	postgame_restored.win_with_assistance()
	var finished: Dictionary = postgame_restored.complete_victory(0)
	if (
		not finished["ok"]
		or not finished["progress"].get("chapterCompleted", false)
		or not finished["progress"].get("chapterResultHistorical", false)
		or finished["progress"]["chapterResult"] != progress["chapterResult"]
		or finished["progress"]["chapterStats"] != postgame_state["chapterStats"]
	):
		_fail("Postgame victory must retain the completion result separately from later statistics")
		return
	print("PASS encounter campaign: entry, snapshot, settlement and world return")
	quit(0)


func _roll(_limit: int) -> int:
	return 0


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
