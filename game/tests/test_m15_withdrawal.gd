extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Events = preload("res://gameplay/battle_events.gd")


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	if not _expect(opened["ok"], "Fixture opens real chapter content"):
		return
	var content: Dictionary = opened["content"].duplicate(true)
	var target: Dictionary = {}
	for unit: Dictionary in opened["battle"].snapshot()["units"]:
		if unit["faction"] == 2 and unit["visible"] and unit["hp"] > 0:
			target = unit
			break
	if not _expect(not target.is_empty(), "Fixture has a visible enemy"):
		return
	var identity: int = target["id"]
	content["story"]["turnEvents"] = [
		{
			"id": "withdraw",
			"afterEnemyPhaseOfRound": 3,
			"unitIds": [],
			"withdrawUnitId": identity,
			"sequence": "withdraw_story"
		}
	]
	var battle: RefCounted = Battle.new(content)
	var state: Dictionary = battle.snapshot()
	state["round"] = 3
	if not _expect(battle.restore_snapshot(state)["ok"], "Controlled round restores"):
		return
	var original: Dictionary = battle.unit(identity).duplicate(true)
	var stats: Dictionary = battle.chapter_stats.duplicate(true)
	stats["rounds"] += 1
	var warehouse: Array = battle.snapshot()["warehouse"].duplicate(true)
	var result: Dictionary = _round(battle)
	if not _expect(
		result.get("ok", false) and result["events"].size() == 1,
		"Visible target produces one withdrawal event"
	):
		return
	var event: Dictionary = result["events"][0]
	var retired: Dictionary = battle.unit(identity)
	var before_retirement: Dictionary = original.duplicate(true)
	before_retirement["action"] = 2
	if not _expect(
		(
			event.get("kind") == "withdrawal"
			and event.get("sequence") == "withdraw_story"
			and event.get("unit") == before_retirement
		),
		"Presenter receives the complete pre-withdrawal unit and dialogue sequence"
	):
		return
	if not _expect(
		(
			not retired["visible"]
			and (retired["flags"] & 1) != 0
			and retired["hp"] == original["hp"]
			and retired["inventory"] == original["inventory"]
			and battle.snapshot()["warehouse"] == warehouse
			and battle.chapter_stats == stats
		),
		"Withdrawal preserves HP, inventory and statistics without combat reward"
	):
		return
	if not _expect(battle.event_completed("withdraw"), "Completed withdrawal is marked"):
		return
	var saved: Dictionary = battle.snapshot()
	if not _expect(
		(
			battle.restore_snapshot(saved)["ok"]
			and battle.snapshot() == saved
			and _round(battle)["events"].is_empty()
		),
		"Cold-style restore retains withdrawal and does not repeat"
	):
		return
	var direct: RefCounted = Events.new(content)
	var zero: Dictionary = original.duplicate(true)
	zero["hp"] = 0
	zero["visible"] = true
	zero["flags"] &= ~1
	var pre: Dictionary = direct.withdraw([zero], identity)
	if not _expect(
		pre["hp"] == 0 and not zero["visible"] and (zero["flags"] & 1) != 0,
		"Visible zero-HP target still withdraws"
	):
		return
	if not _expect(
		direct.withdraw([zero], identity).is_empty() and direct.withdraw([], identity).is_empty(),
		"Hidden or absent target skips withdrawal"
	):
		return
	print("PASS m15 conditional story withdrawal")
	quit(0)


func _round(battle: RefCounted) -> Dictionary:
	for expected: int in [1, 2, 0]:
		var result: Dictionary = battle.end_phase()
		if not _expect(
			result.get("ok", false) and battle.phase == expected, "Advance phase: " + str(result)
		):
			return {"ok": false}
		if expected == 0:
			return result
		while battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"], "Drain automatic actors"
			):
				return {"ok": false}
	return {"ok": false}


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
