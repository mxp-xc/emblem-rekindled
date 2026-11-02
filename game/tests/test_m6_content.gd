extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const ContentProjection = preload("res://app/chapter_projection.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M5 = preload("res://tests/test_m5_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Independent oracle: temp/m3-m7/deployments/p6.json and m6-route-*.json.
const CONTEXTS: Array[Dictionary] = [
	{
		"route": 0,
		"step": 7,
		"party": [0, 9, 6, 7, 3, 8, 2],
		"classes": [0, 4, 20, 12, 16, 12, 8],
		"next": 11
	},
	{"route": 1, "step": 4, "party": [0, 9, 6, 1, 5], "classes": [0, 4, 20, 4, 16], "next": 11},
	{"route": 2, "step": 4, "party": [0, 9, 3, 8, 2], "classes": [0, 4, 16, 12, 8], "next": 11},
	{
		"route": 3,
		"step": 7,
		"party": [0, 9, 3, 7, 6, 1, 5],
		"classes": [0, 4, 16, 12, 20, 4, 16],
		"next": 11
	},
	{"route": 4, "step": 2, "party": [0, 9, 2], "classes": [0, 4, 8], "next": 7},
	{"route": 7, "step": 2, "party": [0, 9, 5], "classes": [0, 4, 16], "next": 5}
]
# [source, class, level, faction, flags, native policy, equipment mode, items, drop, cell]
const RAW: Array = [
	[85, 17, 0, 2, 0, 2, 0, [19, 65, 81], 76, [6, 1]],
	[33, 16, 0, 2, 0, 2, 1, [17, 1, 20], 0, [6, 2]],
	[34, 16, 0, 2, 0, 2, 0, [0, 0, 0], 16, [7, 2]],
	[35, 16, 0, 2, 0, 2, 1, [14, 10, 13], 0, [8, 2]],
	[32, 16, 0, 2, 0, 2, 1, [14, 1, 13], 0, [8, 1]],
	[31, 16, 0, 2, 0, 2, 1, [16, 11, 17], 0, [7, 1]],
	[16, 16, 0, 1, 0, 0, 1, [15, 3, 19], 0, [18, 9]],
	[36, 4, 0, 2, 0, 2, 1, [53, 53, 54], 0, [20, 0]],
	[30, 8, 0, 2, 0, 0, 1, [27, 24, 23], 0, [8, 9]],
	[6, 20, 0, 0, 1, 32, 0, [34, 0, 0], 0, [5, 17]],
	[2, 8, 0, 0, 1, 32, 0, [23, 0, 0], 0, [7, 18]],
	[3, 16, 0, 0, 1, 32, 0, [20, 0, 0], 0, [6, 18]],
	[5, 16, 0, 0, 1, 32, 0, [17, 0, 0], 0, [5, 18]],
	[42, 16, 0, 2, 0, 0, 0, [0, 0, 0], 14, [20, 14]],
	[40, 16, 0, 2, 0, 0, 0, [0, 0, 0], 13, [19, 14]],
	[39, 12, 0, 2, 0, 0, 1, [43, 45, 41], 0, [5, 11]],
	[38, 12, 0, 2, 0, 0, 0, [0, 0, 0], 41, [5, 9]],
	[41, 12, 0, 2, 0, 0, 1, [44, 42, 40], 0, [17, 17]],
	[69, 12, 0, 2, 0, 0, 1, [44, 42, 40], 42, [22, 17]],
	[68, 4, 0, 2, 0, 0, 0, [42, 0, 0], 53, [18, 18]],
	[67, 8, 0, 2, 0, 0, 1, [21, 22, 23], 4, [19, 16]],
	[66, 20, 0, 2, 0, 0, 1, [34, 38, 31], 0, [21, 17]],
	[65, 24, 0, 2, 0, 0, 0, [0, 0, 0], 5, [19, 17]],
	[64, 24, 0, 2, 0, 0, 0, [2, 0, 0], 40, [8, 10]],
	[63, 24, 0, 2, 0, 0, 0, [2, 0, 0], 42, [8, 8]],
	[62, 16, 0, 2, 0, 0, 1, [14, 1, 13], 0, [7, 10]],
	[61, 16, 0, 2, 0, 0, 1, [19, 2, 17], 0, [7, 8]],
	[60, 8, 0, 2, 0, 2, 1, [22, 21, 23], 0, [17, 2]],
	[59, 8, 0, 2, 0, 2, 1, [22, 21, 23], 0, [22, 1]],
	[58, 8, 0, 2, 0, 2, 1, [25, 23, 22], 0, [20, 1]],
	[57, 20, 0, 2, 0, 2, 1, [34, 31, 32], 0, [23, 2]],
	[56, 20, 0, 2, 0, 2, 1, [34, 35, 32], 0, [18, 1]],
	[55, 20, 0, 2, 0, 2, 1, [38, 31, 34], 0, [16, 3]],
	[17, 9, 0, 1, 0, 0, 1, [25, 23, 22], 0, [20, 10]],
	[11, 9, 0, 1, 0, 0, 1, [22, 23, 21], 0, [20, 6]],
	[12, 9, 0, 1, 0, 0, 1, [2, 1, 4], 0, [13, 7]],
	[18, 20, 0, 1, 0, 0, 1, [34, 31, 32], 0, [22, 10]],
	[14, 12, 0, 1, 0, 0, 1, [43, 45, 41], 0, [20, 8]],
	[13, 4, 0, 1, 0, 0, 0, [53, 40, 0], 0, [16, 8]],
	[10, 20, 0, 1, 0, 0, 1, [32, 31, 34], 0, [18, 6]],
	[4, 8, 0, 0, 0, 0, 0, [24, 65, 25], 0, [18, 8]],
	[15, 21, 0, 1, 0, 0, 1, [32, 36, 34], 0, [13, 9]],
	[37, 13, 0, 2, 0, 0, 0, [45, 53, 0], 0, [3, 10]],
	[0, 0, 0, 0, 1, 32, 0, [0, 0, 0], 0, [7, 19]],
	[4, 8, 0, 0, 1, 32, 0, [25, 0, 0], 0, [5, 19]],
	[1, 4, 0, 0, 1, 32, 0, [53, 54, 0], 0, [6, 19]],
]
var _owned: String = ""
var _draws: Array[int] = []


func _initialize() -> void:
	_owned = "user://m6_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim a fresh owned m6 content directory")
		return
	for context: Dictionary in CONTEXTS:
		if not _context(context):
			_cleanup()
			return
	_cleanup()
	print("PASS actual m6 content: six contexts, 46 fixed records, seven slots and JSON restore")
	quit(0)


# Only dr2 is a reachable world record: real m0 -> m3 -> m4 -> m5 choice2.
# Other contexts are explicit domain fixtures, including step2. Some prefixes
# contain unregistered m7; no completedBattle or fabricated world record is made.
# reverse_fixture_party exercises unordered inherited input without changing recruit order.
static func prepare(
	context: Dictionary, roll: Callable, reverse_fixture_party: bool = false
) -> Dictionary:
	if context["route"] == 2:
		var previous: Dictionary = M5.prepare(M5.CONTEXTS[2], roll)
		if not previous["ok"]:
			return previous
		var opened: Dictionary = Session.new().open(
			CHAPTER, "m5", {"progress": previous["progress"]}, roll
		)
		if not opened["ok"]:
			return opened
		var won: Dictionary = opened["battle"].win_with_assistance()
		if not won["ok"]:
			return won
		var completed: Dictionary = opened["battle"].complete_victory(2)
		if not completed["ok"]:
			return completed
		var progress: Dictionary = completed["progress"]
		return {
			"ok": true,
			"kind": "reachable_world",
			"source": {"progress": progress},
			"progress": progress
		}
	var party: Array = []
	for index: int in range(context["party"].size()):
		party.append({"id": context["party"][index], "classId": context["classes"][index]})
	var native: Array = context["party"].duplicate()
	native[0] = 9
	native[1] = 0
	var binding: Dictionary = {
		"party": party,
		"partyOrder": native,
		"route": context["route"],
		"worldStep": context["step"]
	}
	var compiled: Dictionary = Content.new().load_chapter(CHAPTER, "m6", binding)
	if not compiled["ok"]:
		return compiled
	# The first initialization supplies legal members from actual m6 profiles.
	# Its neutral RNG is separate from the initialization under test below.
	var neutral: Callable = func(_limit: int) -> int: return 0
	var template: RefCounted = Battle.new(compiled, neutral)
	party.clear()
	for identity: int in context["party"]:
		var member: Dictionary = template.unit(identity)
		member["hp"] = member["maxHp"]
		member["flags"] = 0
		member["policy"] = 0
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
	state["warehouse"] = [
		{"id": "m6 inherited opaque warehouse", "templateId": 60, "durability": 2}
	]
	return {
		"ok": true,
		"kind": "domain_fixture",
		"source": {"snapshot": state},
		"initializationDraws": draws
	}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare m6 context: " + str(prepared.get("error"))):
		return false
	var source: Dictionary = JSON.parse_string(JSON.stringify(prepared["source"]))
	var before: Dictionary = source.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m6", source, _roll)
	if not _expect(opened["ok"], "Open actual m6: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var draws: Array = _draws.duplicate()
	if prepared["kind"] == "domain_fixture":
		if not _expect(draws.is_empty(), "Opening domain snapshot fixture never initializes again"):
			return false
		draws = prepared["initializationDraws"]
	if not _expect(source == before, "Opening m6 leaves its source unchanged"):
		return false
	if not _deployment(context, content, battle, draws) or not _boss(content, battle):
		return false
	var reversed: Dictionary
	if source.has("progress"):
		reversed = source.duplicate(true)
		reversed["progress"]["party"].reverse()
	else:
		var rebuilt: Dictionary = prepare(context, _roll, true)
		if not _expect(
			rebuilt["ok"] and rebuilt["initializationDraws"] == draws,
			"Reversed inherited party preserves fixture initialization draws"
		):
			return false
		reversed = rebuilt["source"]
	_draws.clear()
	var reordered: Dictionary = Session.new().open(CHAPTER, "m6", reversed, _roll)
	if not _expect(
		(
			reordered["ok"]
			and reordered["battle"].snapshot() == battle.snapshot()
			and reordered["content"]["unitOrder"] == content["unitOrder"]
			and _draws == (draws if source.has("progress") else [])
		),
		"Party array reversal preserves m6 slots, initialization RNG and native traversal"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	if not _expect(store.write(battle)["ok"], "Write m6 only in its owned directory"):
		return false
	# Decode the bytes actually written by Store, rather than an encode-only dictionary.
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
			and restored["content"]["unitOrder"] == content["unitOrder"]
			and store.read()["ok"]
		),
		"Actual m6 JSON restores items, slots and native order without initialization RNG"
	):
		return false
	if not _boss(restored["content"], restored["battle"]):
		return false
	print(
		(
			"PASS actual m6 content dr%d step%d (%s)"
			% [context["route"], context["step"], prepared["kind"]]
		)
	)
	return true


func _deployment(
	context: Dictionary, content: Dictionary, battle: RefCounted, draws: Array
) -> bool:
	if not _expect(
		(
			content["spawns"].size() == 46
			and battle.snapshot()["units"].size() == 46
			and content["map"]["width"] == 25
			and content["map"]["height"] == 20
			and content["slots"].size() == 7
			and content["optionalIds"].is_empty()
			and battle.unit(4)["formal"]
			and battle.unit(4)["classId"] == 8
			and battle.unit(4)["visible"]
			and [battle.unit(4)["x"], battle.unit(4)["y"]] == [18, 8]
			and battle.commander_id == 4
			and content["story"]["battleNumber"] == context["step"] + 1
			and content["story"]["routeChoices"].size() == 1
			and content["story"]["routeChoices"][0]["routeIndex"] == context["route"]
			and content["story"]["routeChoices"][0]["nodeId"] == context["next"]
		),
		"m6 keeps 25x20, 46 fixed records, seven slots, recruit4, commander4 and current route"
	):
		return false
	var temporary: Dictionary = {}
	var next_identity: int = 95
	for slot: int in [6, 2, 3, 5, 0, 4, 1]:
		if slot >= context["party"].size():
			temporary[slot] = next_identity
			next_identity += 1
	var expected: Array[int] = [9, 0]
	for identity: int in context["party"].slice(2):
		expected.append(identity)
	var occupied: Dictionary = {}
	var expected_draws: Array[int] = []
	for index: int in range(RAW.size()):
		var raw: Array = RAW[index]
		var spawn: Dictionary = content["spawns"][index]
		var slot: int = int(spawn.get("deploymentSlot", -1))
		var identity: int = raw[0]
		if slot >= 0:
			identity = context["party"][slot] if slot < context["party"].size() else temporary[slot]
		var inherited: bool = slot >= 0 and slot < context["party"].size()
		var actor: Dictionary = battle.unit(identity)
		if raw[6] == 1:
			expected_draws.append(3)
		if raw[3] != 0:
			expected_draws.append_array([4, 3, 3, 3, 3, 6, 3, 1])
		if not _expect(
			(
				spawn["id"] == identity
				and spawn["deploymentIndex"] == index
				and spawn["sourceId"] == (identity if inherited else raw[0])
				and spawn["faction"] == raw[3]
				and actor["faction"] == raw[3]
				and spawn["flags"] == raw[4]
				and actor["flags"] == raw[4]
				and spawn["policy"] == (0 if raw[3] == 0 else raw[5])
				and actor["policy"] == spawn["policy"]
				and spawn["level"] == maxi(1, raw[2])
				and spawn["randomEquipment"] == (raw[6] == 1)
				and _ints(spawn["itemChoices"]) == _ints(raw[7])
				and spawn["dropTemplateId"] == raw[8]
				and actor["sourceId"] == spawn["sourceId"]
				and actor["dropTemplateId"] == raw[8]
				and not spawn.has("deploymentRegions")
				and _cell(spawn["position"]) == _cell(raw[9])
				and Vector2i(actor["x"], actor["y"]) == _cell(raw[9])
				and actor["visible"] == (raw[4] == 0)
			),
			"Preserve native m6 record%d source/order/flags/policy/items/fixed position" % index
		):
			return false
		if not _expect(
			actor["classId"] == (context["classes"][slot] if inherited else raw[1]),
			"m6 current class at record%d" % index
		):
			return false
		if (
			slot >= 0
			and not _expect(
				content["slots"][slot] == identity and actor["formal"] == inherited,
				"m6 slot%d binds formal recruit order or its temporary substitute" % slot
			)
		):
			return false
		if not inherited:
			var items: Array[int] = []
			for choice: int in range(3):
				if raw[7][choice] > 0 and (raw[6] == 0 or choice == 0):
					items.append(raw[7][choice])
			if raw[8] > 0:
				items.append(raw[8])
			var actual_items: Array[int] = []
			for item: Dictionary in actor["inventory"]:
				actual_items.append(int(item["templateId"]))
			if not _expect(
				items == actual_items, "m6 actual initial inventory at record%d" % index
			):
				return false
		var point := _cell(raw[9])
		if not _expect(
			not occupied.has(point), "All m6 hidden and visible records reserve unique cells"
		):
			return false
		occupied[point] = true
		if identity not in expected:
			expected.append(identity)
		if not _expect(
			(
				ResourceLoader.exists(actor["sprite"])
				and content["mapAnimations"]["units"].has(str(identity))
				and content["interface"]["portraitByUnitId"].has(str(identity))
			),
			"Actual m6 map and portrait presentation resolves"
		):
			return false
		var profile: Dictionary = content["_library"]["profiles"][content["profiles"][identity]]
		for weapon: String in profile["appearances"]:
			var alias: String = "%d:%s" % [identity, weapon]
			if not _expect(
				(
					(
						content["battleArt"]["appearances"][alias]
						== ContentProjection.relative_resources(profile["appearances"][weapon])
					)
					and content["battleClips"]["appearances"].has(alias)
				),
				"Every m6 actor resolves the complete declared weapon appearance"
			):
				return false
	var actual: Array[int] = []
	for actor: Dictionary in battle.snapshot()["units"]:
		actual.append(int(actor["id"]))
	return _expect(
		(
			actual == expected
			and _ints(content["unitOrder"]) == expected
			and draws == expected_draws
			and not battle.snapshot().has("cloneState")
		),
		"m6 native order keeps all46 actors; equipment then growth are the only initialization draws"
	)


func _boss(content: Dictionary, battle: RefCounted) -> bool:
	var profile: Dictionary = content["_library"]["profiles"]["source_85_job_17_faction_2"]
	var portrait: Dictionary = profile["portrait"].duplicate(true)
	portrait["texture"] = "unit_portrait_85"
	var actor: Dictionary = battle.unit(85)
	var items: Array[int] = []
	var ring: Dictionary = {}
	for item: Dictionary in actor["inventory"]:
		items.append(int(item["templateId"]))
		if item["templateId"] == 81:
			ring = item
	return _expect(
		(
			actor["sourceId"] == 85
			and actor["classId"] == 17
			and actor["dropTemplateId"] == 76
			and items == [19, 65, 81, 76]
			and ring.get("durability", -1) == 0
			and profile["portrait"]["portraitId"] == 16
			and profile["portrait"]["texture"]["source"] == "portraits_16.png"
			and content["story"]["speakers"]["85"]["portraitId"] == 16
			and (content["interface"]["portraitByUnitId"]["85"] == portrait)
			and (
				content["interface"]["textures"]["unit_portrait_85"]
				== ContentProjection.relative_resources(profile["portrait"]["texture"])
			)
		),
		"Boss85 keeps class17, [19,65,81], drop76, zero durability ring and original portrait16"
	)


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
