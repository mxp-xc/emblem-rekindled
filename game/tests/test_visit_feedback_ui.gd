extends SceneTree

const Rewards = preload("res://features/battle/reward_timeline.gd")


func _initialize() -> void:
	var empty: Array = Rewards.sequence(
		{"kind": "visit", "actor": 0, "claimed": true, "reward": {"kind": "empty"}}, [], {}, true
	)
	if empty.size() != 1 or empty[0]["text"] != "(空)":
		fail("An empty visit must visibly report its committed result")
		return
	var gold: Array = Rewards.sequence(
		{"kind": "visit", "actor": 0, "claimed": true, "reward": {"kind": "gold", "amount": 0}},
		[],
		{},
		true
	)
	if gold.size() != 1 or gold[0]["secondLine"] != "0金":
		fail("A capped gold visit must show its actual credited amount")
		return
	var full: Array = Rewards.sequence(
		{"kind": "visit", "actor": 0, "claimed": false, "reason": "WAREHOUSE_FULL"}, [], {}, true
	)
	if full.size() != 1 or full[0]["text"] != "仓库已满":
		fail("A failed item visit must report the capacity outcome")
		return
	print("PASS visit feedback: empty, credited gold, capacity failure")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
