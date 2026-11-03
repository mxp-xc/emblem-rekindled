extends SceneTree

const M14 = preload("res://tests/test_m14_outcomes.gd")
const Content = preload("res://app/chapter_content.gd")
const Store = preload("res://persistence/battle_store.gd")
var draws: Array[int] = []


func _initialize() -> void:
	var opened: Dictionary = M14.prepare(6, _roll)
	if not _expect(opened["ok"], "Open actual m14 after m10 settlement: " + str(opened)):
		return
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	state["round"] = 10
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["inventory"] = [{"id": "m14:mixed:staff59", "templateId": 59, "durability": 10}]
			actor["equippedInstanceId"] = ""
	if not _expect(
		battle.restore_snapshot(state)["ok"],
		"Restore controlled round10 with a legal staff59 holder"
	):
		return
	if not _expect(_round(battle), "Finish actual round10 clone wave"):
		return
	state = battle.snapshot()
	if not _expect(
		state["cloneState"]["bindings"].size() == 2, "Actual round10 creates two clones"
	):
		return
	var projected: Dictionary = Content.new().reproject(
		opened["content"], state["units"], state["cloneState"], state.get("summonState", {})
	)
	if not _expect(
		projected["ok"],
		"Bind actual clone presentation before the summon: " + str(projected.get("error"))
	):
		return
	battle.adopt_content(projected)
	if not _expect(
		battle.can_summon(9, "m14:mixed:staff59"),
		"Actual player cleric can use staff59 at its deployed location"
	):
		return
	var summoned: Dictionary = battle.summon_unit(9, "m14:mixed:staff59")
	if not _expect(
		summoned["ok"] and summoned["births"].size() == 1,
		"Legal summon command creates one unit: " + str(summoned)
	):
		return
	var summoned_id: int = int(summoned["births"][0]["unit"])
	if not _expect(_round(battle), "Finish actual round11 clone wave after the summon"):
		return
	state = battle.snapshot()
	var clone_bindings: Array = state["cloneState"]["bindings"]
	var summon_bindings: Array = state["summonState"]["bindings"]
	if not _expect(
		(
			clone_bindings.size() == 4
			and summon_bindings.size() == 1
			and summon_bindings[0]["unitId"] == summoned_id
			and summon_bindings[0]["afterCloneGeneration"] == 2
		),
		"Summon is anchored between two actual clone waves"
	):
		return
	var expected_order: Array[int] = []
	for binding: Dictionary in clone_bindings.slice(0, 2):
		expected_order.append(int(binding["unitId"]))
	expected_order.append(summoned_id)
	for binding: Dictionary in clone_bindings.slice(2, 4):
		expected_order.append(int(binding["unitId"]))
	var encoded: Dictionary = Store.new(projected).encode(battle)
	if not _expect(encoded["ok"], "Encode stable mixed births: " + str(encoded)):
		return
	var record: Dictionary = JSON.parse_string(JSON.stringify(encoded["record"]))
	draws.clear()
	var cold: Dictionary = Store.new(opened["previousContent"]).decode(record, _roll)
	if not _expect(
		cold["ok"] and draws.is_empty(),
		"Fresh Store/Session reads mixed JSON without random draws: " + str(cold.get("error"))
	):
		return
	if not _expect(
		(
			cold["battle"].snapshot() == state
			and cold["content"]["unitOrder"].slice(-5) == expected_order
		),
		"Cold read preserves full dynamic identities, held items, bindings and interleaved order"
	):
		return
	print("PASS m14 clone/summon mixed identity and cold interleaved order")
	quit(0)


func _round(battle: RefCounted) -> bool:
	for expected: int in [1, 2, 0]:
		var result: Dictionary = battle.end_phase()
		if not _expect(
			result["ok"] and battle.phase == expected, "Advance actual m14 phases: " + str(result)
		):
			return false
		while expected != 0 and battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"],
				"Drain automatic actions without combat"
			):
				return false
	return true


func _roll(limit: int) -> int:
	draws.append(limit)
	return 0


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
