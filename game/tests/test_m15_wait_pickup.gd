extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")

var draw_value: int = 0
var draws: Array[int] = []
var action_random: bool = false


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	if not _expect(opened["ok"], "Fixture opens real m0 content"):
		return
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
	content["map"]["locations"] = [
		{
			"id": "wait_0",
			"sourceIndex": 0,
			"kind": "waitPickup",
			"position": [actor["x"], actor["y"]],
			"tileId": 39,
			"reward":
			{
				"kind": "weightedItem",
				"weightedChoices":
				[{"templateId": 72, "weight": 20}, {"templateId": 73, "weight": 20}]
			}
		}
	]
	for sample: Array in [
		[0, 5, 0, 72],
		[19, 5, 0, 72],
		[20, 6, 39, 73],
		[39, 5, 0, 73],
		[40, 6, 40, 0],
		[99, 5, 0, 0]
	]:
		draw_value = sample[0]
		var battle: RefCounted = _fixture(content, sample[1], sample[2])
		var result: Dictionary = battle.wait_unit(0)
		if not _expect(
			(
				result.get("ok", false)
				and result["location"]["claimed"]
				and battle.event_completed("location:wait_0")
				and battle.unit(0)["action"] == 2
				and draws == [100]
			),
			"Weighted wait resolves one draw, consumes location and ends action"
		):
			return
		if sample[3] == 0:
			if not _expect(
				(
					result["location"]["reward"]["kind"] == "empty"
					and not result["location"].has("rewards")
				),
				"Empty result consumes even when storage is full without creating an item"
			):
				return
		else:
			var loot: Dictionary = result["location"]["rewards"]["loot"][0]
			if not _expect(
				(
					loot["item"]["templateId"] == sample[3]
					and loot["destination"] == ("warehouse" if sample[1] == 6 else "inventory")
				),
				"Item reaches available bag or warehouse"
			):
				return
		var snapshot: Dictionary = battle.snapshot()
		if not _expect(
			not battle.wait_unit(0)["ok"] and draws == [100] and battle.snapshot() == snapshot,
			"Repeated input cannot claim again"
		):
			return
	draw_value = 0
	var full: RefCounted = _fixture(content, 6, 40)
	var failed: Dictionary = full.wait_unit(0)
	if not _expect(
		(
			failed["ok"]
			and not failed["location"]["claimed"]
			and failed["location"]["reason"] == "WAREHOUSE_FULL"
			and not full.event_completed("location:wait_0")
			and full.unit(0)["action"] == 2
			and draws == [100]
		),
		"Nonempty full storage ends action without consuming"
	):
		return
	var retry: Dictionary = full.snapshot()
	retry["warehouse"].pop_back()
	for unit: Dictionary in retry["units"]:
		if unit["id"] == 0:
			unit["action"] = 0
	if not _expect(
		(
			full.restore_snapshot(retry)["ok"]
			and full.wait_unit(0)["location"]["claimed"]
			and draws == [100, 100]
		),
		"Later action can retry unclaimed location"
	):
		return
	draw_value = 100
	var invalid: RefCounted = _fixture(content, 5, 0)
	var before: Dictionary = invalid.snapshot()
	if not _expect(
		(
			invalid.wait_unit(0).get("error") == "INVALID_RANDOM_RESULT"
			and invalid.snapshot() == before
			and draws == [100]
		),
		"Invalid random result commits no action, item or location"
	):
		return
	print("PASS m15 weighted wait pickup boundaries")
	quit(0)


func _fixture(content: Dictionary, bag: int, warehouse: int) -> RefCounted:
	action_random = false
	var battle: RefCounted = Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	for unit: Dictionary in state["units"]:
		if unit["id"] == 0:
			unit["inventory"] = []
			unit["equippedInstanceId"] = ""
			for index: int in range(bag):
				unit["inventory"].append({"id": "bag_%d" % index, "templateId": 2, "durability": 1})
	state["warehouse"] = []
	for index: int in range(warehouse):
		state["warehouse"].append({"id": "warehouse_%d" % index, "templateId": 2, "durability": 1})
	if not battle.restore_snapshot(state)["ok"]:
		push_error("Fixture must restore")
		quit(1)
	draws.clear()
	action_random = true
	return battle


func _roll(limit: int) -> int:
	if not action_random:
		return 0
	draws.append(limit)
	return draw_value


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
