extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
const M3 = preload("res://tests/test_m3_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
# Source: temp/m3-m7/deployments/p4.json and m4-route-*.json.
const CONTEXTS: Array[Dictionary] = [
	{"route": 0, "step": 4, "party": [0, 9, 6, 7, 3], "classes": [0, 4, 20, 12, 16], "next": 10},
	{
		"route": 1,
		"step": 7,
		"party": [0, 9, 6, 1, 5, 4, 2],
		"classes": [0, 4, 20, 4, 16, 8, 8],
		"next": 10
	},
	{"route": 2, "step": 2, "party": [0, 9, 3], "classes": [0, 4, 16], "next": 5},
	{"route": 5, "step": 2, "party": [0, 9, 2], "classes": [0, 4, 8], "next": 3},
	{
		"route": 6,
		"step": 7,
		"party": [0, 9, 5, 1, 6, 7, 3],
		"classes": [0, 4, 16, 4, 20, 12, 16],
		"next": 10
	},
	{"route": 7, "step": 4, "party": [0, 9, 5, 4, 2], "classes": [0, 4, 16, 8, 8], "next": 10}
]
# [sourceId, classId, faction, flags, native policy, fixed point or region union]
const RAW: Array = [
	[34, 32, 2, 0, 2, [20, 7]],
	[33, 32, 2, 0, 2, [16, 7]],
	[32, 28, 2, 0, 2, [14, 4]],
	[31, 28, 2, 0, 2, [14, 2]],
	[15, 12, 1, 0, 0, [6, 13]],
	[67, 32, 2, 0, 0, [11, 17]],
	[80, 13, 2, 0, 2, [6, 3]],
	[4, 8, 0, 1, 32, [18, 5]],
	[1, 4, 0, 1, 32, [17, 4]],
	[5, 16, 0, 1, 32, [19, 4]],
	[2, 8, 0, 1, 32, [18, 4]],
	[3, 16, 0, 1, 32, [18, 3]],
	[58, 32, 2, 0, 0, [10, 4]],
	[30, 5, 2, 0, 2, [19, 13]],
	[54, 28, 2, 0, 0, [14, 15]],
	[53, 29, 2, 0, 4, [12, 9]],
	[50, 36, 2, 0, 0, [15, 12]],
	[49, 36, 2, 0, 0, [13, 12]],
	[17, 4, 1, 0, 0, [4, 15]],
	[10, 12, 1, 0, 0, [5, 14]],
	[16, 12, 1, 0, 0, [3, 14]],
	[12, 12, 1, 0, 0, [3, 12]],
	[11, 12, 1, 0, 0, [5, 12]],
	[8, 12, 0, 0, 0, [4, 13]],
	[0, 0, 0, 1, 32, [17, 3]],
	[6, 20, 0, 1, 32, [19, 5]],
	[18, 4, 1, 0, 0, [2, 13]],
	[109, 36, 2, 1, 0, [[0, 9, 10, 20], [4, 17, 8, 18], [16, 18, 20, 19]]],
	[111, 36, 2, 1, 0, [[0, 9, 10, 20], [1, 17, 4, 18], [7, 2, 12, 4]]],
	[115, 36, 2, 1, 0, [[12, 2, 22, 10], [16, 13, 19, 14], [15, 17, 18, 19]]],
	[112, 28, 2, 1, 0, [[0, 9, 8, 20], [7, 10, 9, 12], [12, 3, 14, 4]]],
	[114, 32, 2, 0, 0, [[10, 2, 22, 10], [3, 9, 6, 11]]],
	[110, 32, 2, 1, 0, [[10, 12, 13, 13], [10, 15, 13, 17], [20, 9, 22, 12]]],
	[108, 32, 2, 1, 0, [[0, 9, 10, 20], [15, 8, 21, 10], [14, 10, 21, 12]]],
	[107, 28, 2, 1, 0, [[7, 2, 10, 3], [8, 6, 11, 7], [8, 10, 11, 11]]],
	[113, 28, 2, 0, 0, [[9, 2, 22, 11], [4, 17, 8, 18]]]
]
var _owned: String = ""
var _draws: Array[int] = []


func _initialize() -> void:
	_run_contexts(CONTEXTS.slice(0, 2))


func _run_contexts(contexts: Array) -> void:
	_owned = "user://m4_content_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Cannot claim a fresh owned m4 content directory")
		return
	for context: Dictionary in contexts:
		if not _context(context):
			_cleanup()
			return
	_cleanup()
	print("PASS real m4 content: selected contexts, source records, bindings and JSON restore")
	quit(0)


# dr0 completes m0..m3 through the real Session; dr2 takes m0 choice2,
# then m3 choice2. The other prefixes contain unavailable earlier maps:
# their inputs are controlled domain fixtures built from the real m4 library,
# not WorldStore records or claims of natural full-chapter play.
static func prepare(context: Dictionary, roll: Callable) -> Dictionary:
	var progress: Dictionary
	if context["route"] in [0, 2]:
		var previous: Dictionary = M3.prepare(M3.CONTEXTS[0 if context["route"] == 0 else 1], roll)
		if not previous["ok"]:
			return previous
		var opened: Dictionary = Session.new().open(
			CHAPTER, "m3", {"progress": previous["progress"]}, roll
		)
		if not opened["ok"]:
			return opened
		var won: Dictionary = opened["battle"].win_with_assistance()
		if not won["ok"]:
			return won
		var completed: Dictionary = opened["battle"].complete_victory(context["route"])
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
			"m4",
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
		{"id": "m4 inherited opaque warehouse", "templateId": 60, "durability": 2}
	]
	return {"ok": true, "progress": progress}


func _context(context: Dictionary) -> bool:
	var prepared: Dictionary = prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare m4 context: " + str(prepared.get("error"))):
		return false
	var progress: Dictionary = JSON.parse_string(JSON.stringify(prepared["progress"]))
	var before: Dictionary = progress.duplicate(true)
	_draws.clear()
	var opened: Dictionary = Session.new().open(CHAPTER, "m4", {"progress": progress}, _roll)
	if not _expect(opened["ok"], "Open actual m4: " + str(opened.get("error"))):
		return false
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var draws: Array = _draws.duplicate()
	if not _expect(progress == before, "Opening m4 cannot mutate inherited progress"):
		return false
	if not _deployment(context, content, battle):
		return false
	var reversed: Dictionary = progress.duplicate(true)
	reversed["party"].reverse()
	_draws.clear()
	var reordered: Dictionary = Session.new().open(CHAPTER, "m4", {"progress": reversed}, _roll)
	if not _expect(
		(
			reordered["ok"]
			and reordered["battle"].snapshot() == battle.snapshot()
			and reordered["content"]["unitOrder"] == content["unitOrder"]
			and _draws == draws
		),
		"Party array order cannot change slots, random calls or native traversal"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("route_%d.json" % context["route"]))
	var encoded: Dictionary = store.encode(battle)
	if not _expect(
		encoded["ok"] and store.write(battle)["ok"], "m4 writes only its owned continue"
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
		"m4 JSON restore preserves generated positions, state and opaque items without RNG"
	):
		return false
	if context["route"] == 0 and not _first_wave(content, battle):
		return false
	print("PASS actual m4 content dr%d step%d" % [context["route"], context["step"]])
	return true


func _first_wave(content: Dictionary, battle: RefCounted) -> bool:
	_draws.clear()
	var births: Array = []
	while battle.round_number < 4:
		if battle.phase != 0:
			var identity: int = battle.automatic_actor()
			while identity >= 0:
				if not _expect(
					battle.wait_unit(identity)["ok"], "Controlled real m4 automatic waiting"
				):
					return false
				identity = battle.automatic_actor()
		var changed: Dictionary = battle.end_phase()
		if not _expect(
			changed["ok"], "Advance real m4 to first wave: " + str(changed.get("error"))
		):
			return false
		for event: Dictionary in changed["events"]:
			if event["kind"] == "clones":
				births.append_array(event["births"])
	var state: Dictionary = battle.snapshot()
	var expected: Array = [
		{"unitId": 105, "generation": 1, "templateDeploymentIndex": 27},
		{"unitId": 106, "generation": 2, "templateDeploymentIndex": 31},
		{"unitId": 116, "generation": 3, "templateDeploymentIndex": 34}
	]
	if not _expect(
		(
			births.size() == 3
			and state["cloneState"] == {"nextGeneration": 4, "bindings": expected}
			and state["events"].get("monster_clones:round_3", false)
			and _draws.is_empty()
		),
		"Real m4 bo3 creates three generations using declared families without random draws"
	):
		return false
	var projected: Dictionary = Content.new().reproject(
		content, state["units"], state["cloneState"]
	)
	if not _expect(projected["ok"], "Project real m4 births: " + str(projected.get("error"))):
		return false
	var order: Array = content["unitOrder"].duplicate()
	order.append_array([105, 106, 116])
	if not _expect(
		projected["unitOrder"] == order, "Real first wave appends native generation order"
	):
		return false
	for binding: Dictionary in expected:
		var identity: int = binding["unitId"]
		var family: int = [109, 114, 107][binding["generation"] - 1]
		if not _expect(
			(
				projected["profiles"][identity] == content["profiles"][family]
				and projected["mapAnimations"]["units"].has(str(identity))
				and projected["interface"]["portraitByUnitId"].has(str(identity))
			),
			"Actual newborn resolves its own declared family map and portrait aliases"
		):
			return false
	battle.adopt_content(projected)
	var store: RefCounted = Store.new(projected, _owned.path_join("first_wave.json"))
	var encoded: Dictionary = store.encode(battle)
	if not _expect(
		encoded["ok"] and store.write(battle)["ok"], "Save actual m4 first wave to owned record"
	):
		return false
	var record: Dictionary = JSON.parse_string(JSON.stringify(encoded["record"]))
	record["state"]["units"].reverse()
	record["state"]["cloneState"]["bindings"].reverse()
	var before: Dictionary = record.duplicate(true)
	_draws.clear()
	var restored: Dictionary = store.decode(record, _roll)
	return _expect(
		(
			restored["ok"]
			and restored["battle"].snapshot() == battle.snapshot()
			and restored["content"]["unitOrder"] == order
			and _draws.is_empty()
			and record == before
			and store.read()["ok"]
		),
		"Actual first-wave JSON restore preserves actors, order and processed marker without RNG"
	)


func _deployment(context: Dictionary, content: Dictionary, battle: RefCounted) -> bool:
	if not _expect(
		(
			content["spawns"].size() == 36
			and battle.snapshot()["units"].size() == 36
			and content["slots"].size() == 7
			and content["optionalIds"].size() == 9
			and battle.unit(8)["formal"]
			and battle.unit(8)["classId"] == 12
			and battle.unit(8)["visible"]
			and [battle.unit(8)["x"], battle.unit(8)["y"]] == [4, 13]
			and battle.unit(80)["classId"] == 13
			and battle.unit(80)["dropTemplateId"] == 58
			and content["story"]["battleNumber"] == context["step"] + 1
			and content["story"]["routeChoices"].size() == 1
			and content["story"]["routeChoices"][0]["routeIndex"] == context["route"]
			and content["story"]["routeChoices"][0]["nodeId"] == context["next"]
		),
		"m4 keeps 36 records, seven slots, nine random families, recruit8, boss80 and fixed route"
	):
		return false
	var boss_choices: Array = content["spawns"][6]["itemChoices"]
	if not _expect(
		(
			boss_choices.size() == 3
			and int(boss_choices[0]) == 67
			and int(boss_choices[1]) == 50
			and int(boss_choices[2]) == 43
		),
		"m4 boss80 item template IDs must be [67, 50, 43], got " + str(boss_choices)
	):
		return false
	var temporary: Dictionary = {}
	var next_identity: int = 95
	for slot: int in [4, 1, 5, 2, 3, 0, 6]:
		if slot >= context["party"].size():
			temporary[slot] = next_identity
			next_identity += 1
	var expected: Array = [9, 0]
	expected.append_array(context["party"].slice(2))
	var occupied: Dictionary = {}
	var random_cursor: int = 0
	for index: int in range(RAW.size()):
		var raw: Array = RAW[index]
		var spawn: Dictionary = content["spawns"][index]
		var slot: int = int(spawn.get("deploymentSlot", -1))
		var identity: int = int(raw[0])
		if slot >= 0:
			identity = context["party"][slot] if slot < context["party"].size() else temporary[slot]
		var actor: Dictionary = battle.unit(identity)
		if index in [16, 17, 27, 28, 29]:
			if not _expect(_draws[random_cursor] == 3, "Native random equipment precedes position"):
				return false
			random_cursor += 1
		if not _expect(
			(
				spawn["id"] == identity
				and (
					spawn["sourceId"]
					== (raw[0] if slot < 0 or slot >= context["party"].size() else identity)
				)
				and spawn["faction"] == raw[2]
				and spawn["flags"] == raw[3]
				and spawn["policy"] == (0 if raw[2] == 0 else raw[4])
			),
			"m4 raw source order and policy semantics record%d" % index
		):
			return false
		if slot >= 0:
			var formal: bool = slot < context["party"].size()
			var job: int = context["classes"][slot] if formal else raw[1]
			if not _expect(
				(
					content["slots"][slot] == identity
					and actor["formal"] == formal
					and actor["classId"] == job
					and not actor["visible"]
					and actor["policy"] == 0
				),
				"m4 slot%d uses recruit order and current class" % slot
			):
				return false
		if index >= 27:
			var regions: Array = spawn.get("deploymentRegions", [])
			if not _expect(regions.size() == raw[5].size(), "Native region count record%d" % index):
				return false
			for region_index: int in range(regions.size()):
				var region: Array = regions[region_index]
				var expected_region: Array = raw[5][region_index]
				if not _expect(
					(
						region.size() == 4
						and int(region[0]) == expected_region[0]
						and int(region[1]) == expected_region[1]
						and int(region[2]) == expected_region[2]
						and int(region[3]) == expected_region[3]
					),
					"Native region bounds record%d region%d: %s" % [index, region_index, region]
				):
					return false
			var cells: Dictionary = {}
			for region: Array in raw[5]:
				for x: int in range(region[0], region[2] + 1):
					for y: int in range(region[1], region[3] + 1):
						var candidate := Vector2i(x, y)
						if not occupied.has(candidate):
							cells[candidate] = true
			if not _expect(
				_inside(actor, raw[5]) and _draws[random_cursor] == cells.size(),
				(
					"Random family uses inclusive region union, deduplication and occupied exclusion record%d"
					% index
				)
			):
				return false
			random_cursor += 1
		elif not _expect(
			(
				(
					Vector2i(int(spawn["position"][0]), int(spawn["position"][1]))
					== Vector2i(raw[5][0], raw[5][1])
				)
				and Vector2i(actor["x"], actor["y"]) == Vector2i(raw[5][0], raw[5][1])
			),
			"Fixed native cell record%d" % index
		):
			return false
		var cell := Vector2i(actor["x"], actor["y"])
		if not _expect(not occupied.has(cell), "All initial regions reserve hidden actors too"):
			return false
		occupied[cell] = true
		if raw[2] != 0:
			random_cursor += 8
		if identity not in expected:
			expected.append(identity)
		var profile: Dictionary = content["_library"]["profiles"][content["profiles"][identity]]
		if not _expect(
			(
				ResourceLoader.exists(actor["sprite"])
				and content["mapAnimations"]["units"].has(str(identity))
				and content["interface"]["portraitByUnitId"].has(str(identity))
			),
			"Real m4 map/portrait aliases"
		):
			return false
		for weapon: String in profile["appearances"]:
			var alias: String = "%d:%s" % [identity, weapon]
			if not _expect(
				(
					content["battleArt"]["appearances"].has(alias)
					and content["battleClips"]["appearances"].has(alias)
				),
				"Every real m4 family has complete weapon aliases"
			):
				return false
	var actual: Array = []
	for actor: Dictionary in battle.snapshot()["units"]:
		actual.append(int(actor["id"]))
	return _expect(
		(
			actual == expected
			and random_cursor == _draws.size()
			and content["unitOrder"] == expected
			and battle.snapshot()["cloneState"] == {"nextGeneration": 1, "bindings": []}
		),
		"m4 native order is independent of raw slot order and initial clone generations are empty"
	)


func _inside(actor: Dictionary, regions: Array) -> bool:
	for region: Array in regions:
		if (
			actor["x"] >= region[0]
			and actor["x"] <= region[2]
			and actor["y"] >= region[1]
			and actor["y"] <= region[3]
		):
			return true
	return false


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
