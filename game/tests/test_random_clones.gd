extends SceneTree

const Clones = preload("res://gameplay/battle_clones.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const Inventory = preload("res://gameplay/unit_inventory.gd")
const TEMPLATE_ORDER: Array[int] = [107, 114, 108, 110, 109, 112, 111, 113]
var _draws: Array[int] = []
var _picks: Array[int] = []
var _rules: Dictionary
var _errors: Array[String] = []


func _initialize() -> void:
	_rules = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/generated/rules.json")
	)
	_declaration()
	_waves_and_saved_rounds()
	_current_source()
	_sequential_replacement()
	if not _errors.is_empty():
		for error: String in _errors:
			push_error(error)
		quit(1)
		return
	print(
		(
			"PASS random clones: replacement draws, full pool, unbounded rounds, "
			+ "current family and cold history"
		)
	)
	quit(0)


func _declaration() -> void:
	var data: Dictionary = _fixture()
	var before: Dictionary = data.duplicate(true)
	_expect(
		Clones.definition(data["policy"], data["records"])["ok"],
		"Explicit random schedule is valid"
	)
	_expect(data == before, "Parsing a schedule leaves source unchanged")
	for field: String in ["count", "fromRound"]:
		var policy: Dictionary = data["policy"].duplicate(true)
		policy["randomEachRound"][field] = 0
		_expect(not Clones.definition(policy, data["records"])["ok"], "Reject zero " + field)
	for field: String in ["throughRound", "branches"]:
		var policy: Dictionary = data["policy"].duplicate(true)
		policy[field] = 10 if field == "throughRound" else []
		_expect(not Clones.definition(policy, data["records"])["ok"], "Reject mixed schedule forms")
	var duplicate: Dictionary = data["policy"].duplicate(true)
	duplicate["randomEachRound"]["templateUnitIds"] = [107, 107]
	_expect(
		not Clones.definition(duplicate, data["records"])["ok"],
		"The source list itself has no duplicate IDs"
	)


func _waves_and_saved_rounds() -> void:
	var data: Dictionary = _fixture()
	var planner: RefCounted = _planner(data)
	var state: Dictionary = {"nextGeneration": 1, "bindings": []}
	var events: Dictionary = {}
	var units: Dictionary = data["units"]
	for round_number: int in range(1, 13):
		_draws.clear()
		var planned: Dictionary = planner.plan_wave(round_number, units, [], state, events)
		if not _expect(planned["ok"], "Plan source round %d" % round_number):
			return
		var count: int = (
			0 if round_number == 1 or round_number >= 10 else 1 if round_number == 9 else 2
		)
		_expect(
			planned["birthIds"].size() == count, "Eight templates leave exactly fifteen free IDs"
		)
		_expect(
			_draws == ([] if round_number == 1 else [8, 8]),
			"Every due round draws twice even when full"
		)
		for identity: int in planned["birthIds"]:
			var actor: Dictionary = planned["units"][identity]
			_expect(
				not actor["visible"] and actor["flags"] == 1,
				"Both births stay hidden until arrival presentation"
			)
			_expect(actor["sourceId"] == 107, "Two draws may select the same current template")
		units = planned["units"]
		state = planned["cloneState"]
		if not planned["eventId"].is_empty():
			events[planned["eventId"]] = true
	var saved: Dictionary = {
		"round": 13, "phase": 0, "units": units.values(), "cloneState": state, "events": events
	}
	_draws.clear()
	_expect(
		Clones.saved_bindings(data["policy"], data["records"], saved)["ok"],
		"Completed full-pool rounds remain valid history with zero births"
	)
	_expect(_draws.is_empty(), "Saved history validation never draws a future source")
	for kind: String in ["missing", "future", "false", "noncanonical"]:
		var invalid: Dictionary = saved.duplicate(true)
		match kind:
			"missing":
				invalid["events"].erase("random_clones:round_2")
			"future":
				invalid["events"]["random_clones:round_13"] = true
			"false":
				invalid["events"]["random_clones:round_12"] = false
			"noncanonical":
				invalid["events"]["random_clones:round_02"] = true
		_expect(
			not Clones.saved_bindings(data["policy"], data["records"], invalid)["ok"],
			"Reject " + kind + " history"
		)
	_draws.clear()
	var late: Dictionary = planner.plan_wave(100, units, [], state, events)
	_expect(
		late["ok"] and late["birthIds"].is_empty() and _draws == [8, 8],
		"No authored end round stops a full-pool round100"
	)
	events[late["eventId"]] = true
	_draws.clear()
	var again: Dictionary = planner.plan_wave(100, units, [], state, events)
	_expect(
		again["ok"] and again["eventId"].is_empty() and _draws.is_empty(),
		"Completed round is not redrawn"
	)
	units[105]["hp"] = 0
	units[105]["visible"] = false
	_picks = [1, 1]
	_draws.clear()
	var recycled: Dictionary = planner.plan_wave(101, units, [], state, events)
	_expect(
		recycled["ok"] and recycled["birthIds"] == [105] and _draws == [8, 8],
		"Reclaimed105 fills the sole vacancy but both choices still draw"
	)
	_expect(
		recycled["units"][105]["sourceId"] == 108 and recycled["units"][105]["classId"] == 36,
		"Recycled ID switches to current selected family"
	)
	for round_number: int in [1, 2]:
		var initial: Dictionary = {
			"round": round_number,
			"phase": 0,
			"units": data["units"].values(),
			"cloneState": {"nextGeneration": 1, "bindings": []},
			"events": {}
		}
		_expect(
			Clones.saved_bindings(data["policy"], data["records"], initial)["ok"],
			"Before first due round requires no markers"
		)


func _current_source() -> void:
	var data: Dictionary = _fixture()
	var source: Dictionary = data["units"][107]
	source["visible"] = true
	source["flags"] = 0
	source["hp"] = 0
	source["level"] = 7
	source["maxHp"] = 31
	source["attributes"]["strength"] = 22
	source["inventory"] = [
		{"id": "old weapon", "templateId": 30, "durability": 1},
		{"id": "old G", "templateId": 63, "durability": 1}
	]
	source["dropTemplateId"] = 63
	var before: Dictionary = data["units"].duplicate(true)
	var planned: Dictionary = _planner(data).plan_wave(
		2, data["units"], [], {"nextGeneration": 1, "bindings": []}, {}
	)
	if not _expect(planned["ok"], "Visible HP0 source remains copyable"):
		return
	for identity: int in [105, 106]:
		var born: Dictionary = planned["units"][identity]
		_expect(
			born["level"] == 7 and born["hp"] == 31 and born["attributes"]["strength"] == 22,
			"Clone copies current cultivation and restores full HP"
		)
		_expect(
			born["inventory"][0]["durability"] == 99 and born["inventory"][1]["templateId"] == 63,
			"Default durability and G inventory are rebuilt"
		)
	_expect(data["units"] == before, "Birth planning does not mutate source objects")


func _sequential_replacement() -> void:
	var data: Dictionary = _fixture()
	data["policy"]["pool"] = [107, 108]
	for identity: int in [107, 108]:
		data["units"][identity]["hp"] = 0
	_picks = [1, 0]
	var planned: Dictionary = _planner(data).plan_wave(
		2, data["units"], [], {"nextGeneration": 1, "bindings": []}, {}
	)
	if not _expect(
		planned["ok"] and planned["birthIds"] == [107, 108],
		"Each attempt resolves its current source before allocating"
	):
		return
	_expect(
		planned["units"][107]["classId"] == 36 and planned["units"][108]["classId"] == 36,
		"Second draw107 copies its newly replaced family, not static32"
	)
	for binding: Dictionary in planned["cloneState"]["bindings"]:
		_expect(
			binding["templateDeploymentIndex"] == 2,
			"Both births retain real root108 at source record2"
		)


func _fixture() -> Dictionary:
	var records: Array[Dictionary] = []
	var units: Dictionary = {}
	for identity: int in TEMPLATE_ORDER:
		var job: int = 32 if identity in [107, 114, 111, 113] else 36
		records.append({"sourceId": identity, "classId": job, "faction": 2, "formal": false})
		units[identity] = {
			"id": identity,
			"sourceId": identity,
			"classId": job,
			"classGroup": int(job / 4),
			"faction": 2,
			"formal": false,
			"growthTemplateId": 10 + int(job / 4),
			"equipMask": 4 if job == 32 else 16,
			"level": 1,
			"hp": 20,
			"maxHp": 20,
			"move": 5,
			"flags": 1,
			"visible": false,
			"policy": 0,
			"action": 0,
			"experience": 0,
			"proficiency": 0,
			"x": 2,
			"y": 2,
			"attributes":
			{"strength": 7, "skill": 2, "speed": 6, "defense": 3, "magic": 5, "luck": 3},
			"dropTemplateId": 0,
			"inventory":
			[{"id": "old_%d" % identity, "templateId": 30 if job == 32 else 42, "durability": 1}],
			"equippedInstanceId": "old_%d" % identity
		}
	return {
		"policy":
		{
			"id": "random_clones",
			"pool": [105, 127],
			"randomEachRound":
			{
				"fromRound": 2,
				"count": 2,
				"templateUnitIds": [107, 108, 109, 110, 111, 112, 113, 114]
			}
		},
		"records": records,
		"units": units
	}


func _planner(data: Dictionary) -> RefCounted:
	var combat: RefCounted = Combat.new(_rules, [])
	var inventory: RefCounted = Inventory.new(combat, _roll)
	return Clones.new(
		{
			"entry": {"id": "fixture", "battleId": "random"},
			"_deployments": data["records"],
			"story": {"periodicClones": data["policy"]}
		},
		combat,
		inventory,
		_roll
	)


func _roll(limit: int) -> int:
	_draws.append(limit)
	return _picks.pop_front() if not _picks.is_empty() else 0


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		_errors.append(message)
	return ok
