extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M6 = preload("res://tests/test_m6_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Independent parser: temp/m11/p11-oracle.json; raw record24 remains11,13.
const CONTEXTS: Array[Dictionary] = [
	{
		"route": 0,
		"step": 8,
		"party": [0, 9, 6, 7, 3, 8, 2, 4],
		"classes": [0, 4, 20, 12, 16, 12, 8, 8],
		"next": 15
	},
	{
		"route": 1,
		"step": 5,
		"party": [0, 9, 6, 1, 5, 4],
		"classes": [0, 4, 20, 4, 16, 8],
		"next": 5
	},
	{
		"route": 2,
		"step": 5,
		"party": [0, 9, 3, 8, 2, 4],
		"classes": [0, 4, 16, 12, 8, 8],
		"next": 7
	},
	{
		"route": 3,
		"step": 8,
		"party": [0, 9, 3, 7, 6, 1, 5, 4],
		"classes": [0, 4, 16, 12, 20, 4, 16, 8],
		"next": 15
	}
]
# source,class,level,faction,flags,policy,equipment,items,drop,cell/regions,slot.
const RAW: Array = [
	[35, 16, 1, 2, 0, 2, 0, [19, 0, 0], 0, [17, 3], -1],
	[30, 16, 1, 2, 0, 2, 0, [14, 0, 0], 0, [5, 3], -1],
	[34, 8, 1, 2, 0, 2, 0, [27, 0, 0], 0, [12, 2], -1],
	[32, 8, 1, 2, 0, 2, 0, [24, 0, 0], 0, [10, 2], -1],
	[33, 5, 1, 2, 0, 2, 0, [54, 45, 0], 0, [12, 1], -1],
	[31, 5, 1, 2, 0, 2, 0, [53, 41, 0], 0, [10, 1], -1],
	[47, 12, 1, 2, 1, 2, 0, [0, 44, 0], 51, [17, 9], -1],
	[44, 12, 1, 2, 1, 2, 0, [0, 42, 0], 50, [5, 9], -1],
	[36, 24, 1, 2, 0, 2, 0, [2, 44, 0], 0, [10, 7], -1],
	[41, 4, 1, 2, 0, 2, 0, [53, 0, 0], 0, [12, 5], -1],
	[40, 5, 1, 2, 0, 2, 0, [48, 0, 0], 0, [10, 5], -1],
	[88, 17, 1, 2, 0, 2, 0, [19, 65, 81], 0, [11, 1], -1],
	[49, 29, 1, 2, 1, 2, 0, [29, 65, 0], 0, [18, 10], -1],
	[48, 29, 1, 2, 1, 2, 0, [29, 65, 0], 0, [17, 10], -1],
	[45, 28, 1, 2, 1, 2, 0, [29, 0, 0], 66, [4, 10], -1],
	[46, 28, 1, 2, 1, 2, 0, [29, 65, 0], 0, [5, 10], -1],
	[42, 16, 1, 2, 0, 2, 0, [14, 0, 0], 0, [13, 7], -1],
	[43, 16, 1, 2, 0, 2, 0, [19, 0, 0], 0, [11, 8], -1],
	[39, 16, 1, 2, 0, 2, 0, [14, 0, 0], 0, [9, 7], -1],
	[55, 20, 1, 2, 1, 0, 1, [31, 38, 39], 0, [16, 13], -1],
	[51, 21, 1, 2, 0, 0, 0, [31, 0, 0], 0, [9, 14], -1],
	[52, 21, 1, 2, 0, 0, 0, [31, 0, 0], 0, [8, 16], -1],
	[54, 8, 1, 2, 0, 0, 0, [21, 0, 0], 0, [12, 15], -1],
	[53, 8, 1, 2, 0, 0, 0, [21, 0, 0], 0, [10, 16], -1],
	[50, 9, 1, 2, 0, 0, 0, [21, 0, 0], 0, [11, 13], -1],
	[4, 8, 1, 0, 0, 32, 1, [25, 22, 0], 0, [13, 22], 4],
	[3, 16, 1, 0, 0, 32, 1, [17, 14, 0], 0, [9, 22], 3],
	[1, 5, 1, 0, 0, 32, 0, [53, 48, 0], 0, [10, 23], 1],
	[2, 8, 1, 0, 0, 32, 1, [28, 21, 25], 0, [12, 23], 2],
	[18, 5, 1, 1, 0, 0, 0, [53, 40, 0], 0, [11, 22], -1],
	[17, 9, 1, 1, 0, 0, 1, [25, 1, 22], 0, [12, 21], -1],
	[19, 9, 1, 1, 0, 0, 1, [25, 1, 5], 0, [10, 21], -1],
	[14, 21, 1, 1, 0, 0, 1, [33, 38, 31], 0, [12, 19], -1],
	[12, 21, 1, 1, 0, 0, 1, [33, 34, 31], 0, [10, 19], -1],
	[7, 12, 1, 0, 0, 32, 0, [43, 0, 0], 0, [11, 19], 7],
	[15, 17, 1, 1, 0, 0, 1, [15, 3, 17], 0, [13, 19], -1],
	[16, 17, 1, 1, 0, 0, 1, [17, 2, 16], 0, [13, 20], -1],
	[10, 17, 1, 1, 0, 0, 1, [17, 1, 10], 0, [9, 20], -1],
	[11, 17, 1, 1, 0, 0, 1, [15, 3, 17], 0, [9, 19], -1],
	[6, 20, 1, 0, 0, 32, 0, [34, 0, 0], 0, [12, 20], 6],
	[37, 24, 1, 2, 0, 2, 0, [2, 44, 0], 0, [12, 7], -1],
	[38, 13, 1, 2, 0, 2, 0, [49, 0, 0], 0, [11, 6], -1],
	[0, 1, 1, 0, 0, 32, 0, [0, 0, 0], 0, [11, 24], 0],
	[5, 16, 10, 0, 0, 32, 0, [19, 0, 0], 0, [10, 20], 5],
	[13, 17, 1, 1, 0, 0, 1, [15, 1, 27], 0, [11, 18], -1],
	[114, 16, 1, 2, 1, 0, 0, [19, 0, 0], 0, [19, 15], -1],
	[115, 16, 1, 2, 1, 0, 0, [15, 0, 0], 0, [3, 15], -1],
	[58, 20, 1, 2, 1, 0, 0, [35, 0, 0], 0, [[5, 15, 6, 16]], -1],
	[59, 20, 1, 2, 1, 0, 0, [34, 0, 0], 0, [[5, 13, 6, 14]], -1],
	[60, 21, 1, 2, 0, 0, 0, [31, 0, 0], 0, [[16, 13, 17, 14]], -1],
	[63, 20, 1, 2, 1, 0, 0, [36, 0, 0], 0, [[18, 15, 19, 16]], -1],
	[62, 24, 1, 2, 1, 0, 1, [8, 7, 3], 48, [[16, 15, 17, 16]], -1],
	[61, 25, 1, 2, 1, 0, 0, [5, 45, 0], 0, [[18, 13, 19, 14]], -1],
	[56, 25, 1, 2, 1, 0, 0, [1, 67, 49], 0, [[3, 13, 4, 14]], -1],
	[57, 24, 1, 2, 1, 0, 0, [4, 0, 0], 40, [[3, 15, 4, 16]], -1]
]
var _owned: String = ""
var _draws: Array[int] = []


func _initialize() -> void:
	_owned = "user://m11_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Fresh owned m11 directory required")
		return
	for context: Dictionary in _contexts():
		if not _context(context):
			_cleanup()
			return
	_cleanup()
	print(
		(
			"PASS m11 content route%d: 55 records,slots,training,random regions,cold JSON"
			% _contexts()[0]["route"]
		)
	)
	quit(0)


# Each explicit test entry executes one complete context within the engine deadline.
func _contexts() -> Array[Dictionary]:
	return [CONTEXTS[0]]


# All four entries execute actual m6 win+settlement. M6.prepare uses controlled
# earlier prefixes for routes0/1/3; route3 includes unavailable node12.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	var prior: Dictionary = M6.prepare(M6.CONTEXTS[int(context["route"])], roll)
	if not prior["ok"]:
		return prior
	var opened: Dictionary = Session.new().open(CHAPTER, "m6", prior["source"], roll)
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
		"kind": "m6_settlement_controlled_prefix" if context["route"] != 2 else "reachable_world",
		"source": {"progress": completed["progress"]},
		"progress": completed["progress"]
	}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare m6 settlement: " + str(prepared.get("error"))):
		return false
	var source: Dictionary = JSON.parse_string(JSON.stringify(prepared["source"]))
	var original: Dictionary = source.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m11", source, _roll)
	if not _expect(opened["ok"], "Open actual m11: " + str(opened.get("error"))):
		return false
	var draws: Array = _draws.duplicate()
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	if (
		not _expect(source == original, "Session leaves source unchanged")
		or not _deployment(context, content, battle, draws)
	):
		return false
	var reversed: Dictionary = source.duplicate(true)
	reversed["progress"]["party"].reverse()
	_draws.clear()
	var again: Dictionary = Session.new().open(CHAPTER, "m11", reversed, _roll)
	if not _expect(
		again["ok"] and again["battle"].snapshot() == battle.snapshot() and _draws == draws,
		"Party array reversal preserves native slots/random order/results"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route%d.json" % context["route"]))
	if not _expect(store.write(battle)["ok"], "Write actual Store record to owned directory"):
		return false
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	record["state"]["units"].reverse()
	var before: Dictionary = record.duplicate(true)
	_draws.clear()
	var cold: Dictionary = store.decode(record, _roll)
	if not _expect(
		(
			cold["ok"]
			and _draws.is_empty()
			and record == before
			and cold["battle"].snapshot() == battle.snapshot()
		),
		"Actual JSON cold decode preserves all sampled results without RNG or input mutation"
	):
		return false
	var encoded: Dictionary = store.encode(cold["battle"])
	var canonical: Dictionary = store.encode(battle)
	if not _expect(
		encoded["ok"] and canonical["ok"] and encoded["record"] == canonical["record"],
		"Cold reencode equals whole actual record"
	):
		return false
	# Alter a real inherited formal member; p11 raw slot5 level10 must not overwrite it.
	var trained: Dictionary = source.duplicate(true)
	var saved: Dictionary = {}
	for actor: Dictionary in trained["progress"]["party"]:
		if actor["id"] == context["party"][5]:
			actor["level"] = 5
			actor["experience"] = 37
			actor["attributes"]["strength"] += 3
			if not actor["inventory"].is_empty():
				actor["inventory"][0]["durability"] = 1
			saved = actor.duplicate(true)
	var grown: Dictionary = Session.new().open(CHAPTER, "m11", trained, _roll)
	if not _expect(grown["ok"], "Open trained inherited source"):
		return false
	var actual: Dictionary = grown["battle"].unit(context["party"][5])
	var actual_training: Dictionary = {
		"level": actual["level"],
		"experience": actual["experience"],
		"classId": actual["classId"],
		"attributes": actual["attributes"],
		"inventory": actual["inventory"]
	}
	var saved_training: Dictionary = {
		"level": saved["level"],
		"experience": saved["experience"],
		"classId": saved["classId"],
		"attributes": saved["attributes"],
		"inventory": saved["inventory"]
	}
	# The input was parsed JSON (float protocol numbers); Session restores ints.
	# Compare every training field in the same JSON domain, preserving all values.
	actual_training = JSON.parse_string(JSON.stringify(actual_training))
	saved_training = JSON.parse_string(JSON.stringify(saved_training))
	if not _expect(
		actual_training == saved_training,
		"Current training/items/class survive raw promoted-slot prototypes"
	):
		return false

	if int(context["route"]) == 0 and not _high_regions(source):
		return false
	print(
		"PASS m11 content route%d step%d %s" % [context["route"], context["step"], prepared["kind"]]
	)
	return true


func _deployment(
	context: Dictionary, content: Dictionary, battle: RefCounted, draws: Array
) -> bool:
	if not _expect(
		(
			content["map"]["width"] == 23
			and content["map"]["height"] == 25
			and content["spawns"].size() == 55
			and battle.snapshot()["units"].size() == 55
			and content["slots"].size() == 8
			and _ints(content["optionalIds"]) == [58, 59, 60, 63, 62, 61, 56, 57]
			and battle.commander_id == 9
		),
		"23x25,55 records,eight slots/eight regional units,default commander9"
	):
		return false
	var temporary: Dictionary = {}
	var next_id: int = 95
	for row: Array in RAW:
		var slot: int = row[10]
		if slot >= context["party"].size():
			temporary[slot] = next_id
			next_id += 1
	var occupied: Dictionary = {}
	var sources: Dictionary = {}
	var expected_draws: Array[int] = []
	var regions: int = 0
	var equipment: int = 0
	for index: int in range(RAW.size()):
		var raw: Array = RAW[index]
		var spawn: Dictionary = content["spawns"][index]
		var slot: int = raw[10]
		var inherited: bool = slot >= 0 and slot < context["party"].size()
		var identity: int = (
			context["party"][slot] if inherited else (temporary[slot] if slot >= 0 else raw[0])
		)
		var actor: Dictionary = battle.unit(identity)
		if not _expect(not sources.has(raw[0]), "Original source IDs are unique"):
			return false
		sources[raw[0]] = true
		if raw[6] == 1:
			equipment += 1
			expected_draws.append(3)
		var point: Vector2i
		if index < 47:
			point = Vector2i(11, 12) if raw[0] == 50 else _cell(raw[9])
			if not _expect(
				_cell(spawn["position"]) == point,
				"Only50 has explicit final-business-cell normalization"
			):
				return false
		else:
			regions += 1
			var rectangle: Array = raw[9][0]
			var candidates: Array[Vector2i] = []
			for x: int in range(23):
				for y: int in range(25):
					var cell := Vector2i(x, y)
					if (
						not occupied.has(cell)
						and x >= rectangle[0]
						and x <= rectangle[2]
						and y >= rectangle[1]
						and y <= rectangle[3]
					):
						candidates.append(cell)
			if not _expect(
				(
					not candidates.is_empty()
					and _ints(spawn["deploymentRegions"][0]) == _ints(raw[9][0])
				),
				"Original inclusive2x2 region stays available"
			):
				return false
			expected_draws.append(candidates.size())
			point = candidates[0]
		occupied[point] = true
		if raw[3] != 0:
			expected_draws.append_array([4, 3, 3, 3, 3, 6, 3, 1])
		if not _expect(
			(
				spawn["deploymentIndex"] == index
				and actor["deploymentIndex"] == index
				and actor["sourceId"] == (identity if inherited else raw[0])
				and actor["faction"] == raw[3]
				and actor["classId"] == (context["classes"][slot] if inherited else raw[1])
				and Vector2i(actor["x"], actor["y"]) == point
				and actor["visible"] == (raw[4] == 0)
				and actor["policy"] == (0 if raw[3] == 0 else raw[5])
				and int(spawn["level"]) == raw[2]
				and _ints(spawn["itemChoices"]) == _ints(raw[7])
				and spawn["randomEquipment"] == (raw[6] == 1)
			),
			"Record%d preserves source/order/class/flags/items/random position" % index
		):
			return false
		if (
			slot >= 0
			and not _expect(
				content["slots"][slot] == identity and actor["formal"] == inherited,
				"Slots follow formal order; empty7 then6 become95class12/96class20"
			)
		):
			return false
		if not _expect(
			(
				ResourceLoader.exists(actor["sprite"])
				and content["interface"]["portraitByUnitId"].has(str(identity))
			),
			"Every actual unit binds real sprite and portrait"
		):
			return false
		if not inherited:
			var expected_items: Array[int] = []
			for choice: int in range(3):
				if raw[7][choice] > 0 and (raw[6] == 0 or choice == 0):
					expected_items.append(raw[7][choice])
			if raw[8] > 0:
				expected_items.append(raw[8])
			# Original native constructor moves the first equipable spell ahead of staff.
			# Evidence: temp/m11/native-contexts/m11-route-0/units.json, IDs33/31/18.
			if int(raw[0]) in [33, 31, 18]:
				expected_items.reverse()
			var actual_items: Array[int] = []
			for item: Dictionary in actor["inventory"]:
				actual_items.append(int(item["templateId"]))
			if not _expect(
				actual_items == expected_items, "Record%d actual initial inventory/drop" % index
			):
				return false
			if (
				int(raw[0]) in [33, 31, 18]
				and not _expect(
					actor["equippedInstanceId"] == actor["inventory"][0]["id"],
					"Original constructor equips the spell moved ahead of its staff"
				)
			):
				return false
	var boss: Dictionary = battle.unit(88)
	var profile: Dictionary = content["_library"]["profiles"][content["profiles"][88]]
	return _expect(
		(
			equipment == 14
			and regions == 8
			and expected_draws == draws
			and boss["classId"] == 17
			and profile["portrait"]["portraitId"] == 19
		),
		"14 equipment draws/eight actual candidate limits retain source order; boss88 portrait19/class17"
	)


func _high_regions(source: Dictionary) -> bool:
	var high: Callable = func(limit: int) -> int: return limit - 1
	var opened: Dictionary = Session.new().open(CHAPTER, "m11", source, high)
	if not _expect(opened["ok"], "Initialize maximum-choice original regions"):
		return false
	var occupied: Dictionary = {}
	for index: int in range(RAW.size()):
		var raw: Array = RAW[index]
		var point: Vector2i
		if index < 47:
			point = Vector2i(11, 12) if raw[0] == 50 else _cell(raw[9])
		else:
			var rectangle: Array = raw[9][0]
			var candidates: Array[Vector2i] = []
			for x: int in range(23):
				for y: int in range(25):
					var cell := Vector2i(x, y)
					if (
						not occupied.has(cell)
						and x >= rectangle[0]
						and x <= rectangle[2]
						and y >= rectangle[1]
						and y <= rectangle[3]
					):
						candidates.append(cell)
			if not _expect(
				not candidates.is_empty(), "Maximum region choice has a real unoccupied candidate"
			):
				return false
			point = candidates[-1]
			var actor: Dictionary = opened["battle"].unit(raw[0])
			if not _expect(
				Vector2i(actor["x"], actor["y"]) == point,
				"Upper inclusive bounds and previously reserved cells determine last legal candidate"
			):
				return false
		occupied[point] = true
	return true


func _roll(limit: int) -> int:
	_draws.append(limit)
	return 0


func _ints(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _cell(point: Array) -> Vector2i:
	return Vector2i(int(point[0]), int(point[1]))


func _cleanup() -> void:
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
