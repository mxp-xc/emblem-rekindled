extends SceneTree
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var draws: Array[int] = []
var reward_draw: int = 0


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
	content["map"]["locations"] = [
		{
			"id": "chest_0",
			"sourceIndex": 0,
			"kind": "chest",
			"position": [actor["x"], actor["y"]],
			"tileId": 79,
			"weightedChoices": [{"templateId": 2, "weight": 100}],
			"openedVariant": "opened_chest"
		}
	]
	var costs: Dictionary = {}
	for group: int in range(11):
		costs[str(group)] = 1
	content["map"]["tileVariants"] = {
		"opened_chest":
		{
			"tileId": 88,
			"terrain": 1,
			"texture": content["entry"]["mapTexture"],
			"movementCosts": costs
		}
	}
	var battle: RefCounted = Battle.new(content, _roll)
	draws.clear()
	if "open_chest" not in battle.actions_for(0):
		fail("A ready blue unit on an unopened chest must offer the explicit action")
		return
	var before: int = battle.unit(0)["inventory"].size()
	var result: Dictionary = battle.open_chest(0)
	if (
		not result["ok"]
		or not result["claimed"]
		or battle.unit(0)["inventory"].size() != before + 1
	):
		fail("A successful action must claim one held item")
		return
	if (
		draws != [100]
		or battle.unit(0)["action"] != 2
		or not battle.event_completed("location:chest_0")
	):
		fail("Claim commits once, draws once and ends the action")
		return
	if battle.open_chest(0)["ok"] or draws != [100]:
		fail("Repeated input cannot claim or draw again")
		return
	var fresh: RefCounted = Battle.new(content, _roll)
	var closed: Dictionary = fresh.snapshot()
	var full: Dictionary = closed.duplicate(true)
	var sample: Dictionary = fresh.unit(0)["inventory"][0].duplicate(true)
	for unit: Dictionary in full["units"]:
		if unit["id"] == 0:
			while unit["inventory"].size() < 6:
				var held: Dictionary = sample.duplicate(true)
				held["id"] = "bag:%d" % unit["inventory"].size()
				unit["inventory"].append(held)
	for i: int in range(40):
		var held: Dictionary = sample.duplicate(true)
		held["id"] = "warehouse:%d" % i
		full["warehouse"].append(held)
	if not fresh.restore_snapshot(full)["ok"]:
		fail("Full capacity fixture must be a valid public snapshot")
		return
	draws.clear()
	var failure: Dictionary = fresh.open_chest(0)
	if (
		not failure["ok"]
		or failure["claimed"]
		or failure.get("reason") != "WAREHOUSE_FULL"
		or not draws.is_empty()
	):
		fail("Double full executes without claiming or drawing")
		return
	if (
		fresh.unit(0)["action"] != 2
		or fresh.event_completed("location:chest_0")
		or fresh.map_state()["overlays"].size() != 0
	):
		fail("Double full ends action but keeps chest and map unopened")
		return
	full["warehouse"].pop_back()
	if (
		not fresh.restore_snapshot(full)["ok"]
		or not fresh.open_chest(0)["claimed"]
		or fresh.snapshot()["warehouse"].size() != 40
	):
		fail("After renewed action eligibility one free warehouse slot receives the reward")
		return
	var movement: RefCounted = Battle.new(content, _roll)
	draws.clear()
	var original: Dictionary = movement.snapshot()
	var cell := Vector2i(actor["x"], actor["y"])
	if (
		not movement.move_unit(0, cell)["ok"]
		or movement.event_completed("location:chest_0")
		or not movement.cancel_move()["ok"]
	):
		fail("Move and cancel at the chest never claim it")
		return
	if (
		not movement.wait_unit(0)["ok"]
		or movement.event_completed("location:chest_0")
		or not draws.is_empty()
	):
		fail("Waiting at a chest does not draw or consume it")
		return
	if (
		not movement.restore_snapshot(original)["ok"]
		or not movement.move_unit(0, cell)["ok"]
		or not movement.open_chest(0)["claimed"]
		or not movement.snapshot()["pending_move"].is_empty()
	):
		fail("Opening after a move consumes action and clears pending movement")
		return
	for table: Array in [[39, 33, 30], [2, 10, 70], [15, 19, 70], [25, 27, 70]]:
		content["map"]["locations"][0]["weightedChoices"] = [
			{"templateId": table[0], "weight": table[2]},
			{"templateId": table[1], "weight": 100 - table[2]}
		]
		for sample_value: int in [0, table[2] - 1, table[2], 99]:
			reward_draw = 0
			var weighted: RefCounted = Battle.new(content, _roll)
			reward_draw = sample_value
			draws.clear()
			var claim: Dictionary = weighted.open_chest(0)
			var expected: int = table[0] if sample_value < table[2] else table[1]
			if (
				not claim["claimed"]
				or claim["rewards"]["loot"][0]["item"]["templateId"] != expected
				or draws != [100]
			):
				fail("Native weighted choices keep cumulative boundaries and one draw")
				return
	content["map"]["locations"][0]["weightedChoices"] = [
		{"templateId": 9, "weight": 30},
		{"templateId": 18, "weight": 30},
		{"templateId": 60, "weight": 30}
	]
	content["map"]["locations"][0]["emptyWeight"] = 10
	var full_stock_item: Dictionary = sample.duplicate(true)
	full_stock_item["id"] = "warehouse:39"
	full["warehouse"].append(full_stock_item)
	for sample_value: int in [89, 90, 99]:
		reward_draw = 0
		var weighted: RefCounted = Battle.new(content, _roll)
		if not weighted.restore_snapshot(full)["ok"]:
			fail("Full-capacity weighted chest fixture must restore")
			return
		reward_draw = sample_value
		draws.clear()
		var claim: Dictionary = weighted.open_chest(0)
		var empty: bool = sample_value >= 90
		if (
			not claim["ok"]
			or claim["claimed"] != empty
			or weighted.event_completed("location:chest_0") != empty
			or weighted.map_state()["overlays"].size() != (1 if empty else 0)
			or weighted.unit(0)["action"] != 2
			or draws != [100]
		):
			fail("Empty weighted chest opens even when full; a real item remains unclaimed")
			return
	print("PASS chest actions: explicit claim, one draw, action consumption, duplicate rejection")
	quit(0)


func _roll(limit: int) -> int:
	draws.append(limit)
	return reward_draw


func fail(message: String) -> void:
	push_error(message)
	quit(1)
