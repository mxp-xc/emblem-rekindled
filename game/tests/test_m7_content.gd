extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M6 = preload("res://tests/test_m6_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Independent oracle: temp/m3-m7/deployments/p7.json and m7-route-*.json.
const CONTEXTS: Array[Dictionary] = [
	{"route": 1, "step": 3, "party": [0, 9, 6, 1], "classes": [0, 4, 20, 4], "next": 6},
	{
		"route": 2,
		"step": 6,
		"party": [0, 9, 3, 8, 2, 4],
		"classes": [0, 4, 16, 12, 8, 8],
		"next": 8
	},
	{
		"route": 3,
		"step": 6,
		"party": [0, 9, 3, 7, 6, 1],
		"classes": [0, 4, 16, 12, 20, 4],
		"next": 6
	},
	{"route": 4, "step": 3, "party": [0, 9, 2, 4], "classes": [0, 4, 8, 8], "next": 8},
	{"route": 6, "step": 1, "party": [0, 9], "classes": [0, 4]},
	{"route": 7, "step": 1, "party": [0, 9], "classes": [0, 4]}
]
# [deployment index, slot, cell], in source-record order, not slot order.
const SLOTS: Array = [
	[0, 2, [9, 24]],
	[19, 0, [10, 24]],
	[20, 1, [11, 24]],
	[21, 5, [9, 23]],
	[22, 4, [10, 23]],
	[23, 3, [11, 23]]
]
const RANDOM_ORDER: Array[int] = [110, 109, 107, 108]
var _draws: Array[int] = []
var _owned: String = ""


func _initialize() -> void:
	_owned = "user://m7_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim fresh owned m7 content directory")
		return
	for context: Dictionary in CONTEXTS:
		if not _context(context):
			_cleanup()
			return
	if not _random_edges():
		_cleanup()
		return
	_cleanup()
	print(
		"PASS actual m7 content: six contexts, slot binding, random borders, held drops and cold JSON"
	)
	quit(0)


# route6 is a real m0 choice8/route6 completed world. route7 is a snapshot
# fixture, never a rewritten m0 route. route4 uses a real m6 settlement from
# M6's explicit snapshot fixture; this does not claim natural preceding combat.
static func prepare(
	context: Dictionary, roll: Callable, reverse_fixture_party: bool = false
) -> Dictionary:
	if context["route"] in [4, 6]:
		var opened: Dictionary
		if context["route"] == 6:
			opened = Session.new().open(CHAPTER, "m0", {"new": true}, roll)
		else:
			var prior: Dictionary = M6.prepare(M6.CONTEXTS[4], roll)
			if not prior["ok"]:
				return prior
			opened = Session.new().open(CHAPTER, "m6", prior["source"], roll)
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
		"m7",
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
	state["warehouse"] = [{"id": "m7 inherited warehouse", "templateId": 60, "durability": 2}]
	return {
		"ok": true,
		"kind": "domain_fixture",
		"source": {"snapshot": state},
		"initializationDraws": draws
	}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare actual m7 context: " + str(prepared.get("error"))):
		return false
	var source: Dictionary = JSON.parse_string(JSON.stringify(prepared["source"]))
	var before: Dictionary = source.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m7", source, _roll)
	if not _expect(opened["ok"], "Open actual m7: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	if not _expect(source == before, "Session leaves m7 source unchanged"):
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
	var again: Dictionary = Session.new().open(CHAPTER, "m7", reordered, _roll)
	if not _expect(
		again["ok"] and again["battle"].snapshot() == battle.snapshot(),
		"Reordered stored party/actors preserves m7 recruit-slot and native traversal order"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	if not _expect(store.write(battle)["ok"], "Write m7 only in owned directory"):
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
			"PASS actual m7 content dr%d step%d (%s)"
			% [context["route"], context["step"], prepared["kind"]]
		)
	)
	return true


func _deployment(context: Dictionary, content: Dictionary, battle: RefCounted) -> bool:
	if not _expect(
		(
			content["map"]["width"] == 24
			and content["map"]["height"] == 25
			and content["spawns"].size() == 42
			and battle.snapshot()["units"].size() == 42
			and content["slots"].size() == 6
			and battle.commander_id == 5
			and battle.unit(5)["formal"]
			and battle.unit(5)["classId"] == 16
			and battle.unit(5)["visible"]
			and Vector2i(battle.unit(5)["x"], battle.unit(5)["y"]) == Vector2i(11, 1)
		),
		"m7 has 24x25,42 records,six old slots and visible new formal5/commander5 at11,1"
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
			"Six hidden slots bind old recruit order/current class or source-order temporary identities"
		):
			return false
	var occupied: Dictionary = {}
	var random_count: int = 0
	for actor: Dictionary in battle.snapshot()["units"]:
		var cell := Vector2i(actor["x"], actor["y"])
		if not _expect(
			not occupied.has(cell), "Hidden and visible actors reserve distinct initial cells"
		):
			return false
		occupied[cell] = true
		if actor["id"] in RANDOM_ORDER:
			random_count += 1
			if not _expect(
				not actor["visible"] and actor["y"] == 0 and actor["x"] >= 0 and actor["x"] <= 23,
				"Four future reinforcements are hidden and use inclusive north-edge rectangle"
			):
				return false
		if not _expect(
			(
				ResourceLoader.exists(actor["sprite"])
				and content["interface"]["portraitByUnitId"].has(str(actor["id"]))
			),
			"Every bound actor resolves actual map sprite and portrait"
		):
			return false
	return _expect(random_count == 4, "All four random records survive deployment")


func _random_edges() -> bool:
	for last: bool in [false, true]:
		var roll: Callable = func(limit: int) -> int: return limit - 1 if last else 0
		var prepared: Dictionary = prepare(CONTEXTS[5], roll)
		if not _expect(prepared["ok"], "Build independent north-edge RNG fixture"):
			return false
		var snapshot: Dictionary = prepared["source"]["snapshot"]
		var position_draws: Array[int] = []
		for limit: int in prepared["initializationDraws"]:
			if limit > 6:
				position_draws.append(limit)
		if not _expect(
			position_draws == [24, 23, 22, 21],
			"North-edge deployment draws from24 then23/22/21 free cells including both borders"
		):
			return false
		for index: int in range(RANDOM_ORDER.size()):
			for actor: Dictionary in snapshot["units"]:
				if actor["id"] == RANDOM_ORDER[index]:
					if not _expect(
						actor["x"] == (23 - index if last else index) and actor["y"] == 0,
						"First/last RNG choices use source record order and reserve hidden cells"
					):
						return false
	return true


func _items(content: Dictionary, battle: RefCounted) -> bool:
	var boss: Dictionary = battle.unit(86)
	var profile: Dictionary = content["_library"]["profiles"][content["profiles"][86]]
	var boss_items: Array = []
	for held: Dictionary in boss["inventory"]:
		boss_items.append([int(held["templateId"]), int(held["durability"])])
	var staff_items: Array = []
	for held: Dictionary in battle.unit(44)["inventory"]:
		staff_items.append([int(held["templateId"]), int(held["durability"])])
	return _expect(
		(
			boss["sourceId"] == 86
			and boss["classId"] == 17
			and boss["dropTemplateId"] == 76
			and boss_items == [[19, 28], [65, 4], [76, 1]]
			and profile["portrait"]["portraitId"] == 17
			and content["story"]["speakers"]["86"]["portraitId"] == 17
			and battle.unit(44)["dropTemplateId"] == 55
			and staff_items == [[53, 23], [55, 18]]
		),
		"Boss86 keeps portrait17/equipped19/shield65/drop76;source44 holds53x23 plus drop55x18"
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
