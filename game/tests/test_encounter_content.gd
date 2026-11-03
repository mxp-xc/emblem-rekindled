extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const Deployment = preload("res://app/chapter_deployment.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	var entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHAPTER))
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry["library"]))
	var classes: Dictionary = {}
	for profile: Dictionary in bank["profiles"].values():
		var unit: Dictionary = profile["unit"]
		if unit["formal"] and unit["faction"] == 0 and int(unit["classId"]) % 4 == 0:
			classes[int(unit["sourceId"])] = int(unit["classId"])
	for battle_id: String in ["m17", "m18", "m19"]:
		for step: int in [6, 10]:
			if not _check(entry, bank, classes, battle_id, step):
				return
	print("PASS encounter content: three maps, early and completed world, save and victory")
	quit(0)


func _check(
	entry: Dictionary, bank: Dictionary, classes: Dictionary, battle_id: String, step: int
) -> bool:
	var route: Array = bank["storyCommon"]["world"]["routes"][0]
	var ids: Array[int] = Deployment.recruit_order(
		route, entry["recruitByNode"], step, entry["initialParty"]
	)
	var party: Array = []
	for id: int in ids:
		party.append({"id": id, "sourceId": id, "classId": classes[id]})
	var native_order: Array = [9, 0]
	for id: int in ids:
		if id not in native_order:
			native_order.append(id)
	var loaded: Dictionary = Content.new().load_chapter(
		CHAPTER,
		battle_id,
		{"party": party, "partyOrder": native_order, "route": 0, "worldStep": step}
	)
	if not loaded.get("ok", false):
		return _fail("Cannot load %s at step %d: %s" % [battle_id, step, loaded])
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
	var progress: Dictionary = {
		"chapterId": entry["id"],
		"completedBattle": "m%d" % int(route[step - 1]),
		"worldNode": route[step - 1],
		"worldStep": step,
		"worldLocation": 0,
		"route": 0,
		"party": members,
		"warehouse": [],
		"gold": 7000,
		"commander": 0,
		"commandPolicy": 0,
		"chapterStats": {"rounds": 1, "playerRetirements": 0, "allyRetirements": 0}
	}
	if step == route.size():
		var ordered: Array = members.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
		var rows: Array = []
		for actor: Dictionary in ordered:
			rows.append({"id": actor["id"], "level": actor["level"], "power": 0})
		progress["chapterCompleted"] = true
		progress["chapterResult"] = {
			"party": rows,
			"gold": 7000,
			"totalPower": 0,
			"chapterStats": progress["chapterStats"].duplicate(true)
		}
	var session := Session.new()
	var opened: Dictionary = session.open(CHAPTER, battle_id, {"encounter": progress}, _roll)
	if not opened.get("ok", false):
		return _fail("Cannot enter %s at step %d: %s" % [battle_id, step, opened])
	if battle_id == "m19":
		var advanced: Dictionary = {
			"attributes":
			{"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
			"maxHp": 0,
			"maxProficiency": 0,
			"maxInternalLevel": 9,
			"averageInternalLevel": 9
		}
		var scaled: Dictionary = session.open(
			CHAPTER, battle_id, {"encounter": progress}, _roll, advanced
		)
		if (
			not scaled.get("ok", false)
			or scaled["battle"].unit(32)["classId"] != 29
			or scaled["battle"].unit(33)["classId"] != 29
		):
			return _fail("High-level bonus enemies must load their original advanced class")
	var snapshot: Dictionary = opened["battle"].snapshot()
	var restored: Dictionary = session.open(CHAPTER, battle_id, {"snapshot": snapshot}, _roll)
	if not restored.get("ok", false) or restored["battle"].snapshot() != snapshot:
		return _fail("Cannot restore %s at step %d" % [battle_id, step])
	var battle: RefCounted = restored["battle"]
	battle.win_with_assistance()
	var victory: Dictionary = battle.complete_victory(0)
	if not victory.get("ok", false):
		return _fail("Cannot settle %s at step %d: %s" % [battle_id, step, victory])
	var world: Dictionary = victory["progress"]
	if world["worldStep"] != step or world["worldLocation"] != 0 or world["gold"] != 8000:
		return _fail("Encounter settlement changed the route or reward")
	var store := Store.new(opened["content"])
	var encoded: Dictionary = store.encode_progress(world)
	if not encoded.get("ok", false) or not store.decode(encoded["record"]).get("ok", false):
		return _fail("Cannot save the world after %s at step %d: %s" % [battle_id, step, encoded])
	return true


func _roll(_limit: int) -> int:
	return 0


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
