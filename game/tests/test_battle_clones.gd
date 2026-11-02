extends SceneTree

const Clones = preload("res://gameplay/battle_clones.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const Inventory = preload("res://gameplay/unit_inventory.gd")
const Events = preload("res://gameplay/battle_events.gd")
var _errors: Array[String] = []
var _draws: int = 0


func _initialize() -> void:
	_test_declaration()
	_test_waves()
	_test_pool_and_current_templates()
	_test_inventory_and_reset()
	_test_reveal_batch()
	_test_saved_bindings()
	_test_saved_errors()
	_expect(_draws == 0, "Cloning and binding recovery must not draw randomness")
	if not _errors.is_empty():
		for message: String in _errors:
			push_error(message)
		quit(1)
		return
	print(
		"PASS periodic clones: declaration, current families, pool order, inventory and save algebra"
	)
	quit(0)


func _test_declaration() -> void:
	var data: Dictionary = _fixture()
	var before: Dictionary = data.duplicate(true)
	var declared: Dictionary = Clones.definition(data["policy"], data["records"])
	_expect(declared["ok"] and declared["enabled"], "A finite authored clone declaration is valid")
	_expect(declared["templateIndices"][109] == 0, "Families use raw deployment array indices")
	_expect(data == before, "Declaration validation must not mutate authored data")
	_expect(Clones.definition(null, [])["ok"], "Existing maps need no clone declaration")
	var float_policy: Dictionary = JSON.parse_string(JSON.stringify(data["policy"]))
	_expect(
		Clones.definition(float_policy, data["records"])["ok"], "JSON integral floats are valid"
	)
	var bad: Array = []
	var value: Dictionary = data["policy"].duplicate(true)
	value["pool"] = [127, 105]
	bad.append(value)
	value = data["policy"].duplicate(true)
	value["throughRound"] = 10.5
	bad.append(value)
	value = data["policy"].duplicate(true)
	value["branches"][0]["period"] = 0
	bad.append(value)
	value = data["policy"].duplicate(true)
	value["branches"][0]["templateUnitIds"] = [109, 109]
	bad.append(value)
	value = data["policy"].duplicate(true)
	value["branches"][0]["templateUnitIds"] = [999]
	bad.append(value)
	value = data["policy"].duplicate(true)
	value["script"] = "not an authored operation"
	bad.append(value)
	for policy: Dictionary in bad:
		_expect(
			not Clones.definition(policy, data["records"])["ok"], "Reject malformed declaration"
		)
	for field: String in ["formal", "faction", "deploymentSlot"]:
		var records: Array = data["records"].duplicate(true)
		records[0][field] = true if field == "formal" else 0
		_expect(
			not Clones.definition(data["policy"], records)["ok"], "Reject invalid template " + field
		)
	var records: Array = data["records"].duplicate(true)
	records.append({"sourceId": 105, "classId": 0, "faction": 0, "formal": true})
	_expect(
		not Clones.definition(data["policy"], records)["ok"], "A pool cannot cover a formal actor"
	)
	records[-1] = {"sourceId": 105, "classId": 0, "faction": 2, "formal": false}
	_expect(
		not Clones.definition(data["policy"], records)["ok"],
		"A pool cannot replace undeclared static actors"
	)


func _test_waves() -> void:
	var data: Dictionary = _fixture()
	var expected: Dictionary = {
		3: [109, 114, 107],
		4: [112, 111, 110],
		5: [108, 113, 115],
		6: [109, 114, 107],
		8: [112, 111, 110],
		9: [109, 114, 107],
		10: [108, 113, 115]
	}
	for round_number: int in range(1, 12):
		var result: Dictionary = _planner(data).plan_wave(
			round_number, data["units"], [], _initial(), {}
		)
		if not expected.has(round_number):
			_expect(
				result["eventId"].is_empty() and result["birthIds"].is_empty(),
				"No wave outside authored rounds"
			)
			continue
		var sources: Array[int] = []
		for id: int in result["birthIds"]:
			sources.append(result["units"][id]["sourceId"])
		_expect(sources == expected[round_number], "Wave templates preserve authored branch order")
		_expect(
			result["eventId"] == "monster_clones:round_%d" % round_number,
			"Wave marker includes its round"
		)
	data["policy"]["throughRound"] = 12
	var first: Dictionary = _planner(data).plan_wave(12, data["units"], [], _initial(), {})
	_expect(
		first["units"][105]["sourceId"] == 109 and first["birthIds"].size() == 3,
		"An overlapping period executes only the first matching branch"
	)
	var done: Dictionary = _planner(data).plan_wave(
		3, data["units"], [], _initial(), {"monster_clones:round_3": true}
	)
	_expect(
		done["eventId"].is_empty() and done["cloneState"] == _initial(),
		"A completed wave cannot repeat"
	)


func _test_pool_and_current_templates() -> void:
	var data: Dictionary = _fixture()
	data["units"][105] = data["units"][109].duplicate(true)
	data["units"][105]["id"] = 105
	data["units"][105]["hp"] = 0
	var clone_state: Dictionary = {
		"nextGeneration": 2,
		"bindings": [{"unitId": 105, "generation": 1, "templateDeploymentIndex": 0}]
	}
	var result: Dictionary = _planner(data).plan_wave(3, data["units"], [], clone_state, {})
	_expect(
		result["birthIds"] == [105, 106, 116],
		"Ascending scan reclaims hidden dead before a later missing ID"
	)
	_expect(
		result["units"].keys().slice(-3) == [105, 106, 116],
		"Recycled IDs are erased then appended at the tail"
	)
	data = _fixture()
	data["policy"]["pool"] = [105, 108]
	data["units"][105] = data["units"][109].duplicate(true)
	data["units"][105]["id"] = 105
	data["units"][105]["visible"] = true
	data["units"][105]["hp"] = 0
	data["units"][106] = data["units"][109].duplicate(true)
	data["units"][106]["id"] = 106
	data["units"][107]["hp"] = 0
	data["units"][108]["hp"] = 0
	clone_state = {
		"nextGeneration": 3,
		"bindings":
		[
			{"unitId": 105, "generation": 1, "templateDeploymentIndex": 0},
			{"unitId": 106, "generation": 2, "templateDeploymentIndex": 0}
		]
	}
	result = _planner(data).plan_wave(3, data["units"], [], clone_state, {})
	_expect(result["birthIds"] == [107, 108], "Visible dead and hidden alive occupy the pool")
	_expect(
		result["cloneState"]["nextGeneration"] == 5, "Only successful births consume a generation"
	)
	var full: Dictionary = _planner(data).plan_wave(
		4, result["units"], [], result["cloneState"], {}
	)
	_expect(
		full["birthIds"].is_empty() and full["eventId"] == "monster_clones:round_4",
		"A full pool still completes its wave without creating an actor or item"
	)
	_expect(full["cloneState"] == result["cloneState"], "A full pool preserves generation state")
	data = _fixture()
	data["policy"]["pool"] = [107, 109]
	data["policy"]["branches"] = [{"period": 3, "templateUnitIds": [109, 107]}]
	# Remove static108 so it is a free pool slot in this isolated branch fixture.
	data["records"] = data["records"].filter(
		func(record: Dictionary) -> bool: return record["sourceId"] != 108
	)
	data["units"].erase(108)
	data["units"][107]["hp"] = 0
	data["units"][109]["attributes"]["strength"] = 29
	data["units"][109]["x"] = 4
	result = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	_expect(
		result["birthIds"] == [107, 108], "A later template reads the earlier recycled current ID"
	)
	_expect(
		(
			result["units"][108]["sourceId"] == 109
			and result["units"][108]["attributes"]["strength"] == 29
		),
		"A recycled template carries its current family and stats, not the original family"
	)
	_expect(
		result["origins"][107] == Vector2i(4, 2) and result["origins"][108] == Vector2i(4, 2),
		"All hidden births retain construction positions before any reveal"
	)
	_expect(
		result["cloneState"]["bindings"][1]["templateDeploymentIndex"] == 0,
		"A descendant inherits the original family root"
	)
	data = _fixture()
	data["policy"]["pool"] = [109, 109]
	data["policy"]["branches"] = [{"period": 3, "templateUnitIds": [109]}]
	data["units"][109]["hp"] = 0
	result = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	_expect(
		result["ok"] and result["units"][109]["hp"] == 20,
		"Capture a template before recycling itself"
	)


func _test_inventory_and_reset() -> void:
	var data: Dictionary = _fixture()
	var source: Dictionary = data["units"][109]
	source.merge(
		{
			"hp": 2,
			"level": 7,
			"maxHp": 35,
			"move": 8,
			"flags": 127,
			"policy": 77,
			"action": 2,
			"experience": 88,
			"proficiency": 99,
			"deploymentIndex": 0,
			"temporary": false,
			"dropTemplateId": 67
		},
		true
	)
	source["attributes"]["strength"] = 23
	source["inventory"] = [
		_held("worn", 30, 2), _held("empty", 60, 0), _held("drop1", 67, 1), _held("drop2", 67, 0)
	]
	var warehouse: Array = [
		_held("fixture:m4:clone_1:item_0", 67, 1),
		_held("fixture:m4:clone_1:item_0:1", 67, 1),
		_held("旧掉落 / opaque", 67, 1)
	]
	data["units"][114]["inventory"] = [_held("fixture:m4:clone_1:item_0:2", 30, 1)]
	var before: Dictionary = data.duplicate(true)
	var warehouse_before: Array = warehouse.duplicate(true)
	var initial: Dictionary = _initial()
	var completed: Dictionary = {}
	var result: Dictionary = _planner(data).plan_wave(
		3, data["units"], warehouse, initial, completed
	)
	var born: Dictionary = result["units"][105]
	_expect(
		(
			data == before
			and warehouse == warehouse_before
			and initial == _initial()
			and completed == {}
		),
		"Planning must not mutate any supplied unit, warehouse, state or event"
	)
	_expect(
		(
			born["level"] == 7
			and born["maxHp"] == 35
			and born["hp"] == 35
			and born["move"] == 8
			and born["attributes"]["strength"] == 23
			and born["classId"] == source["classId"]
		),
		"Current template cultivation and class are copied, with full new HP"
	)
	_expect(
		(
			born["flags"] == 1
			and not born["visible"]
			and born["policy"] == 0
			and born["action"] == 0
			and born["experience"] == 0
			and born["proficiency"] == 0
			and not born["formal"]
		),
		"Each birth resets transient state rather than copying its template's combat state"
	)
	_expect(
		(
			not born.has("deploymentIndex")
			and not born.has("temporary")
			and not born.has("deploymentSlot")
		),
		"Dynamic identities are represented only by clone bindings"
	)
	_expect(
		(
			born["inventory"].map(func(item: Dictionary) -> int: return item["templateId"])
			== [30, 60, 67]
		),
		"All G entries are filtered, then one G is appended"
	)
	_expect(
		(
			born["inventory"].map(func(item: Dictionary) -> int: return item["durability"])
			== [99, 3, 3]
		),
		"New held items use default durability, including a template item at zero durability"
	)
	_expect(
		born["inventory"][0]["id"] == "fixture:m4:clone_1:item_0:3",
		"All bags and warehouse participate in deterministic opaque ID collision avoidance"
	)
	_expect(
		born["equippedInstanceId"] == born["inventory"][0]["id"],
		"New equipment is selected normally"
	)
	born["attributes"]["strength"] = 0
	born["inventory"][0]["durability"] = 0
	_expect(
		data == before, "The returned plan shares no mutable unit or held-item objects with inputs"
	)
	data = _fixture()
	data["units"][109]["dropTemplateId"] = 67
	data["units"][109]["inventory"] = []
	for index: int in range(6):
		data["units"][109]["inventory"].append(_held("six_%d" % index, 30, 0))
	result = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	_expect(
		(
			result["units"][105]["inventory"].size() == 6
			and result["units"][105]["inventory"].all(
				func(item: Dictionary) -> bool: return item["templateId"] == 30
			)
		),
		"Rebuilding G respects six-slot capacity without inserting a seventh item"
	)
	# Reuse an ID after its earlier G has become a warehouse item.
	data = _fixture()
	data["units"][109]["dropTemplateId"] = 67
	data["units"][109]["inventory"].append(_held("source_G", 67, 1))
	result = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	var state: Dictionary = result["cloneState"]
	var units: Dictionary = result["units"]
	var old_drop: Dictionary = units[105]["inventory"].pop_back()
	units[105]["visible"] = false
	units[105]["hp"] = 0
	result = _planner(data).plan_wave(6, units, [old_drop], state, {})
	_expect(
		(
			result["units"][105]["inventory"][-1]["templateId"] == 67
			and result["units"][105]["inventory"][-1]["id"] != old_drop["id"]
		),
		"A recycled unit receives new generation item identities while old loot remains owned"
	)


func _test_reveal_batch() -> void:
	var data: Dictionary = _fixture()
	for id: int in [109, 114, 107]:
		data["units"][id]["x"] = 2
		data["units"][id]["y"] = 2
	data["units"][109]["visible"] = true
	data["units"][114]["visible"] = false
	var result: Dictionary = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	var arrivals: Array = Events.new(_content(data)).reinforce(
		result["units"].values(), result["birthIds"]
	)
	_expect(
		(
			arrivals.map(func(arrival: Dictionary) -> Vector2i: return arrival["to"])
			== [Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 3)]
		),
		"Reinforce reserves each destination using left, up, down, right order"
	)
	data = _fixture()
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]:
		var id: int = 40 + data["units"].size()
		data["units"][id] = _actor(id)
		data["units"][id]["visible"] = true
		data["units"][id]["x"] = 2 + offset.x
		data["units"][id]["y"] = 2 + offset.y
	data["units"][109]["visible"] = true
	result = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	arrivals = Events.new(_content(data)).reinforce(result["units"].values(), result["birthIds"])
	_expect(
		(
			not result["units"][105]["visible"]
			and result["units"][105]["hp"] == 20
			and arrivals.is_empty()
		),
		"Blocked births remain hidden and alive in the pool"
	)
	var snapshot: Dictionary = _snapshot(result, 4, {"monster_clones:round_3": true})
	_expect(
		Clones.saved_bindings(data["policy"], data["records"], snapshot)["ok"],
		"Blocked hidden births retain restorable bindings"
	)
	result["units"].erase(49)
	var retry: Dictionary = _planner(data).plan_wave(
		3, result["units"], [], result["cloneState"], snapshot["events"]
	)
	_expect(
		retry["birthIds"].is_empty() and not retry["units"][105]["visible"],
		"A freed neighbor does not retry a completed wave"
	)


func _test_saved_bindings() -> void:
	var data: Dictionary = _fixture()
	var initial: Dictionary = {
		"units": data["units"].values(),
		"cloneState": _initial(),
		"round": 1,
		"phase": 0,
		"events": {}
	}
	_expect(
		Clones.saved_bindings(data["policy"], data["records"], initial)["ok"],
		"A pre-birth save is valid"
	)
	var result: Dictionary = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	var state: Dictionary = _snapshot(result, 4, {"monster_clones:round_3": true})
	# Item strings carry no generation meaning and are not inspected by this validator.
	state["units"][-1]["inventory"][0]["id"] = "opaque / arbitrary : clone_999999"
	state["units"][-1]["hp"] = 0
	var before: Dictionary = state.duplicate(true)
	var decoded: Dictionary = Clones.saved_bindings(data["policy"], data["records"], state)
	_expect(
		decoded["ok"] and decoded["nextGeneration"] == 4 and decoded["bindings"].size() == 3,
		"Dead and hidden actors remain bound without inferring generations from held-item strings"
	)
	_expect(
		decoded["staticUnits"].size() == 9 and decoded["replacedIndices"].is_empty(),
		"Split only explicitly bound dynamic actors"
	)
	_expect(state == before, "Saved validation must not normalize caller-owned records in place")
	var json_state: Dictionary = JSON.parse_string(JSON.stringify(state))
	_expect(
		Clones.saved_bindings(data["policy"], data["records"], json_state)["ok"],
		"Legal JSON float identities and generations restore"
	)
	var current: Dictionary = Clones.current_bindings(
		data["policy"], data["records"], state["units"], state["cloneState"]
	)
	_expect(
		current["ok"] and current["bindings"] == decoded["bindings"],
		"Projection and save recovery share one binding algebra"
	)
	data["units"][107]["hp"] = 0
	data["policy"]["pool"] = [107, 109]
	data["policy"]["branches"] = [{"period": 3, "templateUnitIds": [109, 107, 108]}]
	result = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	state = _snapshot(result, 4, {"monster_clones:round_3": true})
	decoded = Clones.saved_bindings(data["policy"], data["records"], state)
	_expect(
		decoded["ok"] and decoded["replacedIndices"] == [2],
		"Replacing a static pool actor suppresses its original deployment binding"
	)
	var old: Dictionary = Clones.saved_bindings(null, [], {"units": [{"id": 5}]})
	_expect(
		old["ok"] and old["staticUnits"] == [{"id": 5}],
		"Unenabled maps preserve the existing static save contract"
	)
	_expect(
		not Clones.saved_bindings(null, [], {"units": [], "cloneState": _initial()})["ok"],
		"Undeclared maps cannot accept dynamic state"
	)


func _test_saved_errors() -> void:
	var data: Dictionary = _fixture()
	var result: Dictionary = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	var state: Dictionary = _snapshot(result, 4, {"monster_clones:round_3": true})
	var cases: Array[Dictionary] = []
	for invalid: int in [0, 3, 5]:
		var bad: Dictionary = state.duplicate(true)
		bad["cloneState"]["nextGeneration"] = invalid
		cases.append(bad)
	for field: String in ["unitId", "generation", "templateDeploymentIndex"]:
		var bad: Dictionary = state.duplicate(true)
		bad["cloneState"]["bindings"][0][field] = 999
		cases.append(bad)
	for field: String in [
		"sourceId", "classId", "faction", "formal", "deploymentIndex", "temporary"
	]:
		var bad: Dictionary = state.duplicate(true)
		bad["units"][-3][field] = true if field in ["formal", "temporary"] else 0
		cases.append(bad)
	var bad: Dictionary = state.duplicate(true)
	bad["cloneState"]["bindings"][1]["generation"] = 1
	cases.append(bad)
	bad = state.duplicate(true)
	bad["cloneState"]["bindings"][1]["unitId"] = 105
	cases.append(bad)
	bad = state.duplicate(true)
	bad["cloneState"]["bindings"].remove_at(0)
	cases.append(bad)
	bad = state.duplicate(true)
	bad["units"].pop_back()
	cases.append(bad)
	bad = state.duplicate(true)
	bad["units"].remove_at(0)
	cases.append(bad)
	bad = state.duplicate(true)
	bad["cloneState"].erase("bindings")
	cases.append(bad)
	bad = state.duplicate(true)
	bad["phase"] = 1
	cases.append(bad)
	bad = state.duplicate(true)
	bad["events"] = {}
	cases.append(bad)
	bad = state.duplicate(true)
	bad["events"]["monster_clones:round_4"] = true
	cases.append(bad)
	bad = state.duplicate(true)
	bad["events"]["monster_clones:round_7"] = true
	cases.append(bad)
	bad = state.duplicate(true)
	bad["round"] = 3
	cases.append(bad)
	# Structure alone allows later generations, but the processed-wave bound still rejects them.
	bad = state.duplicate(true)
	bad["cloneState"]["bindings"][2]["generation"] = 4
	bad["cloneState"]["nextGeneration"] = 5
	cases.append(bad)
	for index: int in range(cases.size()):
		_expect(
			not Clones.saved_bindings(data["policy"], data["records"], cases[index])["ok"],
			"Reject inconsistent saved clone case %d" % index
		)
	data["units"][107]["hp"] = 0
	data["policy"]["pool"] = [107, 109]
	data["policy"]["branches"] = [{"period": 3, "templateUnitIds": [109, 107, 108]}]
	result = _planner(data).plan_wave(3, data["units"], [], _initial(), {})
	state = _snapshot(result, 4, {"monster_clones:round_3": true})
	state["cloneState"] = _initial()
	_expect(
		not Clones.saved_bindings(data["policy"], data["records"], state)["ok"],
		"Removing a recycled template binding cannot disguise a changed family as the static actor"
	)


func _fixture() -> Dictionary:
	var records: Array[Dictionary] = []
	var units: Dictionary = {}
	for id: int in [109, 114, 107, 112, 111, 110, 108, 113, 115]:
		records.append({"sourceId": id, "classId": id % 3, "faction": 2, "formal": false})
		units[id] = _actor(id)
	return {
		"policy":
		{
			"id": "monster_clones",
			"pool": [105, 127],
			"throughRound": 10,
			"branches":
			[
				{"period": 3, "templateUnitIds": [109, 114, 107]},
				{"period": 4, "templateUnitIds": [112, 111, 110]},
				{"period": 5, "templateUnitIds": [108, 113, 115]}
			]
		},
		"records": records,
		"units": units
	}


func _actor(id: int) -> Dictionary:
	return {
		"id": id,
		"sourceId": id,
		"faction": 2,
		"formal": false,
		"classId": id % 3,
		"classGroup": 0,
		"equipMask": 1,
		"growthTemplateId": 10,
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
		"attributes": {"strength": 7, "skill": 2, "speed": 6, "defense": 3, "magic": 5, "luck": 3},
		"dropTemplateId": 0,
		"inventory": [_held("opaque_%d" % id, 30, 2)],
		"equippedInstanceId": "opaque_%d" % id
	}


func _content(data: Dictionary) -> Dictionary:
	return {
		"entry": {"id": "fixture", "battleId": "m4"},
		"_deployments": data["records"],
		"map": {"width": 8, "height": 8},
		"rules": {"alliances": [0, 0, 1]},
		"story":
		{
			"periodicClones": data["policy"],
			"outcomeRules": {"checks": []},
			"turnEvents": [],
			"aiChanges": []
		}
	}


func _planner(data: Dictionary) -> RefCounted:
	var items: Array[Dictionary] = []
	for id: int in [30, 60, 67]:
		items.append(
			{
				"id": id,
				"defaultDurability": 99 if id == 30 else 3,
				"damageKind": "physical" if id == 30 else "none",
				"categoryMask": 1
			}
		)
	var combat: RefCounted = Combat.new(
		{"itemTemplates": items, "terrainDefense": [], "terrainEvasion": []}, []
	)
	return Clones.new(_content(data), combat, Inventory.new(combat, _draw))


func _initial() -> Dictionary:
	return {"nextGeneration": 1, "bindings": []}


func _snapshot(plan: Dictionary, round_number: int, events: Dictionary) -> Dictionary:
	return {
		"units": plan["units"].values(),
		"cloneState": plan["cloneState"],
		"round": round_number,
		"phase": 0,
		"events": events
	}


func _held(id: String, template_id: int, durability: int) -> Dictionary:
	return {"id": id, "templateId": template_id, "durability": durability}


func _draw(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
