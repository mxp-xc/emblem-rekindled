extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var draws: Array[int] = []
var record_draws: bool = false


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	if not _expect(opened["ok"], "Fixture opens real chapter content"):
		return
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
	var location: Dictionary = {
		"id": "visit_0",
		"sourceIndex": 0,
		"kind": "visit",
		"position": [actor["x"], actor["y"]],
		"tileId": 58,
		"reward": {"kind": "gold", "amount": 1000}
	}
	content["map"]["locations"] = [location]
	for sample: Array in [[1000, 3000, 4000], [500, 3000, 3500], [1000, 9999900, 9999999]]:
		location["reward"]["amount"] = sample[0]
		var battle: RefCounted = _fixture(content, sample[1])
		var result: Dictionary = battle.visit_location(0)
		if not _expect(
			(
				result.get("ok", false)
				and result.get("claimed", false)
				and result["reward"] == {"kind": "gold", "amount": sample[2] - sample[1]}
				and battle.gold == sample[2]
				and battle.unit(0)["action"] == 2
				and battle.event_completed("location:visit_0")
				and draws.is_empty()
			),
			"Fixed gold is awarded without RNG even with full storage and respects the cap"
		):
			return
		var state: Dictionary = battle.snapshot()
		if not _expect(
			not battle.visit_location(0)["ok"] and battle.snapshot() == state and draws.is_empty(),
			"Repeated input cannot award fixed gold twice"
		):
			return
	for bad: Variant in [0, -1, 10000000, 1.5, "500", null]:
		location["reward"]["amount"] = bad
		var battle: RefCounted = _fixture(content, 3000)
		var before: Dictionary = battle.snapshot()
		if not _expect(
			(
				battle.visit_location(0).get("error") == "INVALID_VISIT_REWARD"
				and battle.snapshot() == before
				and draws.is_empty()
			),
			"Invalid fixed gold leaves action and state unchanged"
		):
			return
	location["reward"] = {"kind": "gold", "amount": 500, "extra": true}
	var malformed: RefCounted = _fixture(content, 3000)
	var before: Dictionary = malformed.snapshot()
	if not _expect(
		(
			malformed.visit_location(0).get("error") == "INVALID_VISIT_REWARD"
			and malformed.snapshot() == before
			and draws.is_empty()
		),
		"Extra fixed gold fields are rejected atomically"
	):
		return
	print("PASS fixed visit gold boundaries")
	quit(0)


func _fixture(content: Dictionary, gold: int) -> RefCounted:
	record_draws = false
	var battle: RefCounted = Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	state["gold"] = gold
	for unit: Dictionary in state["units"]:
		if unit["id"] == 0:
			unit["inventory"] = []
			unit["equippedInstanceId"] = ""
			for index: int in range(6):
				unit["inventory"].append({"id": "bag_%d" % index, "templateId": 2, "durability": 1})
	state["warehouse"] = []
	for index: int in range(40):
		state["warehouse"].append({"id": "warehouse_%d" % index, "templateId": 2, "durability": 1})
	if not battle.restore_snapshot(state)["ok"]:
		push_error("Fixed gold fixture must restore")
		quit(1)
	draws.clear()
	record_draws = true
	return battle


func _roll(limit: int) -> int:
	if record_draws:
		draws.append(limit)
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
