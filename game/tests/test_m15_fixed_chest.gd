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
		"id": "chest_0",
		"sourceIndex": 0,
		"kind": "chest",
		"position": [actor["x"], actor["y"]],
		"tileId": 79,
		"reward": {"kind": "item", "templateId": 9},
		"openedVariant": "opened_chest"
	}
	content["map"]["locations"] = [location]
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
	for sample: Array in [[9, 5, 0, "inventory"], [18, 6, 39, "warehouse"]]:
		location["reward"]["templateId"] = sample[0]
		var battle: RefCounted = _fixture(content, sample[1], sample[2])
		if not _expect("open_chest" in battle.actions_for(0), "Fixed chest offers action"):
			return
		var result: Dictionary = battle.open_chest(0)
		if not _expect(
			(
				result.get("ok", false)
				and result.get("claimed", false)
				and draws.is_empty()
				and battle.unit(0)["action"] == 2
				and battle.event_completed("location:chest_0")
			),
			"Fixed chest claims and ends action without drawing"
		):
			return
		var loot: Dictionary = result["rewards"]["loot"][0]
		if not _expect(
			(
				loot["destination"] == sample[3]
				and loot["item"]["templateId"] == sample[0]
				and loot["item"]["id"].ends_with(":location:chest_0")
				and battle.map_state()["overlays"].size() == 1
			),
			"Fixed item reaches bag or warehouse and chest projects open"
		):
			return
		var state: Dictionary = battle.snapshot()
		if not _expect(
			not battle.open_chest(0)["ok"] and battle.snapshot() == state and draws.is_empty(),
			"Repeated input cannot claim twice"
		):
			return
		var fresh: RefCounted = _fixture(content, sample[1], sample[2])
		if not _expect(
			(
				fresh.restore_snapshot(state)["ok"]
				and fresh.snapshot() == state
				and fresh.event_completed("location:chest_0")
				and fresh.map_state()["overlays"].size() == 1
				and draws.is_empty()
			),
			"Fresh battle restores claimed item and open chest without a draw"
		):
			return
	location["reward"]["templateId"] = 9
	var full: RefCounted = _fixture(content, 6, 40)
	var result: Dictionary = full.open_chest(0)
	if not _expect(
		(
			result.get("ok", false)
			and not result.get("claimed", true)
			and result.get("reason") == "WAREHOUSE_FULL"
			and not full.event_completed("location:chest_0")
			and full.map_state()["overlays"].is_empty()
			and full.unit(0)["action"] == 2
			and draws.is_empty()
		),
		"Double full ends action without consuming or opening chest"
	):
		return
	for invalid: Variant in [0, -1, 999, 1.5, "9", null]:
		location["reward"]["templateId"] = invalid
		var battle: RefCounted = _fixture(content, 5, 0)
		var before: Dictionary = battle.snapshot()
		var failed: Dictionary = battle.open_chest(0)
		if not _expect(
			(
				not failed.get("ok", true)
				and battle.snapshot() == before
				and battle.map_state()["overlays"].is_empty()
				and draws.is_empty()
			),
			"Invalid item fails without committing action, contents or map"
		):
			return
	location["reward"] = {"kind": "item", "templateId": 9, "extra": true}
	var malformed: RefCounted = _fixture(content, 5, 0)
	var before: Dictionary = malformed.snapshot()
	if not _expect(
		(
			not malformed.open_chest(0).get("ok", true)
			and malformed.snapshot() == before
			and draws.is_empty()
		),
		"Extra reward fields fail atomically"
	):
		return
	print("PASS m15 fixed chest boundaries")
	quit(0)


func _fixture(content: Dictionary, bag: int, warehouse: int) -> RefCounted:
	record_draws = false
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
		push_error("Fixed chest fixture must restore")
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
