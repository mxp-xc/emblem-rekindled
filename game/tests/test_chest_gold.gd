extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Rewards = preload("res://features/battle/reward_timeline.gd")
var draw: int = 0
var limits: Array[int] = []


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
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
	content["map"]["locations"] = [
		{
			"id": "chest_0",
			"sourceIndex": 0,
			"kind": "chest",
			"position": [actor["x"], actor["y"]],
			"tileId": 79,
			"openedVariant": "opened_chest",
			"reward": {"kind": "goldRange", "minimum": 1, "maximum": 2000}
		}
	]
	for test: Array in [
		[0, 1000, 1], [1999, 1000, 2000], [1999, Battle.MAX_GOLD - 1, 1], [2000, 1000, -1]
	]:
		var sample: int = test[0]
		draw = 0
		var battle: RefCounted = Battle.new(content, _roll)
		var state: Dictionary = battle.snapshot()
		state["gold"] = test[1]
		var item: Dictionary = battle.unit(0)["inventory"][0].duplicate(true)
		for unit: Dictionary in state["units"]:
			if unit["id"] == 0:
				while unit["inventory"].size() < 6:
					var held: Dictionary = item.duplicate(true)
					held["id"] = "bag:%d" % unit["inventory"].size()
					unit["inventory"].append(held)
		for index: int in range(40):
			var held: Dictionary = item.duplicate(true)
			held["id"] = "warehouse:%d" % index
			state["warehouse"].append(held)
		if not _check(battle.restore_snapshot(state)["ok"], "Restore full-capacity fixture"):
			return
		draw = sample
		limits.clear()
		var before: Dictionary = battle.snapshot()
		var result: Dictionary = battle.open_chest(0)
		if sample == 2000:
			if not _check(
				(
					not result["ok"]
					and result["error"] == "INVALID_RANDOM_RESULT"
					and battle.snapshot() == before
				),
				"Invalid RNG cannot mutate chest"
			):
				return
		else:
			if not _check(
				(
					result["ok"]
					and result["claimed"]
					and result["reward"] == {"kind": "gold", "amount": test[2]}
					and battle.gold == test[1] + test[2]
					and battle.event_completed("location:chest_0")
					and battle.map_state()["overlays"].size() == 1
					and battle.unit(0)["action"] == 2
					and limits == [2000]
				),
				"Gold chest opens even at full inventory and clamps the credited amount"
			):
				return
			var feedback: Array = Rewards.sequence(result, [], {}, true)
			if not _check(
				feedback.size() == 1 and feedback[0]["secondLine"] == "%d金" % test[2],
				"Gold chest reports credited gold"
			):
				return
	print("PASS gold chest: full capacity, random bounds, cap and feedback")
	quit(0)


func _roll(limit: int) -> int:
	limits.append(limit)
	return draw


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
