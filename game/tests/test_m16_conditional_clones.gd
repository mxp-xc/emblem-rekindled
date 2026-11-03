extends "res://tests/test_battle_clones.gd"


func _initialize() -> void:
	var data: Dictionary = _fixture()
	data["policy"].erase("branches")
	data["policy"].erase("throughRound")
	data["policy"]["conditionalEvery"] = {
		"period": 2,
		"reservedUnitIds": [112, 113, 114, 115],
		"groups":
		[
			{"whenUnitVisible": 34, "templateUnitIds": [109]},
			{"whenUnitVisible": 40, "templateUnitIds": [108]},
			{"whenUnitVisible": 89, "templateUnitIds": [107]},
			{"whenUnitVisible": 92, "templateUnitIds": [110, 111]}
		]
	}
	for id: int in [34, 40, 89, 92]:
		data["records"].append({"sourceId": id, "classId": 0, "faction": 2, "formal": false})
		data["units"][id] = _actor(id)
		data["units"][id]["visible"] = id != 92
	_expect(
		Clones.definition(data["policy"], data["records"])["ok"], "Conditional schedule validates"
	)
	for mutation: String in [
		"missing_gate", "pool_gate", "duplicate_template", "duplicate_reserved"
	]:
		var invalid: Dictionary = data["policy"].duplicate(true)
		match mutation:
			"missing_gate":
				invalid["conditionalEvery"]["groups"][0]["whenUnitVisible"] = 33
			"pool_gate":
				invalid["conditionalEvery"]["groups"][0]["whenUnitVisible"] = 107
			"duplicate_template":
				invalid["conditionalEvery"]["groups"][1]["templateUnitIds"] = [109]
			"duplicate_reserved":
				invalid["conditionalEvery"]["reservedUnitIds"].append(109)
		_expect(not Clones.definition(invalid, data["records"])["ok"], "Reject " + mutation)
	var planner: RefCounted = _planner(data)
	var odd: Dictionary = planner.plan_wave(1, data["units"], [], _initial(), {})
	_expect(odd.get("ok", false) and odd.get("eventId", "x").is_empty(), "Odd round has no wave")
	var wave: Dictionary = planner.plan_wave(2, data["units"], [], _initial(), {})
	_expect(wave.get("ok", false), "Even round plans")
	if wave.get("ok", false):
		var sources: Array[int] = []
		for id: int in wave["birthIds"]:
			sources.append(wave["units"][id]["sourceId"])
		_expect(sources == [109, 108, 107], "Visible gates preserve template order")
		var snapshot: Dictionary = _snapshot(wave, 3, {wave["eventId"]: true})
		_expect(
			Clones.saved_bindings(data["policy"], data["records"], snapshot)["ok"],
			"Cold recovery accepts completed conditional wave"
		)
		var missing: Dictionary = snapshot.duplicate(true)
		missing["events"].clear()
		_expect(
			not Clones.saved_bindings(data["policy"], data["records"], missing)["ok"],
			"Missing wave marker rejects"
		)
		missing = snapshot.duplicate(true)
		missing["units"] = missing["units"].filter(
			func(actor: Dictionary) -> bool: return actor["id"] != 34
		)
		_expect(
			not Clones.saved_bindings(data["policy"], data["records"], missing)["ok"],
			"Missing gate rejects cold recovery"
		)
		for event: String in [
			"monster_clones:round_1",
			"monster_clones:round_4",
			"monster_clones:round_02",
			"monster_clones:skip_round_2"
		]:
			var invalid: Dictionary = snapshot.duplicate(true)
			invalid["events"][event] = true
			_expect(
				not Clones.saved_bindings(data["policy"], data["records"], invalid)["ok"],
				"Reject invalid conditional event " + event
			)
		var repeated: Dictionary = planner.plan_wave(
			2, wave["units"], [], wave["cloneState"], snapshot["events"]
		)
		_expect(
			repeated.get("ok", false) and repeated.get("eventId", "x").is_empty(),
			"Completed wave cannot repeat"
		)
		var distant: Dictionary = snapshot.duplicate(true)
		distant["round"] = 2147483647
		_expect(
			not Clones.saved_bindings(data["policy"], data["records"], distant)["ok"],
			"Distant incomplete history rejects without scanning future rounds"
		)
	data["units"][92]["visible"] = true
	wave = planner.plan_wave(2, data["units"], [], _initial(), {})
	_expect(
		wave.get("ok", false) and wave.get("birthIds", []).size() == 5,
		"Fourth gate adds two clones"
	)
	for id: int in [34, 40, 89, 92]:
		data["units"][id]["visible"] = false
	wave = planner.plan_wave(2, data["units"], [], _initial(), {})
	_expect(
		(
			wave.get("ok", false)
			and wave.get("birthIds", []).is_empty()
			and wave.get("eventId") == "monster_clones:round_2"
		),
		"Empty conditional wave is still recorded"
	)
	if wave.get("ok", false):
		var empty_snapshot: Dictionary = _snapshot(wave, 3, {wave["eventId"]: true})
		_expect(
			Clones.saved_bindings(data["policy"], data["records"], empty_snapshot)["ok"],
			"Empty wave survives cold recovery"
		)
	if not _errors.is_empty():
		for message: String in _errors:
			push_error(message)
		quit(1)
		return
	print("PASS m16 conditional periodic clones")
	quit(0)
