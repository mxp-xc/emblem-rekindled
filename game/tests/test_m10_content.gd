extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M4 = preload("res://tests/test_m4_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Independent source: temp/m10/p10-oracle.json and original-route-*/observations.json.
const CONTEXTS: Array[Dictionary] = [
	{
		"route": 0,
		"step": 5,
		"party": [0, 9, 6, 7, 3, 8],
		"classes": [0, 4, 20, 12, 16, 12],
		"next": 5
	},
	{
		"route": 1,
		"step": 8,
		"party": [0, 9, 6, 1, 5, 4, 2, 8],
		"classes": [0, 4, 20, 4, 16, 8, 8, 12],
		"next": 14
	},
	{
		"route": 6,
		"step": 8,
		"party": [0, 9, 5, 1, 6, 7, 3, 8],
		"classes": [0, 4, 16, 4, 20, 12, 16, 12],
		"next": 14
	},
	{"route": 7, "step": 5, "party": [0, 9, 5, 4, 2, 8], "classes": [0, 4, 16, 8, 8, 12], "next": 3}
]
const SLOTS: Array = [
	[0, 0, [22, 3], 1, 1],
	[5, 4, [20, 4], 8, 1],
	[6, 5, [22, 5], 16, 1],
	[7, 7, [20, 8], 13, 1],
	[8, 3, [21, 4], 16, 1],
	[9, 2, [22, 4], 8, 1],
	[10, 6, [21, 5], 20, 1],
	[20, 1, [21, 3], 5, 1]
]
# Source,class,faction,fixed cell or region list,equipment flag,policy.
const RECORDS: Array = [
	[0, 1, 0, [22, 3], false, 32],
	[11, 13, 1, [17, 6], false, 2],
	[12, 13, 1, [20, 10], false, 2],
	[15, 5, 1, [18, 6], false, 2],
	[17, 5, 1, [21, 10], false, 2],
	[4, 8, 0, [20, 4], true, 32],
	[5, 16, 0, [22, 5], false, 32],
	[7, 13, 0, [20, 8], false, 32],
	[3, 16, 0, [21, 4], true, 32],
	[2, 8, 0, [22, 4], true, 32],
	[6, 20, 0, [21, 5], true, 32],
	[61, 29, 2, [8, 16], false, 2],
	[63, 29, 2, [7, 17], false, 2],
	[66, 33, 2, [8, 6], false, 2],
	[67, 33, 2, [9, 7], false, 2],
	[69, 37, 2, [19, 19], false, 2],
	[34, 37, 2, [18, 18], false, 2],
	[30, 5, 2, [8, 7], false, 0],
	[90, 13, 2, [8, 17], false, 0],
	[36, 5, 2, [18, 19], false, 0],
	[1, 5, 0, [21, 3], false, 32],
	[33, 29, 2, [8, 18], false, 2],
	[39, 12, 2, [[2, 1, 11, 8]], false, 0],
	[38, 12, 2, [[5, 8, 13, 13]], false, 0],
	[37, 12, 2, [[10, 10, 18, 16]], false, 0],
	[36, 12, 2, [[15, 16, 23, 21]], false, 0],
	[35, 12, 2, [[5, 16, 14, 21]], false, 0]
]
var _draws: Array[int] = []
var _owned: String = ""
var _verified_sources: Dictionary = {}


func _initialize() -> void:
	_owned = "user://m10_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim fresh owned m10 content directory")
		return
	for context: Dictionary in CONTEXTS:
		if not _context(context) or not _inheritance(context):
			_cleanup()
			return
	if not _random_equipment():
		_cleanup()
		return
	_cleanup()
	print("PASS m10 content: four contexts/slots/training/source36/random cells/cold JSON")
	quit(0)


# Routes0/7 enter via actual m4 settlement commands. Earlier m4 inputs may be
# explicit fixtures. Route1 includes unavailable m11; route6 is a late snapshot.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	if context["route"] in [0, 7]:
		var prior: Dictionary = M4.prepare(M4.CONTEXTS[0 if context["route"] == 0 else 5], roll)
		if not prior["ok"]:
			return prior
		var opened: Dictionary = Session.new().open(
			CHAPTER, "m4", {"progress": prior["progress"]}, roll
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
		"m10",
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
	state["warehouse"] = [{"id": "m10 inherited warehouse", "templateId": 60, "durability": 2}]
	return {
		"ok": true,
		"kind": "domain_fixture",
		"source": {"snapshot": state},
		"initializationDraws": draws
	}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare actual m10 context: " + str(prepared.get("error"))):
		return false
	var source: Dictionary = JSON.parse_string(JSON.stringify(prepared["source"]))
	var before: Dictionary = source.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m10", source, _roll)
	if not _expect(opened["ok"], "Open actual m10: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	if not _expect(source == before, "Session leaves m10 source unchanged"):
		return false
	if (
		source.has("snapshot")
		and not _expect(_draws.is_empty(), "Snapshot initialization consumes no RNG")
	):
		return false
	if not _deployment(context, content, battle) or not _items(content, battle):
		return false
	var reordered: Dictionary = source.duplicate(true)
	if source.has("progress"):
		reordered["progress"]["party"].reverse()
	else:
		reordered["snapshot"]["units"].reverse()
	var again: Dictionary = Session.new().open(CHAPTER, "m10", reordered, _roll)
	if not _expect(
		again["ok"] and again["battle"].snapshot() == battle.snapshot(),
		"Stored array order cannot change slots, native order or initialized results"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	if not _expect(store.write(battle)["ok"], "Write m10 only in owned record directory"):
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
		"Cold actual JSON preserves units/items/slots/random cells without replaying initialization"
	):
		return false
	# Training varies the same already validated source; do not replay its full
	# m4 prefix just to obtain an identical immutable input a second time.
	_verified_sources[int(context["route"])] = prepared["source"].duplicate(true)
	print(
		"PASS m10 content dr%d step%d (%s)" % [context["route"], context["step"], prepared["kind"]]
	)
	return true


func _deployment(context: Dictionary, content: Dictionary, battle: RefCounted) -> bool:
	if not _expect(
		(
			content["map"]["width"] == 25
			and content["map"]["height"] == 22
			and content["spawns"].size() == 27
			and battle.snapshot()["units"].size() == 27
			and content["slots"].size() == 8
			and battle.commander_id == 9
		),
		"m10 is25x22/27 records/eight slots/default9"
	):
		return false
	var native: Array = context["party"].duplicate()
	native[0] = 9
	native[1] = 0
	for index: int in range(native.size()):
		if not _expect(
			content["unitOrder"][index] == native[index], "Native formal vector starts9,0"
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
			"Visible slots preserve current member class;empty slot7 precedes slot6 as95/96"
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
				and actor["visible"]
				and ResourceLoader.exists(actor["sprite"])
				and content["interface"]["portraitByUnitId"].has(str(actor["id"]))
			),
			"All27 units have unique occupied cells and bound presentation"
		):
			return false
		occupied[cell] = true
		var inside: bool = false
		if index < 22:
			inside = cell == _cell(row[3])
		else:
			for rectangle: Array in row[3]:
				inside = (
					inside
					or (
						cell.x >= rectangle[0]
						and cell.x <= rectangle[2]
						and cell.y >= rectangle[1]
						and cell.y <= rectangle[3]
					)
				)
		if not _expect(inside, "Fixed position or inclusive original rectangle is retained"):
			return false
		if (
			actor["faction"] != 0
			and not _expect(
				(
					actor["sourceId"] == row[0]
					and actor["classId"] == row[1]
					and actor["faction"] == row[2]
					and actor["policy"] == row[5]
				),
				"Source/class/faction/policy remain independent of actualID"
			)
		):
			return false
	return _expect(
		(
			battle.unit(36)["sourceId"] == 36
			and battle.unit(36)["classId"] == 5
			and battle.unit(36)["deploymentIndex"] == 19
			and battle.unit(40)["sourceId"] == 36
			and battle.unit(40)["classId"] == 12
			and battle.unit(40)["deploymentIndex"] == 25
		),
		"Duplicate source36 keeps actual36/index19/class5 and actual40/index25/class12"
	)


func _inheritance(context: Dictionary) -> bool:
	if not _expect(
		_verified_sources.has(int(context["route"])),
		"Training requires its validated context source"
	):
		return false
	var source: Dictionary = _verified_sources[int(context["route"])].duplicate(true)
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
	state["warehouse"] = [{"id": "m10 opaque warehouse", "templateId": 60, "durability": 2}]
	var before: Dictionary = source.duplicate(true)
	var opened: Dictionary = Session.new().open(CHAPTER, "m10", source, _roll)
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
		"Inherited training and opaque items survive promoted slot prototypes"
	)


func _random_equipment() -> bool:
	var prepared: Dictionary = prepare(CONTEXTS[1], _roll)
	if not _expect(prepared["ok"], "Prepare low-choice initialization fixture"):
		return false
	var expected: Array[int] = []
	var occupied: Dictionary = {}
	var position_limits: Array[int] = []
	var equipment: int = 0
	for index: int in range(RECORDS.size()):
		var row: Array = RECORDS[index]
		if row[4]:
			expected.append(3)
			equipment += 1
		var point: Vector2i
		if index < 22:
			point = _cell(row[3])
		else:
			var candidates: Array[Vector2i] = []
			for x: int in range(25):
				for y: int in range(22):
					var rectangle: Array = row[3][0]
					var cell := Vector2i(x, y)
					if (
						not occupied.has(cell)
						and x >= rectangle[0]
						and x <= rectangle[2]
						and y >= rectangle[1]
						and y <= rectangle[3]
					):
						candidates.append(cell)
			expected.append(candidates.size())
			position_limits.append(candidates.size())
			point = candidates[0]
		occupied[point] = true
		if row[2] != 0:
			expected.append_array([4, 3, 3, 3, 3, 6, 3, 1])
	if not _expect(
		(
			equipment == 4
			and expected.size() == 161
			and position_limits.size() == 5
			and prepared["initializationDraws"] == expected
		),
		"Four equipment and five position draws retain source order with ordinary growth calls"
	):
		return false
	var state: Dictionary = prepared["source"]["snapshot"]
	for pair: Array in [[39, [2, 1]], [38, [5, 8]], [37, [10, 10]], [40, [15, 16]], [35, [5, 16]]]:
		for actor: Dictionary in state["units"]:
			if (
				actor["id"] == pair[0]
				and not _expect(
					Vector2i(actor["x"], actor["y"]) == _cell(pair[1]),
					"Modern low choices match audited original minimum cells;no original high-end claim"
				)
			):
				return false
	return true


func _items(content: Dictionary, battle: RefCounted) -> bool:
	var boss: Dictionary = battle.unit(90)
	var held: Array[int] = []
	for item: Dictionary in boss["inventory"]:
		held.append(int(item["templateId"]))
	if not _expect(
		(
			boss["classId"] == 13
			and (
				content["_library"]["profiles"][content["profiles"][90]]["portrait"]["portraitId"]
				== 21
			)
			and boss["dropTemplateId"] == 76
			and held == [51, 59, 67, 76]
			and boss["equippedInstanceId"] == boss["inventory"][0]["id"]
		),
		"Mara equips51 and retains59/shield67/drop76"
	):
		return false
	for identity: int in [39, 38, 37, 40, 35]:
		held.clear()
		for item: Dictionary in battle.unit(identity)["inventory"]:
			held.append(int(item["templateId"]))
		if not _expect(held == [47, 80], "Each of five regional sorcerers carries47 and actual80"):
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
