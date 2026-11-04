extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const ContentProjection = preload("res://app/chapter_projection.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M4 = preload("res://tests/test_m4_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Independent oracle: temp/m3-m7/deployments/p5.json and m5-route-*.json.
const CONTEXTS: Array[Dictionary] = [
	{
		"route": 0,
		"step": 6,
		"party": [0, 9, 6, 7, 3, 8],
		"classes": [0, 4, 20, 12, 16, 12],
		"next": 6
	},
	{
		"route": 1,
		"step": 6,
		"party": [0, 9, 6, 1, 5, 4],
		"classes": [0, 4, 20, 4, 16, 8],
		"next": 4
	},
	{"route": 2, "step": 3, "party": [0, 9, 3, 8], "classes": [0, 4, 16, 12], "next": 6},
	{"route": 4, "step": 1, "party": [0, 9], "classes": [0, 4]},
	{"route": 5, "step": 1, "party": [0, 9], "classes": [0, 4]},
	{"route": 7, "step": 3, "party": [0, 9, 5, 4], "classes": [0, 4, 16, 8], "next": 4}
]
# [source, class, level, faction, flags, native policy, equipment mode, items, drop, cell/regions]
const RAW: Array = [
	[1, 4, 0, 0, 1, 32, 0, [53, 0, 0], 0, [21, 6]],
	[2, 8, 0, 0, 1, 32, 0, [22, 60, 0], 0, [20, 6]],
	[4, 8, 0, 0, 1, 32, 0, [22, 0, 0], 0, [20, 8]],
	[3, 16, 0, 0, 1, 32, 0, [17, 0, 0], 0, [20, 7]],
	[0, 0, 0, 0, 1, 32, 0, [0, 0, 0], 0, [21, 7]],
	[61, 20, 0, 2, 1, 0, 1, [32, 31, 34], 0, [18, 2]],
	[60, 20, 0, 2, 1, 0, 1, [34, 31, 33], 0, [19, 1]],
	[18, 4, 0, 1, 0, 0, 0, [54, 53, 0], 0, [15, 8]],
	[10, 8, 0, 1, 0, 0, 0, [22, 0, 0], 0, [13, 5]],
	[17, 8, 0, 1, 0, 0, 0, [22, 0, 0], 0, [13, 11]],
	[16, 8, 0, 1, 0, 0, 0, [23, 0, 0], 0, [14, 10]],
	[11, 8, 0, 1, 0, 0, 0, [23, 0, 0], 0, [14, 6]],
	[84, 25, 0, 2, 0, 2, 0, [1, 44, 65], 76, [1, 8]],
	[53, 16, 0, 2, 0, 2, 1, [16, 1, 11], 0, [1, 9]],
	[52, 16, 0, 2, 0, 2, 1, [13, 14, 19], 0, [1, 7]],
	[51, 8, 0, 2, 0, 0, 1, [22, 25, 21], 0, [7, 10]],
	[50, 9, 0, 2, 0, 2, 1, [21, 1, 21], 0, [6, 7]],
	[49, 8, 0, 2, 0, 0, 1, [22, 21, 23], 0, [7, 6]],
	[48, 8, 0, 2, 0, 0, 1, [21, 23, 27], 0, [8, 7]],
	[47, 9, 0, 2, 0, 2, 1, [21, 1, 1], 0, [6, 9]],
	[46, 8, 0, 2, 0, 0, 0, [0, 0, 0], 25, [8, 9]],
	[45, 8, 0, 2, 0, 0, 0, [0, 0, 0], 23, [8, 8]],
	[44, 24, 0, 2, 0, 2, 0, [44, 1, 0], 60, [6, 5]],
	[2, 8, 0, 0, 0, 0, 0, [24, 23, 0], 0, [14, 8]],
	[15, 8, 0, 1, 0, 0, 0, [22, 0, 0], 0, [13, 9]],
	[46, 24, 5, 2, 0, 2, 0, [1, 42, 0], 0, [6, 11]],
	[12, 8, 2, 1, 0, 0, 0, [22, 0, 0], 0, [13, 7]],
	[42, 13, 1, 2, 0, 2, 0, [45, 0, 0], 65, [6, 8]],
	[5, 16, 10, 0, 1, 32, 0, [16, 13, 0], 0, [21, 8]],
	[54, 16, 0, 2, 0, 2, 1, [13, 1, 8], 0, [0, 8]],
	[66, 16, 0, 2, 1, 0, 1, [13, 17, 15], 13, [[16, 6, 19, 7]]],
	[64, 16, 0, 2, 1, 0, 1, [16, 15, 13], 1, [[17, 10, 19, 11]]],
	[69, 16, 0, 2, 1, 0, 1, [17, 16, 13], 0, [[10, 0, 12, 1]]],
	[67, 16, 0, 2, 1, 0, 1, [13, 19, 17], 0, [[13, 2, 15, 3]]],
	[65, 16, 0, 2, 1, 0, 1, [16, 17, 13], 21, [[17, 8, 19, 9]]],
	[68, 16, 0, 2, 1, 0, 1, [16, 15, 13], 0, [[16, 4, 19, 5]]],
]
var _owned: String = ""
var _draws: Array[int] = []


func _initialize() -> void:
	_run_contexts(CONTEXTS.slice(0, 2))


func _run_contexts(contexts: Array) -> void:
	_owned = "user://m5_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim a fresh owned m5 content directory")
		return
	for context: Dictionary in contexts:
		if not _context(context):
			_cleanup()
			return
	_cleanup()
	print("PASS actual m5 content: selected contexts, records, source46 aliases and JSON restore")
	quit(0)


# dr2 uses real m0 choice2 -> m3 choice2 -> m4 fixed2. dr4 uses actual
# m0 choice4; dr5 is a controlled projection of its identical completed prefix,
# never an independently reachable m0 world record. Other prefixes include
# unavailable maps, so use actual m5 templates as controlled domain fixtures.
# These preparations do not claim natural full-chapter combat.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	var progress: Dictionary
	if context["route"] == 2:
		var previous: Dictionary = M4.prepare(M4.CONTEXTS[2], roll)
		if not previous["ok"]:
			return previous
		var opened: Dictionary = Session.new().open(
			CHAPTER, "m4", {"progress": previous["progress"]}, roll
		)
		if not opened["ok"]:
			return opened
		var won: Dictionary = opened["battle"].win_with_assistance()
		if not won["ok"]:
			return won
		var completed: Dictionary = opened["battle"].complete_victory(2)
		if not completed["ok"]:
			return completed
		progress = completed["progress"]
	elif context["route"] in [4, 5]:
		var opened: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, roll)
		if not opened["ok"]:
			return opened
		var won: Dictionary = opened["battle"].win_with_assistance()
		if not won["ok"]:
			return won
		var completed: Dictionary = opened["battle"].complete_victory(4)
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
			"m5",
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
		for identity: int in context["party"]:
			var member: Dictionary = template.unit(identity)
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
	progress["warehouse"] = [
		{"id": "m5 inherited opaque warehouse", "templateId": 60, "durability": 2}
	]
	return {"ok": true, "progress": progress}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare m5 context: " + str(prepared.get("error"))):
		return false
	var progress: Dictionary = JSON.parse_string(JSON.stringify(prepared["progress"]))
	var before: Dictionary = progress.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m5", {"progress": progress}, _roll)
	if not _expect(opened["ok"], "Open actual m5: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var draws: Array = _draws.duplicate()
	if not _expect(progress == before, "Opening m5 leaves inherited progress unchanged"):
		return false
	if not _deployment(context, content, battle) or not _source46(content, battle):
		return false
	var reversed: Dictionary = progress.duplicate(true)
	reversed["party"].reverse()
	_draws.clear()
	var reordered: Dictionary = Session.new().open(CHAPTER, "m5", {"progress": reversed}, _roll)
	if not _expect(
		(
			reordered["ok"]
			and reordered["battle"].snapshot() == battle.snapshot()
			and reordered["content"]["unitOrder"] == content["unitOrder"]
			and _draws == draws
		),
		"Party array reversal preserves m5 slots, random calls and native traversal"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	var encoded: Dictionary = store.encode(battle)
	if not _expect(
		encoded["ok"] and store.write(battle)["ok"], "Write m5 only in its owned directory"
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
			and store.read()["ok"]
		),
		"JSON restores both source46 actors and generated results without initialization draws"
	):
		return false
	if not _source46(restored["content"], restored["battle"]):
		return false
	print("PASS actual m5 content dr%d step%d" % [context["route"], context["step"]])
	return true


func _deployment(context: Dictionary, content: Dictionary, battle: RefCounted) -> bool:
	if not _expect(
		(
			content["spawns"].size() == 36
			and battle.snapshot()["units"].size() == 36
			and content["map"]["width"] == 23
			and content["map"]["height"] == 20
			and content["slots"].size() == 6
			and content["optionalIds"].size() == 6
			and battle.unit(2)["formal"]
			and battle.unit(2)["classId"] == 8
			and battle.unit(2)["visible"]
			and Vector2i(battle.unit(2)["x"], battle.unit(2)["y"]) == Vector2i(14, 8)
			and content["story"]["battleNumber"] == context["step"] + 1
		),
		"m5 is 23x20 with all36 records, six slots/random records and direct recruit2"
	):
		return false
	var temporary: Dictionary = {}
	var next_identity: int = 95
	for slot: int in [1, 2, 4, 3, 0, 5]:
		if slot >= context["party"].size():
			temporary[slot] = next_identity
			next_identity += 1
	var expected: Array[int] = [9, 0]
	for identity: int in context["party"].slice(2):
		expected.append(identity)
	var occupied: Dictionary = {}
	var cursor: int = 0
	for index: int in range(RAW.size()):
		var raw: Array = RAW[index]
		var spawn: Dictionary = content["spawns"][index]
		var slot: int = int(spawn.get("deploymentSlot", -1))
		var identity: int = 70 if index == 25 else raw[0]
		if slot >= 0:
			identity = context["party"][slot] if slot < context["party"].size() else temporary[slot]
		var actor: Dictionary = battle.unit(identity)
		if raw[6] == 1:
			if not _expect(
				_draws[cursor] == 3, "Equipment is drawn before position/growth at record%d" % index
			):
				return false
			cursor += 1
		if not _expect(
			(
				spawn["id"] == identity
				and (
					spawn["sourceId"]
					== (identity if slot >= 0 and slot < context["party"].size() else raw[0])
				)
				and spawn["faction"] == raw[3]
				and spawn["flags"] == raw[4]
				and spawn["policy"] == (0 if raw[3] == 0 else raw[5])
				and spawn["level"] == maxi(1, raw[2])
				and _ints(spawn["itemChoices"]) == _ints(raw[7])
				and spawn["dropTemplateId"] == raw[8]
			),
			"Preserve native m5 record%d source/order/level/items/policy" % index
		):
			return false
		if slot >= 0:
			var formal: bool = slot < context["party"].size()
			if not _expect(
				(
					content["slots"][slot] == identity
					and actor["formal"] == formal
					and actor["classId"] == (context["classes"][slot] if formal else raw[1])
					and actor["policy"] == 0
					and not actor["visible"]
				),
				"Slot%d binds by recruit order/current class" % slot
			):
				return false
		elif not _expect(actor["classId"] == raw[1], "Direct actor class at record%d" % index):
			return false
		if index >= 30:
			var regions: Array = spawn.get("deploymentRegions", [])
			if not _expect(
				regions.size() == 1 and _ints(regions[0]) == _ints(raw[9][0]),
				"m5 keeps one native rectangle per cavalry record"
			):
				return false
			var candidates: Array[Vector2i] = []
			var region: Array = raw[9][0]
			for x: int in range(region[0], region[2] + 1):
				for y: int in range(region[1], region[3] + 1):
					var cell := Vector2i(x, y)
					if not occupied.has(cell) and cell not in candidates:
						candidates.append(cell)
			if not _expect(
				(
					_draws[cursor] == candidates.size()
					and Vector2i(actor["x"], actor["y"]) == candidates[0]
				),
				(
					"Inclusive four borders, deduplicated free candidates and native x/y order at record%d"
					% index
				)
			):
				return false
			cursor += 1
		elif not _expect(
			(
				_cell(spawn["position"]) == _cell(raw[9])
				and Vector2i(actor["x"], actor["y"]) == _cell(raw[9])
			),
			"Fixed original position at record%d" % index
		):
			return false
		var point := Vector2i(actor["x"], actor["y"])
		if not _expect(
			not occupied.has(point), "Hidden and visible initial actors reserve distinct cells"
		):
			return false
		occupied[point] = true
		if raw[3] != 0:
			for noise: int in [4, 3, 3, 3, 3, 6, 3, 1]:
				if not _expect(
					_draws[cursor] == noise, "Native growth draw order at record%d" % index
				):
					return false
				cursor += 1
		if identity not in expected:
			expected.append(identity)
	var actual: Array[int] = []
	for actor: Dictionary in battle.snapshot()["units"]:
		actual.append(int(actor["id"]))
		if not _expect(
			(
				ResourceLoader.exists(actor["sprite"])
				and content["mapAnimations"]["units"].has(str(actor["id"]))
			),
			"Actual m5 map presentation resolves"
		):
			return false
	return _expect(
		(
			actual == expected
			and _ints(content["unitOrder"]) == expected
			and cursor == _draws.size()
			and not battle.snapshot().has("cloneState")
		),
		"m5 native traversal retains36 distinct actors; no births or initialization draws are omitted"
	)


func _source46(content: Dictionary, battle: RefCounted) -> bool:
	# Compare each specified recipe to its own catalog definition, without fixed PNG names.
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHAPTER))
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chapter["library"]))
	var definition: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(chapter["battles"]["m5"])
	)
	for identity: int in [46, 70]:
		var job: int = 8 if identity == 46 else 24
		var recipe: String = "source_46_job_%d_faction_2" % job
		var actor: Dictionary = battle.unit(identity)
		var profile: Dictionary = library["profiles"][recipe]
		if not _expect(
			(
				content["profiles"][identity] == recipe
				and actor["sourceId"] == 46
				and actor["classId"] == job
				and actor["level"] == (1 if identity == 46 else 5)
				and (
					Vector2i(actor["x"], actor["y"])
					== (Vector2i(8, 9) if identity == 46 else Vector2i(6, 11))
				)
				and actor["sprite"] == profile["unit"]["sprite"]
				and (
					content["mapAnimations"]["units"][str(identity)]
					== ContentProjection.relative_resources(
						library["mapAnimationPool"][profile["mapAnimation"]]
					)
				)
			),
			"Actor%d independently binds source46 class/level/cell/map profile" % identity
		):
			return false
		var items: Array[int] = []
		for item: Dictionary in actor["inventory"]:
			items.append(int(item["templateId"]))
		if not _expect(
			items == ([25] if identity == 46 else [1, 42]),
			"Each source46 actor retains its own actual items"
		):
			return false
		for weapon: String in profile["appearances"]:
			var alias: String = "%d:%s" % [identity, weapon]
			if not _expect(
				(
					(
						content["battleArt"]["appearances"][alias]
						== ContentProjection.relative_resources(
							content["_library"]["appearancePool"][profile["appearances"][weapon]]
						)
					)
					and (
						content["battleClips"]["appearances"][alias]
						== profile["motion"][definition["stage"]][weapon]
					)
				),
				"Source46 actor appearance binds its own full frame/offset/weapon definition"
			):
				return false
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
