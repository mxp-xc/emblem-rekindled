extends SceneTree
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var draws: Array[int] = []


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
	var group: Array[int] = []
	for unit: Dictionary in content["units"]:
		if unit["faction"] == 2 and group.size() < 4:
			group.append(int(unit["id"]))
	content["story"]["locationEvents"] = [
		{"locationId": "chest_0", "unitIds": group, "sequence": ""}
	]
	var battle: RefCounted = Battle.new(content, _roll)
	var base: Dictionary = battle.snapshot()
	for unit: Dictionary in base["units"]:
		if unit["id"] in group:
			unit["visible"] = false
			unit["flags"] |= 1
	if not battle.restore_snapshot(base)["ok"]:
		fail("Hidden group fixture must restore")
		return
	var leader: Dictionary = battle.unit(group[0])
	var result: Dictionary = battle.open_chest(0)
	if (
		not result.get("locationEvent", {}).has("arrivals")
		or result["locationEvent"]["focus"] != Vector2i(leader["x"], leader["y"])
	):
		fail("Location group focuses its leader current business cell")
		return
	var arrived: Array[int] = []
	for arrival: Dictionary in result["locationEvent"]["arrivals"]:
		arrived.append(int(arrival["unit"]))
	if arrived != group or not battle.outcome.is_empty():
		fail("The complete group arrives in declared order before outcome")
		return
	for gate: String in ["dead", "visible"]:
		var state: Dictionary = base.duplicate(true)
		for unit: Dictionary in state["units"]:
			if unit["id"] == group[0]:
				if gate == "dead":
					unit["hp"] = 0
				else:
					unit["visible"] = true
					unit["flags"] &= ~1
		if not battle.restore_snapshot(state)["ok"]:
			fail("Leader gate fixture restores")
			return
		result = battle.open_chest(0)
		if not result["claimed"] or result.has("locationEvent"):
			fail("Dead or visible group leader skips the whole event but keeps reward")
			return
		for id: int in group.slice(1):
			if battle.unit(id)["visible"]:
				fail("Leader gate cannot reveal remaining members")
				return
	var center := Vector2i(-1, -1)
	var offsets: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT
	]
	for y: int in range(1, int(content["map"]["height"]) - 1):
		for x: int in range(1, int(content["map"]["width"]) - 1):
			var empty: bool = true
			for unit: Dictionary in base["units"]:
				if unit["visible"] and Vector2i(unit["x"] - x, unit["y"] - y) in offsets:
					empty = false
			if empty:
				center = Vector2i(x, y)
				break
		if center.x >= 0:
			break
	if center.x < 0:
		fail("Controlled blocker fixture needs five empty cells")
		return
	var occupied_content: Dictionary = content.duplicate(true)
	occupied_content["map"]["locations"][0]["position"] = [center.x, center.y]
	for blocked: bool in [false, true]:
		var occupied: RefCounted = Battle.new(occupied_content, _roll)
		var state: Dictionary = base.duplicate(true)
		var blocker_index: int = 1
		for unit: Dictionary in state["units"]:
			if unit["id"] == 0 or unit["id"] == group[0]:
				unit["x"] = center.x
				unit["y"] = center.y
			elif blocked and unit["id"] not in group and blocker_index < offsets.size():
				var cell: Vector2i = center + offsets[blocker_index]
				unit["x"] = cell.x
				unit["y"] = cell.y
				blocker_index += 1
		if not occupied.restore_snapshot(state)["ok"]:
			fail("Occupied location fixture restores")
			return
		result = occupied.open_chest(0)
		var event: Dictionary = result.get("locationEvent", {})
		if not result["claimed"] or event.get("focus") != center:
			fail("Blocked leader still passes gate and commits reward/focus")
			return
		if blocked:
			if occupied.unit(group[0])["visible"] or event["arrivals"].size() != 3:
				fail("Surrounded leader stays hidden while the other three arrive")
				return
		elif (
			not occupied.unit(group[0])["visible"]
			or (
				Vector2i(occupied.unit(group[0])["x"], occupied.unit(group[0])["y"])
				!= center + Vector2i.LEFT
			)
		):
			fail("Occupied leader cell tries left first")
			return
		var committed: Dictionary = occupied.snapshot()
		if (
			not occupied.restore_snapshot(committed)["ok"]
			or occupied.snapshot() != committed
			or occupied.open_chest(0)["ok"]
		):
			fail("Blocked actual arrivals persist and cannot replay")
			return
	var outcome_content: Dictionary = content.duplicate(true)
	outcome_content["story"]["outcomeRules"]["checks"] = [
		{"condition": "roundAfter", "round": 100, "kind": "victory"}
	]
	var ordered: RefCounted = Battle.new(outcome_content, _roll)
	var no_visible: Dictionary = base.duplicate(true)
	for unit: Dictionary in no_visible["units"]:
		if unit["faction"] == 2:
			unit["visible"] = false
			unit["flags"] |= 1
	if not ordered.restore_snapshot(no_visible)["ok"]:
		fail("Outcome ordering fixture restores before its rule is rebound")
		return
	outcome_content["story"]["outcomeRules"]["checks"] = [
		{"condition": "noVisibleEnemies", "faction": 2, "kind": "victory"}
	]
	ordered.adopt_content(outcome_content)
	if not ordered.open_chest(0)["claimed"] or not ordered.outcome.is_empty():
		fail("Chest group commits before the action outcome check")
		return
	print("PASS chest events: ordered complete group, leader focus, leader gates preserve reward")
	quit(0)


func _roll(limit: int) -> int:
	draws.append(limit)
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
