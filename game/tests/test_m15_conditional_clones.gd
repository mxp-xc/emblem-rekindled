extends "res://tests/test_random_clones.gd"


func _initialize() -> void:
	_rules = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/generated/rules.json")
	)
	var data: Dictionary = _fixture()
	data["policy"]["randomEachRound"]["count"] = 3
	data["policy"]["randomEachRound"]["whenUnitHidden"] = 83
	data["records"].append({"sourceId": 83, "classId": 17, "faction": 2, "formal": false})
	data["units"][83] = {"id": 83, "visible": true, "hp": 20, "inventory": []}
	_expect(Clones.definition(data["policy"], data["records"])["ok"], "Validated hidden-unit gate")
	for bad: Variant in [84, 107, -1, "83"]:
		var invalid: Dictionary = data["policy"].duplicate(true)
		invalid["randomEachRound"]["whenUnitHidden"] = bad
		_expect(
			not Clones.definition(invalid, data["records"])["ok"],
			"Reject invalid gate: " + str(bad)
		)
	var planner: RefCounted = _planner(data)
	var state: Dictionary = {"nextGeneration": 1, "bindings": []}
	var events: Dictionary = {}
	var units: Dictionary = data["units"]
	_draws.clear()
	var skipped: Dictionary = planner.plan_wave(2, units, [], state, events)
	if not _expect(skipped.get("ok", false), "Plan skipped round"):
		_finish()
		return
	_expect(
		(
			skipped.get("skipped") == true
			and skipped["birthIds"].is_empty()
			and skipped["eventId"] == "random_clones:skip_round_2"
			and _draws.is_empty()
		),
		"Visible gate skips without draws and records a completed skipped round"
	)
	events[skipped["eventId"]] = true
	var repeated: Dictionary = planner.plan_wave(2, units, [], state, events)
	_expect(repeated["ok"] and repeated["eventId"].is_empty(), "Skipped round does not replay")
	units[83]["visible"] = false
	_draws.clear()
	var wave: Dictionary = planner.plan_wave(3, units, [], state, events)
	if not _expect(wave.get("ok", false), "Plan hidden-live gate wave"):
		_finish()
		return
	_expect(
		wave.get("skipped") == false and wave["birthIds"].size() == 3 and _draws == [8, 8, 8],
		"Hidden gate triggers three draws even while target remains alive"
	)
	units = wave["units"]
	state = wave["cloneState"]
	events[wave["eventId"]] = true
	var saved: Dictionary = {
		"round": 4, "phase": 0, "units": units.values(), "cloneState": state, "events": events
	}
	_draws.clear()
	_expect(
		Clones.saved_bindings(data["policy"], data["records"], saved)["ok"],
		"Cold history accepts skipped and active rounds"
	)
	_expect(_draws.is_empty(), "Cold history validation never draws")
	for mutation: String in [
		"missing",
		"both",
		"future",
		"false",
		"noncanonical",
		"missing_gate",
		"impossible_generation"
	]:
		var invalid: Dictionary = saved.duplicate(true)
		match mutation:
			"missing":
				invalid["events"].erase("random_clones:skip_round_2")
			"both":
				invalid["events"]["random_clones:round_2"] = true
			"future":
				invalid["events"]["random_clones:skip_round_4"] = true
			"false":
				invalid["events"]["random_clones:skip_round_2"] = false
			"noncanonical":
				invalid["events"]["random_clones:skip_round_02"] = true
			"missing_gate":
				invalid["units"] = invalid["units"].filter(
					func(actor: Dictionary) -> bool: return actor["id"] != 83
				)
			"impossible_generation":
				invalid["events"].erase("random_clones:round_3")
				invalid["events"]["random_clones:skip_round_3"] = true
		_expect(
			not Clones.saved_bindings(data["policy"], data["records"], invalid)["ok"],
			"Reject " + mutation
		)
	_finish()


func _finish() -> void:
	if not _errors.is_empty():
		for error: String in _errors:
			push_error(error)
		quit(1)
		return
	print("PASS conditional clones: hidden gate, skipped rounds and cold history")
	quit(0)
