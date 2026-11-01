extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Original controlled initialization: temp/m2/original-deployment/route-*.json,
# routes-summary.json and README.md. Classes are captured S, slot order is Y.
# These are identities/classes, not claims about naturally trained attributes.
const CONTEXTS: Array[Dictionary] = [
	{"route": 0, "step": 2, "party": [0, 9, 6], "classes": [0, 4, 20]},
	{"route": 3, "step": 2, "party": [0, 9, 3], "classes": [0, 4, 16]},
	{"route": 4, "step": 7, "party": [0, 9, 2, 4, 5, 1, 6], "classes": [0, 4, 8, 8, 16, 4, 20]},
	{"route": 5, "step": 4, "party": [0, 9, 2, 8, 3], "classes": [0, 4, 8, 12, 16]},
	{"route": 6, "step": 4, "party": [0, 9, 5, 1, 6], "classes": [0, 4, 16, 4, 20]},
	{"route": 7, "step": 7, "party": [0, 9, 5, 4, 2, 8, 3], "classes": [0, 4, 16, 8, 8, 12, 16]}
]
const SLOT_POINTS: Array = [[10, 2], [9, 2], [11, 2], [8, 2], [11, 1], [10, 1], [9, 1]]
const SLOT_CLASSES: Array = [0, 4, 8, 16, 8, 16, 20]
const RAW_IDS: Array = [
	35,
	30,
	31,
	69,
	68,
	67,
	66,
	65,
	64,
	63,
	-5,
	-1,
	-6,
	-3,
	-2,
	58,
	57,
	56,
	55,
	54,
	53,
	52,
	50,
	49,
	48,
	47,
	10,
	18,
	17,
	11,
	7,
	15,
	16,
	0,
	-4,
	33,
	32,
	82
]
var _draws: Array[int] = []
var _owned: String = ""


func _initialize() -> void:
	var directory: String = "user://m2_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(directory) != OK:
		_fail("Cannot claim a fresh owned m2 test directory")
		return
	_owned = directory
	for context: Dictionary in CONTEXTS:
		if not _context(context):
			_cleanup()
			return
	_cleanup()
	print(
		"PASS real m2 content: six routes, native order, profiles, resources, JSON restore, world slots"
	)
	quit(0)


# dr0 follows actual Session m0 -> m1 assisted completion. Other routes include
# unavailable prior maps. Build a legal synthetic world point from real m2
# Content/Battle templates instead of pretending to play those maps naturally.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	var session := Session.new()
	var progress: Dictionary
	if context["route"] == 0:
		var opened: Dictionary = session.open(CHAPTER, "m0", {"new": true}, roll)
		if not opened["ok"]:
			return opened
		for battle_id: String in ["m0", "m1"]:
			if battle_id == "m1":
				opened = session.open(CHAPTER, battle_id, {"progress": progress}, roll)
				if not opened["ok"]:
					return opened
			var won: Dictionary = opened["battle"].win_with_assistance()
			if not won["ok"]:
				return won
			var completed: Dictionary = opened["battle"].complete_victory(0)
			if not completed["ok"]:
				return completed
			progress = completed["progress"]
	else:
		var party: Array = []
		for index: int in range(context["party"].size()):
			party.append({"id": context["party"][index], "classId": context["classes"][index]})
		var native: Array = context["party"].duplicate()
		native[0] = 9
		native[1] = 0
		var compiled: Dictionary = Content.new().load_chapter(
			CHAPTER,
			"m2",
			{
				"party": party,
				"partyOrder": native,
				"route": context["route"],
				"worldStep": context["step"]
			}
		)
		if not compiled["ok"]:
			return compiled
		var template: RefCounted = Battle.new(compiled, roll)
		party.clear()
		for id: int in context["party"]:
			var member: Dictionary = template.unit(id)
			member["hp"] = member["maxHp"]
			member["flags"] = 0
			member["policy"] = 0
			member["visible"] = true
			member["action"] = 0
			party.append(member)
		var route: Array = compiled["story"]["world"]["routes"][context["route"]]
		var previous: int = int(route[context["step"] - 1])
		progress = {
			"chapterId": "chapter_1",
			"completedBattle": "m%d" % previous,
			"worldNode": previous,
			"worldStep": context["step"],
			"route": context["route"],
			"gold": 7000,
			"commander": 0,
			"commandPolicy": 0,
			"party": party,
			"warehouse": []
		}
	return {"ok": true, "progress": progress}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(
		prepared["ok"], "Prepare route %d: %s" % [context["route"], prepared.get("error")]
	):
		return false
	var progress: Dictionary = prepared["progress"]
	var before: Dictionary = progress.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m2", {"progress": progress}, _roll)
	if not _expect(opened["ok"], "Real m2 route %d: %s" % [context["route"], opened.get("error")]):
		return false
	var draws: Array = _draws.duplicate()
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	if not _expect(progress == before, "Session must preserve inherited world input"):
		return false
	if not _deployment(context, content, battle, draws):
		return false
	var reversed: Dictionary = progress.duplicate(true)
	reversed["party"].reverse()
	_draws.clear()
	var reordered: Dictionary = Session.new().open(CHAPTER, "m2", {"progress": reversed}, _roll)
	if not _expect(
		(
			reordered["ok"]
			and reordered["battle"].snapshot() == battle.snapshot()
			and reordered["content"]["unitOrder"] == content["unitOrder"]
			and _draws == draws
		),
		"Party array order cannot change bindings, native traversal, random recipients or results"
	):
		return false
	var state: Dictionary = battle.snapshot()
	state["round"] = 4
	state["events"]["party_arrival"] = true
	# A normal moved random deployment is legal outside its initial region.
	for actor: Dictionary in state["units"]:
		if actor["id"] == 82:
			actor["x"] = 12
			actor["y"] = 12
	if not _expect(battle.restore_snapshot(state)["ok"], "Moved real boss must remain saveable"):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	var encoded: Dictionary = store.encode(battle)
	if not _expect(encoded["ok"] and store.write(battle)["ok"], "Real m2 continue must write"):
		return false
	var record: Dictionary = JSON.parse_string(JSON.stringify(encoded["record"]))
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
			and restored["content"]["entry"]["battleId"] == "m2"
			and restored["content"]["map"] == content["map"]
			and store.read()["ok"]
		),
		"JSON continue must restore actual m2 map/roster/phase/events, with no initial RNG or mutation"
	):
		return false
	if not _expect(
		battle.win_with_assistance()["ok"], "Controlled m2 completion must be available"
	):
		return false
	var completed: Dictionary = battle.complete_victory(context["route"])
	if not _expect(completed["ok"], "Real m2 completion must retain its route"):
		return false
	var world: Dictionary = completed["progress"]
	var resolved: Dictionary = Session.new().completed_content(CHAPTER, world)
	if not _expect(
		(
			resolved["ok"]
			and resolved["content"]["story"]["battleNumber"] == context["step"] + 1
			and resolved["content"]["_context"]["worldStep"] == world["worldStep"] - 1
			and store.write_progress(world)["ok"]
			and store.read()["ok"]
			and store.write_slot(0, world)["ok"]
			and store.read_slot(0)["ok"]
		),
		"Completed world content uses step-1 and survives continue/named-slot storage"
	):
		return false
	print(
		(
			"PASS real m2 context dr%d step%d party%s"
			% [context["route"], context["step"], context["party"]]
		)
	)
	return true


func _deployment(
	context: Dictionary, content: Dictionary, battle: RefCounted, draws: Array
) -> bool:
	if not _expect(
		(
			content["spawns"].size() == 38
			and battle.snapshot()["units"].size() == 38
			and content["map"]["width"] == 22
			and content["map"]["height"] == 26
			and battle.commander_id == 7
			and battle.unit(7)["classId"] == 12
			and battle.unit(7)["formal"]
			and battle.unit(7)["visible"]
			and content["story"]["battleNumber"] == context["step"] + 1
			and content["story"]["sequences"]["opening"][0]["text"]["text"].begins_with(
				"第%d战\n" % (context["step"] + 1)
			)
		),
		"m2 must use 38 actual deployments, real map, new recruit/commander 7 and current battle title"
	):
		return false
	var slots: Dictionary = content["slots"]
	var temporary: Dictionary = {}
	if context["party"].size() < 7:
		temporary = {5: 95, 6: 96}
		if context["party"].size() == 3:
			temporary.merge({3: 97, 4: 98})
	for slot: int in range(7):
		var formal: bool = slot < context["party"].size()
		var id: int = context["party"][slot] if formal else temporary[slot]
		var job: int = context["classes"][slot] if formal else SLOT_CLASSES[slot]
		var recipe: String = ("source_%d" % id) if formal else ("slot_%d" % slot)
		var actor: Dictionary = battle.unit(id)
		if not _expect(
			(
				slots[slot] == id
				and actor["classId"] == job
				and actor["formal"] == formal
				and actor["sourceId"] == (id if formal else slot)
				and actor["x"] == SLOT_POINTS[slot][0]
				and actor["y"] == SLOT_POINTS[slot][1]
				and actor["flags"] == 1
				and not actor["visible"]
				and actor["policy"] == 0
				and content["profiles"][id] == "%s_job_%d_faction_0" % [recipe, job]
			),
			(
				"Route %d slot%d must bind source identity/current class and canonical hidden position"
				% [context["route"], slot]
			)
		):
			return false
	var expected: Array = [9, 0]
	expected.append_array(context["party"].slice(2))
	for raw_id: int in RAW_IDS:
		var id: int = slots[-raw_id] if raw_id < 0 else (slots[0] if raw_id == 0 else raw_id)
		if id not in expected:
			expected.append(id)
	var actual: Array = []
	var occupied: Dictionary = {}
	var visible: int = 0
	for actor: Dictionary in battle.snapshot()["units"]:
		actual.append(int(actor["id"]))
		visible += int(actor["visible"])
		var cell := Vector2i(actor["x"], actor["y"])
		if not _expect(
			not occupied.has(cell),
			"Every original deployment, including hidden ones, reserves one cell"
		):
			return false
		occupied[cell] = true
		var profile: Dictionary = content["_library"]["profiles"][content["profiles"][actor["id"]]]
		if not _expect(
			(
				content["mapAnimations"]["units"].has(str(actor["id"]))
				and ResourceLoader.exists(actor["sprite"])
			),
			"Actual deployment must resolve a real map sprite"
		):
			return false
		for weapon: String in profile["appearances"]:
			var alias: String = "%d:%s" % [actor["id"], weapon]
			if not _expect(
				(
					content["battleArt"]["appearances"].has(alias)
					and content["battleClips"]["appearances"].has(alias)
				),
				"Current source profile must retain every declared action"
			):
				return false
	if not _expect(
		content["unitOrder"] == expected and actual == expected and visible == 21,
		"Native as order starts with old [9,0,...], raw p appends the rest; initial visible count is 21"
	):
		return false
	for sample: Array in [[33, 17, 15, 18, 18], [32, 6, 14, 7, 16], [82, 4, 21, 16, 24]]:
		var actor: Dictionary = battle.unit(sample[0])
		if not _expect(
			(
				actor["x"] >= sample[1]
				and actor["x"] <= sample[3]
				and actor["y"] >= sample[2]
				and actor["y"] <= sample[4]
			),
			"Real random deployments stay inside source bounds"
		):
			return false
	# Source p2 has 30 non-player units, each draws eight growth noises. The
	# final three p records draw position before that record's growth, not as order.
	var noise: Array = [4, 3, 3, 3, 3, 6, 3, 1]
	var suffix: Array = []
	for candidates: int in [7, 6, 50]:
		if candidates != 50:
			suffix.append(3)  # Equipment precedes position for records 33 and 32.
		suffix.append(candidates)
		suffix.append_array(noise)
	return _expect(
		draws.slice(draws.size() - suffix.size()) == suffix,
		"Raw p initialization must draw real random positions 33/32/82 before each actor's growth"
	)


func _roll(limit: int) -> int:
	_draws.append(limit)
	return 0


func _cleanup() -> void:
	if _owned.is_empty():
		return
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
