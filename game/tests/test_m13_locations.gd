extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var draws: Array[int] = []
var next_draw: int = 99


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
	content["map"]["locations"] = [
		{
			"id": "visit_0",
			"sourceIndex": 0,
			"kind": "visit",
			"position": [actor["x"], actor["y"]],
			"tileId": 58,
			"reward": {"kind": "weightedItem", "weightedChoices": [{"templateId": 2, "weight": 90}]}
		}
	]
	var battle: RefCounted = Battle.new(content, _roll)
	draws.clear()
	if "visit_location" not in battle.actions_for(0):
		fail("Ready actor standing on a visit location must have the visit command")
		return
	var before: Dictionary = battle.unit(0)
	var result: Dictionary = battle.visit_location(0)
	if not result["ok"] or not result["claimed"] or result.get("reward", {}).get("kind") != "empty":
		fail("The unassigned part of a 100-point reward table is a successful empty visit")
		return
	if (
		draws != [100]
		or battle.unit(0)["action"] != 2
		or not battle.event_completed("location:visit_0")
	):
		fail("An empty visit consumes the location and action exactly once")
		return
	if battle.unit(0)["inventory"] != before["inventory"]:
		fail("Empty visits create no held item")
		return
	if (
		battle.map_state()["map"]["tiles"] != content["map"]["tiles"]
		or not battle.map_state()["overlays"].is_empty()
	):
		fail("Visit locations keep the tactical tiles unchanged")
		return
	if battle.visit_location(0)["ok"] or draws != [100]:
		fail("Repeated visit input cannot draw or claim again")
		return
	for boundary: int in [19, 20, 89, 90, 99]:
		var weighted: Dictionary = {
			"kind": "weightedItem",
			"weightedChoices": [{"templateId": 1, "weight": 20}, {"templateId": 2, "weight": 70}]
		}
		var candidate: RefCounted = _fixture(content, weighted, boundary, 0, 0)
		var visited: Dictionary = candidate.visit_location(0)
		var expected: int = 1 if boundary == 19 else (2 if boundary < 90 else -1)
		if not visited["ok"] or not visited["claimed"] or draws != [100]:
			fail("Weighted visits use exactly the fixed 100-point interval")
			return
		if (
			(expected < 0 and visited["reward"]["kind"] != "empty")
			or (expected > 0 and visited["reward"].get("templateId") != expected)
		):
			fail("Weighted reward boundaries preserve authored interval order")
			return
	var second_location: Dictionary = content.duplicate(true)
	second_location["map"]["locations"][0]["id"] = "visit_1"
	for sample: Array in [
		[9, 68], [10, 69], [19, 69], [20, 70], [29, 70], [30, 71], [39, 71], [40, -1]
	]:
		var candidate: RefCounted = _fixture(
			second_location,
			{
				"kind": "weightedItem",
				"weightedChoices":
				[
					{"templateId": 68, "weight": 10},
					{"templateId": 69, "weight": 10},
					{"templateId": 70, "weight": 10},
					{"templateId": 71, "weight": 10}
				]
			},
			int(sample[0]),
			0,
			0
		)
		var visited: Dictionary = candidate.visit_location(0)
		if not visited["ok"] or not visited["claimed"] or draws != [100]:
			fail(
				"The second location uses four authored ten-point intervals within a 100-point draw"
			)
			return
		if (
			(int(sample[1]) < 0 and visited["reward"]["kind"] != "empty")
			or (int(sample[1]) > 0 and visited["reward"].get("templateId") != int(sample[1]))
		):
			fail("Second-location interval boundaries select 68, 69, 70, 71, then empty")
			return
	if not _unconfirmed_actions(content):
		return
	if not _visit_clears_move(content, false) or not _visit_clears_move(content, true):
		return
	for bag: int in [5, 6]:
		for warehouse: int in [39, 40]:
			var candidate: RefCounted = _fixture(
				content, {"kind": "item", "templateId": 2}, 0, bag, warehouse
			)
			var visited: Dictionary = candidate.visit_location(0)
			var claimed: bool = bag == 5 or warehouse == 39
			if (
				not visited["ok"]
				or visited["claimed"] != claimed
				or candidate.unit(0)["action"] != 2
				or not draws.is_empty()
			):
				fail("Fixed items use no RNG and bag/warehouse capacity decides only the claim")
				return
			if candidate.event_completed("location:visit_0") != claimed:
				fail("A capacity failure ends action while keeping the visit available")
				return
	for boundary: int in [0, 499]:
		var candidate: RefCounted = _fixture(
			content, {"kind": "goldRange", "minimum": 1, "maximum": 500}, boundary, 6, 40
		)
		var previous: int = candidate.gold
		var visited: Dictionary = candidate.visit_location(0)
		if (
			not visited["claimed"]
			or visited["reward"] != {"kind": "gold", "amount": boundary + 1}
			or candidate.gold != previous + boundary + 1
			or draws != [500]
		):
			fail(
				"Gold includes both endpoints and succeeds even when both storage locations are full"
			)
			return
	var full_empty: RefCounted = _fixture(
		content,
		{"kind": "weightedItem", "weightedChoices": [{"templateId": 2, "weight": 90}]},
		99,
		6,
		40
	)
	if not full_empty.visit_location(0)["claimed"] or draws != [100]:
		fail("An empty draw must be determined before storage capacity is checked")
		return
	var capped: RefCounted = _fixture(
		content, {"kind": "goldRange", "minimum": 1, "maximum": 500}, 499, 6, 40
	)
	capped.gold = 9999999
	if (
		capped.visit_location(0)["reward"] != {"kind": "gold", "amount": 0}
		or not capped.event_completed("location:visit_0")
	):
		fail("At the gold cap the visit still consumes once and reports the actual increment")
		return
	var invalid: RefCounted = _fixture(
		content, {"kind": "goldRange", "minimum": 1, "maximum": 500}, -1, 0, 0
	)
	var unchanged: Dictionary = invalid.snapshot()
	if invalid.visit_location(0)["ok"] or invalid.snapshot() != unchanged:
		fail("An invalid injected random result must fail without a partial action commit")
		return
	var saved: Dictionary = full_empty.snapshot()
	draws.clear()
	if (
		not full_empty.restore_snapshot(JSON.parse_string(JSON.stringify(saved)))["ok"]
		or not draws.is_empty()
		or not full_empty.map_state()["overlays"].is_empty()
	):
		fail("Consumed visits restore from JSON with no draw and no chest projection")
		return
	print("PASS m13 locations: empty visit consumes once and preserves map")
	quit(0)


func _roll(limit: int) -> int:
	draws.append(limit)
	return mini(next_draw, limit - 1)


func _unconfirmed_actions(content: Dictionary) -> bool:
	var candidate: RefCounted = _fixture(
		content,
		{"kind": "weightedItem", "weightedChoices": [{"templateId": 2, "weight": 90}]},
		99,
		0,
		0
	)
	var before: Dictionary = candidate.snapshot()
	for repetition: int in range(3):
		if "visit_location" not in candidate.actions_for(0):
			fail("Repeated menu reads keep the unconsumed visit action available")
			return false
		candidate.map_state()
		candidate.unit_information(0)
	if candidate.snapshot() != before or not draws.is_empty():
		fail("Reading action and map information cannot draw a reward or change the battle")
		return false
	var actor: Dictionary = candidate.unit(0)
	var cell := Vector2i(actor["x"], actor["y"])
	if not candidate.move_unit(0, cell)["ok"] or not candidate.cancel_move()["ok"]:
		fail("A movement preview can be cancelled before confirming a visit")
		return false
	if candidate.snapshot() != before or not draws.is_empty():
		fail("Cancelling movement on a visit location leaves its reward and action unconsumed")
		return false
	if (
		not candidate.wait_unit(0)["ok"]
		or candidate.event_completed("location:visit_0")
		or not draws.is_empty()
	):
		fail("Waiting on a visit location does not claim it or draw a future reward")
		return false
	return true


func _visit_clears_move(content: Dictionary, full: bool) -> bool:
	var candidate: RefCounted = _fixture(
		content,
		{"kind": "weightedItem", "weightedChoices": [{"templateId": 2, "weight": 90}]},
		0 if full else 99,
		6 if full else 0,
		40 if full else 0
	)
	var actor: Dictionary = candidate.unit(0)
	if not candidate.move_unit(0, Vector2i(actor["x"], actor["y"]))["ok"]:
		fail("A legal visit may follow a pending move by the same actor")
		return false
	if candidate.snapshot()["pending_move"].is_empty():
		fail("The fixture must exercise an actual pending move before visiting")
		return false
	var visited: Dictionary = candidate.visit_location(0)
	if (
		not visited["ok"]
		or visited["claimed"] == full
		or candidate.unit(0)["action"] != 2
		or not candidate.snapshot()["pending_move"].is_empty()
		or draws != [100]
	):
		fail(
			"Both successful and capacity-failed visit attempts finish the action and clear its pending move"
		)
		return false
	if candidate.event_completed("location:visit_0") == full:
		fail("Only the successful visit consumes the location after movement")
		return false
	return true


func _fixture(
	source: Dictionary, reward: Dictionary, draw: int, bag: int, warehouse: int
) -> RefCounted:
	var content: Dictionary = source.duplicate(true)
	content["map"]["locations"][0]["reward"] = reward
	next_draw = maxi(draw, 0)
	var battle: RefCounted = Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] != 0:
			continue
		actor["inventory"] = []
		actor["equippedInstanceId"] = ""
		for index: int in range(bag):
			actor["inventory"].append(
				{"id": "visit_bag_%d" % index, "templateId": 2, "durability": 1}
			)
	state["warehouse"] = []
	for index: int in range(warehouse):
		state["warehouse"].append(
			{"id": "visit_warehouse_%d" % index, "templateId": 2, "durability": 1}
		)
	if not battle.restore_snapshot(state)["ok"]:
		fail("Visit capacity fixture must restore through the public snapshot boundary")
	next_draw = draw
	draws.clear()
	return battle


func fail(message: String) -> void:
	push_error(message)
	quit(1)
