extends SceneTree

const M14 = preload("res://tests/test_m14_outcomes.gd")
const Store = preload("res://persistence/battle_store.gd")
var draws: Array[int] = []
var choice: int = 0


func _initialize() -> void:
	var opened: Dictionary = M14.prepare(6, _roll)
	if not _expect(
		opened["ok"], "Actual m10 progress opens m14 for clone schedule: " + str(opened)
	):
		return
	var battle: RefCounted = opened["battle"]
	if not _expect(not battle.unit(112)["visible"], "Original source112 starts hidden"):
		return
	var state: Dictionary = battle.snapshot()
	state["round"] = 9
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore controlled round-nine boundary"):
		return
	draws.clear()
	var ninth: Dictionary = _round(battle)
	if not _expect(
		ninth["ok"] and not draws.has(8) and battle.snapshot()["cloneState"]["bindings"].is_empty(),
		(
			"Round9 creates no clones and makes no template draws: result=%s draws=%s cloneState=%s"
			% [str(ninth), str(draws), str(battle.snapshot()["cloneState"])]
		)
	):
		return
	choice = 0
	draws.clear()
	var tenth: Dictionary = _round(battle)
	if not _expect(
		tenth["ok"] and draws.filter(func(limit: int) -> bool: return limit == 8) == [8, 8],
		"Round10 draws two independent template choices"
	):
		return
	var bindings: Array = battle.snapshot()["cloneState"]["bindings"]
	if not _expect(
		(
			bindings.size() == 2
			and battle.unit(105)["sourceId"] == 107
			and battle.unit(106)["sourceId"] == 107
		),
		"Repeated107 creates two independently bound family members"
	):
		return
	choice = 5
	draws.clear()
	var eleventh: Dictionary = _round(battle)
	if not _expect(
		eleventh["ok"] and draws.filter(func(limit: int) -> bool: return limit == 8) == [8, 8],
		"Round11 draws twice independently"
	):
		return
	state = battle.snapshot()
	if not _expect(
		(
			state["cloneState"]["bindings"].size() == 4
			and battle.unit(115)["sourceId"] == 112
			and battle.unit(116)["sourceId"] == 112
			and not battle.unit(112)["visible"]
		),
		"Hidden112 can be chosen twice without revealing the original"
	):
		return
	var store: RefCounted = Store.new(opened["content"])
	var encoded: Dictionary = store.encode(battle)
	if not _expect(encoded["ok"], "Stable clone state encodes: " + str(encoded)):
		return
	draws.clear()
	var cold: Dictionary = Store.new(opened["previousContent"]).decode(
		JSON.parse_string(JSON.stringify(encoded["record"])), _roll
	)
	if not _expect(
		cold["ok"] and draws.is_empty() and cold["battle"].snapshot() == state,
		"Fresh Store/Session preserves clone identities, family order and event history without draws"
	):
		return
	print("PASS actual m14 round9/10/11 clone schedule and cold family identity")
	quit(0)


func _round(battle: RefCounted) -> Dictionary:
	for expected: int in [1, 2, 0]:
		var result: Dictionary = battle.end_phase()
		if not _expect(
			result["ok"] and battle.phase == expected,
			"Advance controlled m14 phase: " + str(result)
		):
			return {"ok": false}
		if expected == 0:
			return result
		while battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"],
				"Drain automatic actors without fixture combat"
			):
				return {"ok": false}
	return {"ok": false}


func _roll(limit: int) -> int:
	draws.append(limit)
	return mini(choice, limit - 1)


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
