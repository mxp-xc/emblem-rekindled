extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Source: temp/m3-m7/deployments/{README,p3,m3-route-*}.json/md.
# Captured classes and recruit order are initialization evidence, not natural training.
const CONTEXTS: Array[Dictionary] = [
	{"route": 0, "step": 3, "party": [0, 9, 6, 7], "classes": [0, 4, 20, 12], "next": 4},
	{"route": 2, "step": 1, "party": [0, 9], "classes": [0, 4], "next": 4},
	{"route": 3, "step": 1, "party": [0, 9], "classes": [0, 4], "next": 2},
	{"route": 5, "step": 3, "party": [0, 9, 2, 8], "classes": [0, 4, 8, 12], "next": 2},
	{
		"route": 6,
		"step": 6,
		"party": [0, 9, 5, 1, 6, 7],
		"classes": [0, 4, 16, 4, 20, 12],
		"next": 4
	},
	{"route": 7, "step": 6, "party": [0, 9, 5, 4, 2, 8], "classes": [0, 4, 16, 8, 8, 12], "next": 2}
]
const SLOT_POINTS: Array = [[16, 3], [16, 2], [17, 3], [17, 2], [18, 2], [16, 1]]
const SLOT_CLASSES: Array = [0, 4, 8, 16, 8, 16]
# Negative IDs denote old deployment slots; direct recruit3 is distinct from slot3.
const RAW_IDS: Array = [
	-5,
	68,
	69,
	11,
	10,
	108,
	107,
	109,
	110,
	30,
	60,
	3,
	38,
	15,
	16,
	12,
	14,
	43,
	44,
	83,
	46,
	47,
	48,
	49,
	50,
	51,
	52,
	53,
	54,
	0,
	-1,
	-4,
	-3,
	-2,
	13,
	63,
	64,
	65,
	66
]
const RAW_POINTS: Array = [
	[16, 1],
	[12, 12],
	[10, 12],
	[14, 6],
	[8, 6],
	[16, 14],
	[18, 7],
	[6, 14],
	[4, 5],
	[15, 16],
	[12, 19],
	[11, 9],
	[7, 15],
	[10, 8],
	[12, 8],
	[9, 7],
	[13, 7],
	[11, 19],
	[15, 15],
	[11, 20],
	[10, 19],
	[14, 17],
	[7, 16],
	[8, 17],
	[9, 11],
	[11, 11],
	[13, 11],
	[10, 15],
	[12, 15],
	[16, 3],
	[16, 2],
	[18, 2],
	[17, 2],
	[17, 3],
	[11, 7],
	[12, 5],
	[10, 5],
	[11, 4],
	[11, 5]
]
var _draws: Array[int] = []
var _owned: String = ""


func _initialize() -> void:
	_run_contexts(CONTEXTS.slice(0, 2))


func _run_contexts(contexts: Array) -> void:
	_owned = "user://m3_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim a fresh owned m3 content directory")
		return
	for context: Dictionary in contexts:
		if not _context(context):
			_cleanup()
			return
	_cleanup()
	print("PASS real m3 content: selected contexts, deployments, party bindings and JSON restore")
	quit(0)


# dr0 uses real Session m0/m1/m2 assisted completions, dr2 uses m0 choice2.
# m0 offers representative route2, not route3: dr3 projects that completed
# progress onto its identical legal prefix. Other contexts contain unavailable
# earlier maps, so their world points deliberately use real m3 unit templates.
# None of these controlled fixtures claims natural full-chapter combat.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	var session := Session.new()
	var progress: Dictionary
	if context["route"] in [0, 2, 3]:
		var opened: Dictionary = session.open(CHAPTER, "m0", {"new": true}, roll)
		if not opened["ok"]:
			return opened
		var prior: Array = ["m0", "m1", "m2"] if context["route"] == 0 else ["m0"]
		for battle_id: String in prior:
			if battle_id != "m0":
				opened = session.open(CHAPTER, battle_id, {"progress": progress}, roll)
				if not opened["ok"]:
					return opened
			var won: Dictionary = opened["battle"].win_with_assistance()
			if not won["ok"]:
				return won
			var completed: Dictionary = opened["battle"].complete_victory(
				0 if context["route"] == 0 else 2
			)
			if not completed["ok"]:
				return completed
			progress = completed["progress"]
		progress["route"] = context["route"]
	else:
		var party: Array = []
		for index: int in range(context["party"].size()):
			party.append({"id": context["party"][index], "classId": context["classes"][index]})
		var native: Array = context["party"].duplicate()
		native[0] = 9
		native[1] = 0
		var compiled: Dictionary = Content.new().load_chapter(
			CHAPTER,
			"m3",
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
	progress["warehouse"] = [{"id": "m3:inherited:warehouse", "templateId": 60, "durability": 2}]
	return {"ok": true, "progress": progress}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare legal m3 context: " + str(prepared.get("error"))):
		return false
	# Real JSON world input, including float-decoded numeric fields.
	var progress: Dictionary = JSON.parse_string(JSON.stringify(prepared["progress"]))
	var before: Dictionary = progress.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m3", {"progress": progress}, _roll)
	if not _expect(opened["ok"], "Open actual m3: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var draws: Array = _draws.duplicate()
	if not _expect(progress == before, "Opening m3 cannot mutate inherited world input"):
		return false
	if not _deployment(context, content, battle):
		return false
	var reversed: Dictionary = progress.duplicate(true)
	reversed["party"].reverse()
	_draws.clear()
	var reordered: Dictionary = Session.new().open(CHAPTER, "m3", {"progress": reversed}, _roll)
	if not _expect(
		(
			reordered["ok"]
			and reordered["battle"].snapshot() == battle.snapshot()
			and reordered["content"]["unitOrder"] == content["unitOrder"]
			and _draws == draws
		),
		"Party array order cannot change m3 slots, initialization RNG or native traversal"
	):
		return false
	var state: Dictionary = battle.snapshot()
	# Valid moved coordinates are independent of the original fixed deployment.
	for actor: Dictionary in state["units"]:
		if actor["id"] == 83:
			actor["x"] = 20
			actor["y"] = 20
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Moved actual m3 boss must remain saveable"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	var encoded: Dictionary = store.encode(battle)
	if not _expect(
		encoded["ok"] and store.write(battle)["ok"], "m3 writes only its owned continue"
	):
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
			and restored["content"]["entry"]["battleId"] == "m3"
			and restored["content"]["map"] == content["map"]
			and store.read()["ok"]
		),
		"JSON m3 restore keeps actual map/roster/coordinates without initialization RNG or mutation"
	):
		return false
	print("PASS actual m3 content dr%d step%d" % [context["route"], context["step"]])
	return true


func _deployment(context: Dictionary, content: Dictionary, battle: RefCounted) -> bool:
	if not _expect(
		(
			content["spawns"].size() == 39
			and battle.snapshot()["units"].size() == 39
			and content["map"]["width"] == 22
			and content["map"]["height"] == 22
			and content["slots"].size() == 6
			and battle.unit(3)["formal"]
			and battle.unit(3)["classId"] == 16
			and battle.unit(3)["level"] == 10
			and battle.unit(3)["visible"]
			and battle.unit(3)["x"] == 11
			and battle.unit(3)["y"] == 9
			and content["story"]["battleNumber"] == context["step"] + 1
			and content["story"]["sequences"]["opening"][0]["text"]["text"].begins_with(
				"第%d战\n" % (context["step"] + 1)
			)
		),
		"m3 must resolve its real 22x22 map, 39 records, six slots and direct level10 recruit3"
	):
		return false
	var slots: Dictionary = content["slots"]
	var temporary: Dictionary = {}
	var next_id: int = 95
	for slot: int in [5, 0, 1, 4, 3, 2]:
		if slot >= context["party"].size():
			temporary[slot] = next_id
			next_id += 1
	for slot: int in range(6):
		var formal: bool = slot < context["party"].size()
		var id: int = context["party"][slot] if formal else temporary[slot]
		var job: int = context["classes"][slot] if formal else SLOT_CLASSES[slot]
		var actor: Dictionary = battle.unit(id)
		var profile: String = (
			"%s_%d_job_%d_faction_0" % ["source" if formal else "slot", id if formal else slot, job]
		)
		if not _expect(
			(
				slots[slot] == id
				and actor["classId"] == job
				and actor["formal"] == formal
				and actor["sourceId"] == (id if formal else slot)
				and actor["flags"] == 1
				and not actor["visible"]
				and actor["policy"] == 0
				and [actor["x"], actor["y"]] == SLOT_POINTS[slot]
				and content["profiles"][id] == profile
			),
			"m3 slot%d must retain recruit identity/current class and canonical hidden cell" % slot
		):
			return false
	var expected: Array = [9, 0]
	expected.append_array(context["party"].slice(2))
	var source_slots: Array = []
	for index: int in range(RAW_IDS.size()):
		var raw: int = RAW_IDS[index]
		var id: int = slots[-raw] if raw < 0 else (slots[0] if raw == 0 else raw)
		var spawn: Dictionary = content["spawns"][index]
		if not _expect(
			(
				spawn["id"] == id
				and _cell(spawn["position"]) == _cell(RAW_POINTS[index])
				and not spawn.has("deploymentRegions")
				and Vector2i(battle.unit(id)["x"], battle.unit(id)["y"]) == _cell(RAW_POINTS[index])
			),
			(
				"m3 record%d must preserve source identity and fixed position %s without random regions"
				% [index, RAW_POINTS[index]]
			)
		):
			return false
		if spawn.has("deploymentSlot"):
			source_slots.append(int(spawn["deploymentSlot"]))
		if id not in expected:
			expected.append(id)
	var actual: Array = []
	var visible: int = 0
	for actor: Dictionary in battle.snapshot()["units"]:
		actual.append(int(actor["id"]))
		visible += int(actor["visible"])
		if not _expect(
			(
				ResourceLoader.exists(actor["sprite"])
				and content["mapAnimations"]["units"].has(str(actor["id"]))
			),
			"Every actual m3 unit resolves real map presentation"
		):
			return false
		var profile: Dictionary = content["_library"]["profiles"][content["profiles"][actor["id"]]]
		for weapon: String in profile["appearances"]:
			var alias: String = "%d:%s" % [actor["id"], weapon]
			if not _expect(
				(
					content["battleArt"]["appearances"].has(alias)
					and content["battleClips"]["appearances"].has(alias)
				),
				"m3 source profile retains every declared battle appearance"
			):
				return false
	return _expect(
		(
			source_slots == [5, 0, 1, 4, 3, 2]
			and actual == expected
			and content["unitOrder"] == expected
			and visible == 19
		),
		"m3 source slot order differs from native vector; 19 units begin visible"
	)


func _roll(limit: int) -> int:
	_draws.append(limit)
	return 0


# JSON numeric arrays use float Variants; grid coordinates have integer meaning.
func _cell(point: Array) -> Vector2i:
	return Vector2i(int(point[0]), int(point[1]))


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
