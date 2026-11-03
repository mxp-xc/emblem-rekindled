extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M2 = preload("res://tests/test_m2_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Independent source: temp/m9/p9-oracle.json and original-route-*/observations.json.
const CONTEXTS: Array[Dictionary] = [
	{
		"route": 4,
		"step": 8,
		"party": [0, 9, 2, 4, 5, 1, 6, 7],
		"classes": [0, 4, 8, 8, 16, 4, 20, 12],
		"next": 13
	},
	{
		"route": 5,
		"step": 5,
		"party": [0, 9, 2, 8, 3, 7],
		"classes": [0, 4, 8, 12, 16, 12],
		"next": 1
	},
	{
		"route": 6,
		"step": 5,
		"party": [0, 9, 5, 1, 6, 7],
		"classes": [0, 4, 16, 4, 20, 12],
		"next": 3
	},
	{
		"route": 7,
		"step": 8,
		"party": [0, 9, 5, 4, 2, 8, 3, 7],
		"classes": [0, 4, 16, 8, 8, 12, 16, 12],
		"next": 13
	}
]
# Source order: index, deploymentSlot, position, template class, declared level.
const SLOTS: Array = [
	[18, 5, [19, 11], 16, 10],
	[19, 0, [19, 9], 0, 1],
	[20, 3, [0, 8], 16, 1],
	[21, 1, [0, 9], 4, 1],
	[22, 4, [0, 11], 8, 1],
	[23, 6, [0, 12], 20, 1],
	[24, 2, [19, 8], 8, 1],
	[25, 7, [19, 12], 12, 1]
]
# Source, class, faction, x, y, random-equipment, flags, level, policy.
const RECORDS: Array = [
	[107, 32, 2, 2, 17, false, 1, 1, 0],
	[114, 32, 2, 9, 8, false, 1, 1, 0],
	[108, 36, 2, 6, 11, true, 1, 1, 0],
	[110, 36, 2, 17, 17, true, 1, 1, 0],
	[109, 36, 2, 12, 11, true, 1, 1, 0],
	[112, 36, 2, 17, 1, true, 1, 1, 0],
	[111, 32, 2, 9, 4, false, 1, 1, 0],
	[113, 32, 2, 3, 3, false, 1, 1, 0],
	[34, 28, 2, 11, 19, false, 0, 1, 2],
	[33, 28, 2, 12, 17, false, 0, 1, 2],
	[63, 28, 2, 7, 0, false, 0, 1, 2],
	[62, 28, 2, 6, 16, false, 0, 1, 2],
	[61, 28, 2, 12, 3, false, 0, 1, 2],
	[60, 28, 2, 12, 0, false, 0, 1, 2],
	[59, 28, 2, 7, 2, false, 0, 1, 2],
	[58, 28, 2, 6, 19, false, 0, 1, 2],
	[31, 5, 2, 9, 18, false, 0, 1, 4],
	[32, 5, 2, 9, 1, false, 0, 1, 4],
	[5, 16, 0, 19, 11, false, 0, 10, 32],
	[0, 0, 0, 19, 9, false, 0, 1, 32],
	[3, 16, 0, 0, 8, false, 0, 1, 32],
	[1, 4, 0, 0, 9, false, 0, 1, 32],
	[4, 8, 0, 0, 11, false, 0, 1, 32],
	[6, 20, 0, 0, 12, false, 0, 1, 32],
	[2, 8, 0, 19, 8, true, 0, 1, 32],
	[7, 12, 0, 19, 12, false, 0, 1, 32],
	[16, 5, 1, 1, 8, false, 0, 1, 0],
	[15, 5, 1, 1, 12, false, 0, 1, 0],
	[11, 12, 1, 1, 9, false, 0, 1, 0],
	[12, 12, 1, 1, 11, false, 0, 1, 0],
	[10, 12, 1, 18, 9, false, 0, 1, 0],
	[14, 12, 1, 18, 11, false, 0, 1, 0],
	[18, 5, 1, 18, 12, false, 0, 1, 0],
	[17, 5, 1, 18, 8, false, 0, 1, 0]
]
var _draws: Array[int] = []
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(CONTEXTS.slice(0, 2), true)


func _run_contexts(contexts: Array, check_random: bool) -> void:
	_owned = "user://m9_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim fresh owned m9 content directory")
		return
	for context: Dictionary in contexts:
		if not _context(context) or not _inheritance(context):
			_cleanup()
			return
	if check_random and not _random_equipment():
		_cleanup()
		return
	_cleanup()
	print(
		"PASS m9 content contexts: ",
		contexts.map(func(context: Dictionary) -> int: return context["route"])
	)
	quit(0)


# Routes5/6 use a real m2 settlement; M2's prepared earlier world remains an
# explicit fixture. Routes4/7 include unavailable m12/m10, so use snapshots.
# Neither path claims naturally completing all preceding battles.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	if context["route"] in [5, 6]:
		var prior: Dictionary = M2.prepare(M2.CONTEXTS[3 if context["route"] == 5 else 4], roll)
		if not prior["ok"]:
			return prior
		var opened: Dictionary = Session.new().open(
			CHAPTER, "m2", {"progress": prior["progress"]}, roll
		)
		if not opened["ok"]:
			return opened
		var won: Dictionary = opened["battle"].win_with_assistance()
		if not won["ok"]:
			return won
		var completed: Dictionary = opened["battle"].complete_victory(context["route"])
		if not completed["ok"]:
			return completed
		return {
			"ok": true,
			"kind": "reachable_world",
			"source": {"progress": completed["progress"]},
			"progress": completed["progress"]
		}
	var party: Array = []
	for index: int in range(context["party"].size()):
		party.append({"id": context["party"][index], "classId": context["classes"][index]})
	var native: Array = context["party"].duplicate()
	native[0] = 9
	native[1] = 0
	var compiled: Dictionary = Content.new().load_chapter(
		CHAPTER,
		"m9",
		{
			"party": party,
			"partyOrder": native,
			"route": context["route"],
			"worldStep": context["step"]
		}
	)
	if not compiled["ok"]:
		return compiled
	var neutral: Callable = func(_limit: int) -> int: return 0
	var template: RefCounted = Battle.new(compiled, neutral)
	party.clear()
	for identity: int in context["party"]:
		var member: Dictionary = template.unit(identity)
		member["flags"] = 0
		member["visible"] = true
		member["action"] = 0
		party.append(member)
	compiled["inheritedParty"] = party
	var draws: Array[int] = []
	var recorded: Callable = func(limit: int) -> int:
		draws.append(limit)
		return int(roll.call(limit))
	var battle: RefCounted = Battle.new(compiled, recorded)
	var state: Dictionary = battle.snapshot()
	state["campaign"] = {"route": context["route"], "worldStep": context["step"]}
	state["gold"] = 7000
	state["warehouse"] = [{"id": "m9 inherited warehouse", "templateId": 60, "durability": 2}]
	return {
		"ok": true,
		"kind": "domain_fixture",
		"source": {"snapshot": state},
		"initializationDraws": draws
	}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare actual m9 context: " + str(prepared.get("error"))):
		return false
	var source: Dictionary = JSON.parse_string(JSON.stringify(prepared["source"]))
	var before: Dictionary = source.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m9", source, _roll)
	if not _expect(opened["ok"], "Open actual m9: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	if not _expect(source == before, "Session leaves m9 source unchanged"):
		return false
	if (
		source.has("snapshot")
		and not _expect(_draws.is_empty(), "Snapshot initialization consumes no RNG")
	):
		return false
	if not _deployment(context, content, battle) or not _items(battle):
		return false
	var reordered: Dictionary = source.duplicate(true)
	if source.has("progress"):
		reordered["progress"]["party"].reverse()
	else:
		reordered["snapshot"]["units"].reverse()
	var again: Dictionary = Session.new().open(CHAPTER, "m9", reordered, _roll)
	if not _expect(
		again["ok"] and again["battle"].snapshot() == battle.snapshot(),
		"Stored array order cannot change slots, native order or initialized results"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	if not _expect(store.write(battle)["ok"], "Write m9 only in owned record directory"):
		return false
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	record["state"]["units"].reverse()
	var saved: Dictionary = record.duplicate(true)
	_draws.clear()
	var restored: Dictionary = store.decode(record, _roll)
	if not _expect(
		(
			restored["ok"]
			and _draws.is_empty()
			and record == saved
			and restored["battle"].snapshot() == battle.snapshot()
			and store.read()["ok"]
		),
		"Cold actual JSON preserves units/items/slots/clone templates without replaying initialization"
	):
		return false
	print(
		"PASS m9 content dr%d step%d (%s)" % [context["route"], context["step"], prepared["kind"]]
	)
	return true


func _deployment(context: Dictionary, content: Dictionary, battle: RefCounted) -> bool:
	if not _expect(
		(
			content["map"]["width"] == 20
			and content["map"]["height"] == 20
			and content["spawns"].size() == 34
			and battle.snapshot()["units"].size() == 34
			and content["slots"].size() == 8
			and battle.commander_id == 9
		),
		"m9 is20x20/34 records/eight slots/default commander9"
	):
		return false
	var native: Array = context["party"].duplicate()
	native[0] = 9
	native[1] = 0
	for index: int in range(native.size()):
		if not _expect(
			content["unitOrder"][index] == native[index],
			"Existing formal vector starts9,0 then recruit order"
		):
			return false
	var temporary: int = 95
	for row: Array in SLOTS:
		var slot: int = row[1]
		var formal: bool = slot < context["party"].size()
		var identity: int = context["party"][slot] if formal else temporary
		if not formal:
			temporary += 1
		var actor: Dictionary = battle.unit(identity)
		if not _expect(
			(
				content["slots"][slot] == identity
				and actor["formal"] == formal
				and actor["visible"]
				and actor["policy"] == 0
				and actor["deploymentIndex"] == row[0]
				and Vector2i(actor["x"], actor["y"]) == _cell(row[2])
				and actor["classId"] == (context["classes"][slot] if formal else row[3])
			),
			"Eight visible slots bind inherited/current classes or temporary95/96 in source order"
		):
			return false
	if not _expect(
		int(content["_deployments"][18]["level"]) == 10,
		"Original slot5 declaration remains level10"
	):
		return false
	var occupied: Dictionary = {}
	for actor: Dictionary in battle.snapshot()["units"]:
		var index: int = actor["deploymentIndex"]
		var row: Array = RECORDS[index]
		var cell := Vector2i(actor["x"], actor["y"])
		if not _expect(
			(
				not occupied.has(cell)
				and cell == Vector2i(row[3], row[4])
				and actor["visible"] == (row[6] == 0)
				and ResourceLoader.exists(actor["sprite"])
				and content["interface"]["portraitByUnitId"].has(str(actor["id"]))
			),
			"Every record keeps fixed cell, hidden-template state and complete map/portrait presentation"
		):
			return false
		occupied[cell] = true
		if (
			actor["faction"] != 0
			and not _expect(
				(
					actor["sourceId"] == row[0]
					and actor["classId"] == row[1]
					and actor["faction"] == row[2]
					and actor["policy"] == row[8]
				),
				"Original friend/enemy identity, class and policy survive binding"
			)
		):
			return false
	return true


func _inheritance(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare slot5 inheritance boundary"):
		return false
	var source: Dictionary = prepared["source"].duplicate(true)
	var state: Dictionary = source["progress"] if source.has("progress") else source["snapshot"]
	var identity: int = context["party"][5]
	var saved: Dictionary = {}
	var actors: Array = state["party"] if source.has("progress") else state["units"]
	for actor: Dictionary in actors:
		if actor["id"] == identity:
			actor["level"] = 5
			actor["experience"] = 37
			actor["attributes"]["strength"] += 3
			actor["inventory"][0]["durability"] = 1
			saved = actor.duplicate(true)
	state["warehouse"] = [{"id": "m9 opaque warehouse", "templateId": 60, "durability": 2}]
	var before: Dictionary = source.duplicate(true)
	var opened: Dictionary = Session.new().open(CHAPTER, "m9", source, _roll)
	if not _expect(
		opened["ok"], "Open modified valid inherited member: " + str(opened.get("error"))
	):
		return false
	var actual: Dictionary = opened["battle"].unit(identity)
	return _expect(
		(
			not saved.is_empty()
			and source == before
			and actual["level"] == 5
			and actual["experience"] == 37
			and actual["attributes"] == saved["attributes"]
			and actual["inventory"] == saved["inventory"]
			and opened["battle"].snapshot()["warehouse"] == state["warehouse"]
		),
		"Slot5 level10 preserves inherited level/training and held item identity/durability"
	)


func _random_equipment() -> bool:
	for last: bool in [false, true]:
		var roll: Callable = func(limit: int) -> int: return limit - 1 if last else 0
		var prepared: Dictionary = prepare(CONTEXTS[0], roll)
		if not _expect(prepared["ok"], "Prepare independent equipment boundary"):
			return false
		var expected: Array[int] = []
		var equipment_count: int = 0
		for row: Array in RECORDS:
			if row[5]:
				expected.append(3)
				equipment_count += 1
			if row[2] != 0:
				expected.append_array([4, 3, 3, 3, 3, 6, 3, 1])
		if not _expect(
			(
				equipment_count == 5
				and expected.size() == 213
				and prepared["initializationDraws"] == expected
			),
			"Exactly5 equipment draws precede source-record growth; no fixed position consumes RNG"
		):
			return false
	return true


func _items(battle: RefCounted) -> bool:
	for identity: int in [31, 32]:
		var actor: Dictionary = battle.unit(identity)
		var held: Array = []
		for item: Dictionary in actor["inventory"]:
			held.append([int(item["templateId"]), int(item["durability"])])
		if not _expect(
			(
				actor["classId"] == 5
				and actor["policy"] == 4
				and held == [[48, 12], [59, 10], [65, 4]]
				and actor["equippedInstanceId"] == actor["inventory"][0]["id"]
				and actor["dropTemplateId"] == (65 if identity == 31 else 0)
			),
			"Both summoners equip48 and retain59 plus65; only31 drops65"
		):
			return false
	return true


func _roll(limit: int) -> int:
	_draws.append(limit)
	return 0


func _cell(point: Array) -> Vector2i:
	return Vector2i(int(point[0]), int(point[1]))


func _cleanup() -> void:
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
