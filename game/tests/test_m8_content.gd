extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M7 = preload("res://tests/test_m7_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Independent oracle: temp/m8/p8-oracle.json and original-route-*/observations.json.
const CONTEXTS: Array[Dictionary] = [
	{"route": 1, "step": 2, "party": [0, 9, 6], "classes": [0, 4, 20], "next": 7},
	{
		"route": 2,
		"step": 7,
		"party": [0, 9, 3, 8, 2, 4, 5],
		"classes": [0, 4, 16, 12, 8, 8, 16],
		"next": 12
	},
	{"route": 3, "step": 4, "party": [0, 9, 3, 7, 6], "classes": [0, 4, 16, 12, 20], "next": 12},
	{"route": 4, "step": 4, "party": [0, 9, 2, 4, 5], "classes": [0, 4, 8, 8, 16], "next": 12},
	{
		"route": 5,
		"step": 7,
		"party": [0, 9, 2, 8, 3, 7, 6],
		"classes": [0, 4, 8, 12, 16, 12, 20],
		"next": 12
	},
	{"route": 6, "step": 2, "party": [0, 9, 5], "classes": [0, 4, 16], "next": 1}
]
# Source record order, independently transcribed from p8-oracle.json.
const SLOTS: Array = [
	[0, 1, [19, 24]],
	[27, 0, [17, 24]],
	[28, 2, [18, 24]],
	[29, 3, [20, 24]],
	[30, 4, [17, 25]],
	[31, 5, [18, 25]],
	[37, 6, [19, 25]]
]
const RECORDS: Array = [
	[1, 4, 0, 19, 24, false],
	[1, 4, 0, 11, 7, false],
	[16, 24, 1, 14, 17, true],
	[18, 4, 1, 7, 9, false],
	[14, 12, 1, 8, 11, true],
	[17, 12, 1, 13, 18, true],
	[13, 24, 1, 7, 11, false],
	[11, 24, 1, 15, 6, false],
	[45, 5, 2, 2, 17, false],
	[46, 5, 2, 25, 7, true],
	[12, 20, 1, 13, 16, true],
	[10, 20, 1, 13, 8, true],
	[49, 32, 2, 8, 18, false],
	[50, 32, 2, 7, 17, false],
	[51, 36, 2, 1, 12, true],
	[52, 36, 2, 2, 22, true],
	[53, 36, 2, 24, 22, true],
	[54, 36, 2, 24, 10, true],
	[55, 36, 2, 24, 3, true],
	[56, 28, 2, 22, 7, false],
	[57, 28, 2, 22, 5, false],
	[58, 28, 2, 6, 15, false],
	[59, 28, 2, 19, 16, false],
	[15, 4, 1, 13, 6, false],
	[61, 4, 2, 20, 15, true],
	[62, 36, 2, 19, 15, true],
	[63, 36, 2, 20, 12, true],
	[0, 0, 0, 17, 24, false],
	[2, 8, 0, 18, 24, false],
	[3, 16, 0, 20, 24, true],
	[4, 8, 0, 17, 25, false],
	[5, 16, 0, 18, 25, true],
	[30, 32, 2, 8, 23, false],
	[32, 32, 2, 24, 14, false],
	[31, 32, 2, 6, 2, false],
	[33, 5, 2, 1, 7, false],
	[87, 5, 2, 1, 6, true],
	[6, 20, 0, 19, 25, false],
	[64, 28, 2, 20, 16, false],
	[65, 29, 2, 3, 16, false]
]
var _draws: Array[int] = []
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(CONTEXTS.slice(0, 2), true)


func _run_contexts(contexts: Array, include_random: bool) -> void:
	_owned = "user://m8_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim fresh owned m8 content directory")
		return
	for context: Dictionary in contexts:
		if not _context(context):
			_cleanup()
			return
	if include_random and not _random_equipment():
		_cleanup()
		return
	_cleanup()
	print("PASS actual m8 content: selected contexts and requested equipment RNG boundaries")
	quit(0)


# Routes4/6 enter through a real m7 settlement; other contexts are explicit
# domain fixtures, not claims of naturally playing their preceding battles.
static func prepare(
	context: Dictionary, roll: Callable, reverse_fixture_party: bool = false
) -> Dictionary:
	if context["route"] in [4, 6]:
		var prior_context: Dictionary = M7.CONTEXTS[3 if context["route"] == 4 else 4]
		var prior: Dictionary = M7.prepare(prior_context, roll)
		if not prior["ok"]:
			return prior
		var opened: Dictionary = Session.new().open(CHAPTER, "m7", prior["source"], roll)
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
		"m8",
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
	if reverse_fixture_party:
		party.reverse()
	compiled["inheritedParty"] = party
	var draws: Array[int] = []
	var recorded: Callable = func(limit: int) -> int:
		draws.append(limit)
		return int(roll.call(limit))
	var battle: RefCounted = Battle.new(compiled, recorded)
	var state: Dictionary = battle.snapshot()
	state["campaign"] = {"route": context["route"], "worldStep": context["step"]}
	state["gold"] = 7000
	state["warehouse"] = [{"id": "m8 inherited warehouse", "templateId": 60, "durability": 2}]
	return {
		"ok": true,
		"kind": "domain_fixture",
		"source": {"snapshot": state},
		"initializationDraws": draws
	}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare actual m8 context: " + str(prepared.get("error"))):
		return false
	var source: Dictionary = JSON.parse_string(JSON.stringify(prepared["source"]))
	var before: Dictionary = source.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m8", source, _roll)
	if not _expect(opened["ok"], "Open actual m8: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	if not _expect(source == before, "Session leaves m8 source unchanged"):
		return false
	if (
		source.has("snapshot")
		and not _expect(_draws.is_empty(), "Snapshot opens with zero initialization RNG")
	):
		return false
	if not _deployment(context, content, battle) or not _items(content, battle):
		return false
	# Both JSON actor order and inherited party order are storage details.
	var reordered: Dictionary = source.duplicate(true)
	if source.has("progress"):
		reordered["progress"]["party"].reverse()
	else:
		reordered["snapshot"]["units"].reverse()
	var again: Dictionary = Session.new().open(CHAPTER, "m8", reordered, _roll)
	if not _expect(
		again["ok"] and again["battle"].snapshot() == battle.snapshot(),
		"Reordered stored party/actors preserves m8 recruit-slot and native traversal order"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	if not _expect(store.write(battle)["ok"], "Write m8 only in owned directory"):
		return false
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	record["state"]["units"].reverse()
	var preserved: Dictionary = record.duplicate(true)
	_draws.clear()
	var restored: Dictionary = store.decode(record, _roll)
	if not _expect(
		(
			restored["ok"]
			and _draws.is_empty()
			and record == preserved
			and restored["battle"].snapshot() == battle.snapshot()
			and store.read()["ok"]
		),
		"Store actual JSON restores source/order/slots/items/random cells without initialization RNG"
	):
		return false
	print(
		(
			"PASS actual m8 content dr%d step%d (%s)"
			% [context["route"], context["step"], prepared["kind"]]
		)
	)
	return true


func _deployment(context: Dictionary, content: Dictionary, battle: RefCounted) -> bool:
	if not _expect(
		(
			content["map"]["width"] == 26
			and content["map"]["height"] == 27
			and content["spawns"].size() == 40
			and battle.snapshot()["units"].size() == 40
			and content["slots"].size() == 7
			and battle.commander_id == 1
			and battle.unit(1)["formal"]
			and battle.unit(1)["classId"] == 4
			and battle.unit(1)["visible"]
			and Vector2i(battle.unit(1)["x"], battle.unit(1)["y"]) == Vector2i(11, 7)
		),
		"m8 has26x27/40 records/seven old slots and distinct visible new formal1"
	):
		return false
	var temporary: int = 95
	for specification: Array in SLOTS:
		var slot: int = specification[1]
		var formal: bool = slot < context["party"].size()
		var identity: int = context["party"][slot] if formal else temporary
		if not formal:
			temporary += 1
		var actor: Dictionary = battle.unit(identity)
		if not _expect(
			(
				content["slots"][slot] == identity
				and actor["formal"] == formal
				and not actor["visible"]
				and actor["deploymentIndex"] == specification[0]
				and Vector2i(actor["x"], actor["y"]) == _cell(specification[2])
				and (not formal or actor["classId"] == context["classes"][slot])
			),
			"Seven hidden slots preserve recruit order, source-order temporary IDs and inherited classes"
		):
			return false
	var occupied: Dictionary = {}
	for actor: Dictionary in battle.snapshot()["units"]:
		var index: int = actor["deploymentIndex"]
		var oracle: Array = RECORDS[index]
		var cell := Vector2i(actor["x"], actor["y"])
		if not _expect(
			(
				not occupied.has(cell)
				and cell == Vector2i(oracle[3], oracle[4])
				and ResourceLoader.exists(actor["sprite"])
				and content["interface"]["portraitByUnitId"].has(str(actor["id"]))
			),
			"Every actual record retains its fixed cell and complete map/portrait presentation"
		):
			return false
		occupied[cell] = true
		if (
			actor["faction"] != 0
			and not _expect(
				(
					actor["sourceId"] == oracle[0]
					and actor["classId"] == oracle[1]
					and actor["faction"] == oracle[2]
				),
				"Native friend/enemy source and class survive normalization"
			)
		):
			return false
	return true


func _random_equipment() -> bool:
	for last: bool in [false, true]:
		var roll: Callable = func(limit: int) -> int: return limit - 1 if last else 0
		var prepared: Dictionary = prepare(CONTEXTS[0], roll)
		if not _expect(prepared["ok"], "Prepare independent equipment RNG boundary"):
			return false
		var expected: Array[int] = []
		var count: int = 0
		for row: Array in RECORDS:
			if row[5]:
				expected.append(3)
				count += 1
			if row[2] != 0:
				expected.append_array([4, 3, 3, 3, 3, 6, 3, 1])
		if not _expect(
			count == 17 and prepared["initializationDraws"] == expected,
			"Exactly17 equipment draws precede fixed-cell initialization; no position RNG is consumed"
		):
			return false
	return true


func _items(content: Dictionary, battle: RefCounted) -> bool:
	var new_items: Array[int] = []
	for held: Dictionary in battle.unit(1)["inventory"]:
		new_items.append(int(held["templateId"]))
	var boss: Dictionary = battle.unit(87)
	var profile: Dictionary = content["_library"]["profiles"][content["profiles"][87]]
	var drop: Dictionary = {}
	for held: Dictionary in boss["inventory"]:
		if held["templateId"] == 59:
			drop = held
	return _expect(
		(
			new_items == [53, 59]
			and not drop.is_empty()
			and drop["durability"] == 10
			and boss["dropTemplateId"] == 59
			and profile["portrait"]["portraitId"] == 18
			and content["story"]["speakers"]["87"]["portraitId"] == 18
		),
		"New1 holds53/59;boss87 carries actual59x10 drop and portrait18"
	)


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
