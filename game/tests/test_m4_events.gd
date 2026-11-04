extends SceneTree

const Matrix = preload("res://tests/test_m4_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
const WAVES: Dictionary = {
	3: [109, 114, 107],
	4: [112, 111, 110],
	5: [108, 113, 115],
	6: [109, 114, 107],
	8: [112, 111, 110],
	9: [109, 114, 107],
	10: [108, 113, 115]
}
var _draws: int = 0


func _initialize() -> void:
	for context: Dictionary in Matrix.CONTEXTS:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare actual m4: " + str(prepared.get("error"))):
			return
		var opened: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m4", {"progress": prepared["progress"]}, _roll
		)
		if not _expect(opened["ok"], "Open actual m4: " + str(opened.get("error"))):
			return
		if not _rounds(opened, context) or not _priority(opened):
			return
		print("PASS real m4 events dr%d step%d" % [context["route"], context["step"]])
	print("PASS m4 events: seven waves, pool saturation, source inventory, round11 and settlement")
	quit(0)


func _rounds(opened: Dictionary, context: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var original: Dictionary = battle.snapshot()
	var event_id: String = opened["content"]["story"]["turnEvents"][0]["id"]
	var emitted: Array[int] = []
	var arrival_count: int = 0
	var next_id: int = 105
	var total_births: int = 0
	var before_draws: int = _draws
	while battle.round_number < 11:
		var previous: int = battle.round_number
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(advanced["ok"], "Advance m4 real phases: " + str(advanced)):
			return false
		var cloned: bool = false
		for event: Dictionary in advanced["events"]:
			if event["kind"] == "reinforcements":
				arrival_count += 1
				if not _expect(
					(
						previous == 2
						and event["arrivals"].size() == 7
						and battle.event_completed(event_id)
					),
					"Round2 reveals all seven actual slot occupants exactly once"
				):
					return false
			if event["kind"] != "clones":
				continue
			cloned = true
			emitted.append(previous)
			if not _expect(WAVES.has(previous), "Only original rounds emit periodic clones"):
				return false
			var expected: Array = WAVES[previous]
			for index: int in range(event["births"].size()):
				while next_id >= 107 and next_id <= 115:
					next_id += 1
				var born: Dictionary = event["births"][index]
				var actor: Dictionary = battle.unit(born["unit"])
				var source: Dictionary = battle.unit(expected[index])
				if not _expect(
					(
						born["unit"] == next_id
						and actor["sourceId"] == source["sourceId"]
						and actor["classId"] == source["classId"]
						and actor["hp"] == source["maxHp"]
						and actor["attributes"] == source["attributes"]
						and actor["experience"] == 0
						and actor["proficiency"] == 0
						and actor["policy"] == 0
						and actor["formal"] == false
					),
					"Each source-order birth copies its actual current template without growth draws"
				):
					return false
				next_id += 1
				total_births += 1
			if not _expect(
				battle.event_completed("monster_clones:round_%d" % previous),
				"Even a full-pool wave records its own completed round"
			):
				return false
		if not _expect(cloned == WAVES.has(previous), "First-match cycle occurs at the real phase"):
			return false
		if battle.round_number < 11:
			if not _expect(battle.outcome.is_empty(), "Survival never wins before entering11"):
				return false
			var saved: Dictionary = JSON.parse_string(JSON.stringify(battle.snapshot()))
			if not _expect(
				battle.restore_snapshot(saved)["ok"], "Stable m4 phase JSON keeps clone algebra"
			):
				return false
	if not _expect(
		(
			emitted == [3, 4, 5, 6, 8, 9, 10]
			and arrival_count == 1
			and total_births == 14
			and battle.snapshot()["units"].size() == 50
			and battle.snapshot()["cloneState"]["nextGeneration"] == 15
			and _draws == before_draws
			and battle.outcome.get("kind") == "victory"
			and battle.outcome.get("reason") == "survived"
			and battle.unit(80)["hp"] > 0
		),
		"Pool saturation, deterministic phases and immediate round11 victory match the source"
	):
		return false
	var completed: Dictionary = battle.complete_victory(context["route"])
	if not _expect(completed["ok"], "m4 settles its fixed route"):
		return false
	var world: Dictionary = completed["progress"]
	var again: Dictionary = battle.complete_victory(context["route"])
	var party: Array = []
	for actor: Dictionary in world["party"]:
		party.append(int(actor["id"]))
	var expected_party: Array = context["party"].duplicate()
	expected_party.append(8)
	return _expect(
		(
			world["route"] == context["route"]
			and world["completedBattle"] == "m4"
			and world["worldStep"] == context["step"] + 1
			and world["gold"] == original["gold"] + 1000
			and world["warehouse"] == original["warehouse"]
			and party == expected_party
			and again.get("alreadyComplete", false)
			and again["progress"] == world
		),
		"m4 awards1000 and formal roster once while retaining the current route"
	)


func _priority(opened: Dictionary) -> bool:
	var rules := Events.new(opened["content"])
	for required: int in [0, 8]:
		var units: Array = opened["battle"].snapshot()["units"]
		for actor: Dictionary in units:
			if actor["id"] == required:
				actor["hp"] = 0
				actor["visible"] = false
		if not _expect(
			rules.outcome(units, 11).get("kind") == "defeat",
			"Required0/8 defeat takes precedence over round11 survival"
		):
			return false
	var cleared: Array = opened["battle"].snapshot()["units"]
	for actor: Dictionary in cleared:
		if actor["faction"] == 2:
			actor["hp"] = 0
			actor["visible"] = false
	return _expect(
		(
			rules.outcome(cleared, 10).is_empty()
			and rules.outcome(cleared, 11).get("kind") == "victory"
		),
		"Boss death and an empty battlefield cannot win before the survival threshold"
	)


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
