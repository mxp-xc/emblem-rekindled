extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const M8 = preload("res://tests/test_m8_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# p12-oracle.json and static-inventory.json, independently parsed from original p12.
const CONTEXTS: Array[Dictionary] = [
	{
		"route": 2,
		"step": 8,
		"party": [0, 9, 3, 8, 2, 4, 5, 1],
		"classes": [0, 4, 16, 12, 8, 8, 16, 4],
		"next": 16
	},
	{
		"route": 3,
		"step": 5,
		"party": [0, 9, 3, 7, 6, 1],
		"classes": [0, 4, 16, 12, 20, 4],
		"next": 7
	},
	{"route": 4, "step": 5, "party": [0, 9, 2, 4, 5, 1], "classes": [0, 4, 8, 8, 16, 4], "next": 1},
	{
		"route": 5,
		"step": 8,
		"party": [0, 9, 2, 8, 3, 7, 6, 1],
		"classes": [0, 4, 8, 12, 16, 12, 20, 4],
		"next": 16
	}
]

# source,class,level,faction,flags,policy,randomEquipment,items,drop,cell/regions,slot.
const RAW: Array = [
	[4, 8, 10, 0, 0, 32, 1, [22, 27, 0], 0, [23, 15], 4],
	[0, 0, 1, 0, 0, 32, 0, [0, 0, 0], 0, [12, 24], 0],
	[6, 20, 1, 0, 0, 32, 0, [35, 61, 31], 0, [0, 15], 6],
	[5, 16, 1, 0, 0, 32, 1, [15, 19, 0], 0, [23, 16], 5],
	[1, 4, 1, 0, 0, 32, 0, [0, 0, 0], 0, [11, 24], 1],
	[2, 8, 1, 0, 0, 32, 1, [21, 23, 25], 0, [10, 24], 2],
	[3, 16, 1, 0, 0, 32, 1, [17, 14, 0], 0, [13, 24], 3],
	[7, 12, 1, 0, 0, 32, 0, [61, 45, 0], 0, [0, 16], 7],
	[89, 13, 1, 2, 0, 4, 0, [46, 51, 65], 57, [12, 1], -1],
	[11, 5, 1, 1, 0, 0, 0, [43, 53, 0], 0, [1, 16], -1],
	[13, 5, 1, 1, 0, 0, 0, [53, 43, 0], 0, [22, 16], -1],
	[10, 25, 1, 1, 0, 0, 0, [4, 41, 0], 0, [1, 15], -1],
	[12, 25, 1, 1, 0, 0, 0, [4, 44, 0], 0, [22, 15], -1],
	[15, 25, 1, 1, 0, 0, 0, [5, 44, 0], 0, [11, 23], -1],
	[16, 5, 1, 1, 0, 0, 0, [53, 45, 0], 0, [12, 23], -1],
	[41, 29, 1, 2, 0, 4, 0, [29, 67, 0], 63, [11, 7], -1],
	[40, 29, 1, 2, 0, 4, 0, [29, 67, 0], 63, [12, 7], -1],
	[43, 28, 1, 2, 0, 4, 0, [67, 29, 0], 63, [11, 12], -1],
	[42, 28, 1, 2, 0, 4, 0, [67, 29, 0], 63, [12, 12], -1],
	[37, 12, 1, 2, 0, 4, 0, [51, 0, 0], 65, [11, 6], -1],
	[36, 13, 1, 2, 0, 4, 0, [50, 0, 0], 65, [12, 6], -1],
	[34, 20, 1, 2, 0, 4, 0, [34, 0, 0], 0, [11, 11], -1],
	[35, 20, 1, 2, 0, 4, 0, [34, 0, 0], 0, [12, 11], -1],
	[39, 29, 1, 2, 0, 4, 0, [67, 29, 0], 0, [11, 2], -1],
	[38, 29, 1, 2, 0, 4, 0, [67, 29, 0], 0, [12, 2], -1],
	[68, 36, 1, 2, 1, 0, 0, [45, 0, 0], 0, [[19, 15, 21, 16]], -1],
	[67, 36, 1, 2, 1, 0, 1, [43, 47, 44], 0, [[17, 9, 18, 10]], -1],
	[66, 37, 1, 2, 1, 0, 1, [41, 44, 42], 0, [[4, 9, 5, 10]], -1],
	[65, 36, 1, 2, 1, 0, 1, [45, 40, 42], 0, [[5, 19, 7, 20]], -1],
	[64, 5, 1, 2, 1, 0, 1, [48, 44, 42], 0, [[4, 14, 5, 16]], -1],
	[63, 5, 1, 2, 1, 0, 1, [53, 54, 41], 0, [[2, 14, 3, 16]], -1],
	[62, 8, 1, 2, 1, 0, 1, [28, 25, 22], 0, [[19, 14, 20, 16]], -1],
	[61, 9, 1, 2, 1, 0, 1, [23, 24, 25], 0, [[16, 14, 18, 15]], -1],
	[60, 24, 1, 2, 1, 0, 0, [3, 44, 0], 0, [[19, 10, 20, 11]], -1],
	[59, 25, 1, 2, 1, 0, 0, [2, 40, 0], 0, [[16, 10, 18, 11]], -1],
	[58, 16, 1, 2, 1, 0, 1, [16, 2, 17], 0, [[5, 10, 6, 11]], -1],
	[57, 16, 1, 2, 1, 0, 1, [14, 3, 15], 0, [[2, 10, 3, 11]], -1],
	[30, 16, 1, 2, 1, 0, 1, [19, 10, 15], 0, [[2, 9, 3, 10]], -1],
	[33, 8, 1, 2, 1, 0, 1, [25, 28, 21], 0, [[19, 16, 21, 18]], -1],
	[31, 24, 1, 2, 1, 0, 0, [11, 42, 0], 0, [[20, 9, 21, 10]], -1],
	[32, 5, 1, 2, 1, 0, 1, [47, 44, 48], 0, [[2, 18, 4, 19]], -1]
]

var _draws: Array[int] = []
var _owned: String = ""


func _initialize() -> void:
	_owned = "user://m12_content_%d" % Time.get_ticks_usec()
	if not _expect(DirAccess.make_dir_absolute(_owned) == OK, "Claim fresh owned records"):
		return
	for context: Dictionary in _contexts():
		var prepared: Dictionary = prepare(context, _zero)
		if not _expect(prepared["ok"], "Prepare real m8 settlement: " + str(prepared.get("error"))):
			return
		var source: Dictionary = JSON.parse_string(JSON.stringify(prepared["source"]))
		var before: Dictionary = source.duplicate(true)
		_draws.clear()
		var opened: Dictionary = Session.new().open(CHAPTER, "m12", source, _roll)
		if not _expect(opened["ok"], "Open actual m12: " + str(opened.get("error"))):
			return
		if not _expect(
			(
				opened["content"]["spawns"].size() == 41
				and opened["battle"].snapshot()["units"].size() == 41
			),
			"m12 preserves all 41 original deployment records"
		):
			return
		if not _expect(source == before, "Entering m12 leaves source progress unchanged"):
			return
		if not _deployment(context, opened, _draws.duplicate(), source["progress"]["party"]):
			return
		var reordered: Dictionary = source.duplicate(true)
		reordered["progress"]["party"].reverse()
		_draws.clear()
		var again: Dictionary = Session.new().open(CHAPTER, "m12", reordered, _roll)
		if not _expect(
			again["ok"] and again["battle"].snapshot() == opened["battle"].snapshot(),
			"Stored party array order does not change slot bindings or native order"
		):
			return
		if not _cold(opened, "route%d" % context["route"]):
			return
		print(
			(
				"PASS m12 content route%d step%d controlled m8 settlement"
				% [context["route"], context["step"]]
			)
		)
	_cleanup()
	print("PASS m12 actual content, deployment and cold JSON")
	quit(0)


func _contexts() -> Array[Dictionary]:
	return [CONTEXTS[0]]


# Earlier route prefixes are controlled domain fixtures. The last m8 victory and
# settlement are real public commands; this does not claim natural whole-chapter play.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	var prior: Dictionary = M8.prepare(M8.CONTEXTS[int(context["route"]) - 1], roll)
	if not prior["ok"]:
		return prior
	var opened: Dictionary = Session.new().open(CHAPTER, "m8", prior["source"], roll)
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
		"source": {"progress": completed["progress"]},
		"progress": completed["progress"],
		"kind": "m8_settlement_controlled_prefix"
	}


static func _zero(_limit: int) -> int:
	return 0


func _deployment(
	context: Dictionary, opened: Dictionary, draws: Array, inherited_party: Array
) -> bool:
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	if not _expect(
		(
			content["map"]["width"] == 24
			and content["map"]["height"] == 27
			and content["slots"].size() == 8
			and battle.commander_id == 9
		),
		"24x27 map, eight slots and native default commander9"
	):
		return false
	var next_temporary: int = 95
	var occupied: Dictionary = {}
	var expected_draws: Array[int] = []
	var hidden: int = 0
	var friends: int = 0
	for index: int in range(RAW.size()):
		var row: Array = RAW[index]
		var slot: int = row[10]
		var formal: bool = slot >= 0 and slot < context["party"].size()
		var identity: int = (
			context["party"][slot] if formal else (next_temporary if slot >= 0 else row[0])
		)
		if slot >= 0 and not formal:
			next_temporary += 1
		var spawn: Dictionary = content["spawns"][index]
		var actor: Dictionary = battle.unit(identity)
		if row[6] == 1:
			expected_draws.append(3)
		var point: Vector2i
		if index < 25:
			point = Vector2i(row[9][0], row[9][1])
		else:
			var region: Array = row[9][0]
			var candidates: Array[Vector2i] = []
			for x: int in range(24):
				for y: int in range(27):
					var cell := Vector2i(x, y)
					if (
						not occupied.has(cell)
						and x >= region[0]
						and x <= region[2]
						and y >= region[1]
						and y <= region[3]
					):
						candidates.append(cell)
			if not _expect(
				_ints(spawn["deploymentRegions"][0]) == _ints(region) and not candidates.is_empty(),
				"Native inclusive region is retained at record%d" % index
			):
				return false
			expected_draws.append(candidates.size())
			point = candidates[0]
		occupied[point] = true
		if row[3] != 0:
			expected_draws.append_array([4, 3, 3, 3, 3, 6, 3, 1])
		if not _expect(
			(
				actor["deploymentIndex"] == index
				and spawn["deploymentIndex"] == index
				and actor["sourceId"] == (identity if formal else row[0])
				and actor["classId"] == (context["classes"][slot] if formal else row[1])
				and actor["faction"] == row[3]
				and actor["visible"] == (row[4] == 0)
				and actor["policy"] == (0 if row[3] == 0 else row[5])
				and Vector2i(actor["x"], actor["y"]) == point
				and _ints(spawn["itemChoices"]) == _ints(row[7])
				and spawn["randomEquipment"] == (row[6] == 1)
			),
			(
				"Original record%d retains order, binding, class, visibility, policy, items and cell"
				% index
			)
		):
			return false
		if (
			slot >= 0
			and not _expect(
				content["slots"][slot] == identity and actor["formal"] == formal,
				"Empty slots6/7 are distinct95/96, not formal source6/7"
			)
		):
			return false
		if not _expect(
			(
				ResourceLoader.exists(actor["sprite"])
				and content["interface"]["portraitByUnitId"].has(str(identity))
			),
			"Each actual unit binds map and portrait resources"
		):
			return false
		if not actor["visible"]:
			hidden += 1
		if actor["faction"] == 1:
			friends += 1
		if formal:
			for saved: Dictionary in inherited_party:
				if saved["id"] != identity:
					continue
				for key: String in [
					"level",
					"experience",
					"proficiency",
					"attributes",
					"inventory",
					"equippedInstanceId"
				]:
					if not _expect(
						(
							JSON.parse_string(JSON.stringify(actor[key]))
							== JSON.parse_string(JSON.stringify(saved[key]))
						),
						"Inherited training and held items survive m12 prototype: " + key
					):
						return false
	return _expect(
		hidden == 16 and friends == 6 and draws == expected_draws,
		"Six allies/16 hidden; ordered equipment/position/growth RNG, no chest pre-draws"
	)


func _cold(opened: Dictionary, name: String) -> bool:
	var battle: RefCounted = opened["battle"]
	var store := Store.new(opened["content"], _owned.path_join(name + ".json"))
	if not _expect(store.write(battle)["ok"], "Write actual record to isolated owned directory"):
		return false
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	record["state"]["units"].reverse()
	var before: Dictionary = record.duplicate(true)
	_draws.clear()
	var restored: Dictionary = store.decode(record, _roll)
	var read: Dictionary = store.read()
	return _expect(
		(
			restored["ok"]
			and read["ok"]
			and _draws.is_empty()
			and record == before
			and restored["battle"].snapshot() == battle.snapshot()
			and read["battle"].snapshot() == battle.snapshot()
		),
		"Actual Store JSON cold read preserves units/items/order and decode draws zero RNG"
	)


func _roll(limit: int) -> int:
	_draws.append(limit)
	return 0


func _ints(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _cleanup() -> void:
	if _owned.is_empty():
		return
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		_cleanup()
		quit(1)
	return condition
