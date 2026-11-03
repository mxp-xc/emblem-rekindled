extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const M11 = preload("res://tests/test_m11_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var draws: int = 0


func _initialize() -> void:
	var context: Dictionary = M11.CONTEXTS[0]
	var prepared: Dictionary = M11.prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare controlled m11 route"):
		return
	var prior: Dictionary = Session.new().open(CHAPTER, "m11", prepared["source"], _roll)
	if not _expect(
		prior["ok"] and prior["battle"].win_with_assistance()["ok"], "Open and settle m11"
	):
		return
	var progress: Dictionary = prior["battle"].complete_victory(0)
	if not _expect(progress["ok"], "Produce m11 progress"):
		return
	var opened: Dictionary = Session.new().open(
		CHAPTER, "m15", {"progress": progress["progress"]}, _roll
	)
	if not _expect(opened["ok"], "Open actual m15: " + str(opened)):
		return
	var path: String = "user://m15_chests_%d.json" % Time.get_ticks_usec()
	var store: RefCounted = Store.new(opened["content"], path)
	var initial: Dictionary = opened["battle"].snapshot()
	for sample: Array in [["chest_0", 1, 0, 9], ["chest_9", 21, 0, 18]]:
		if not _case(opened["battle"], initial, store, prior["content"], sample):
			return
	DirAccess.remove_absolute(path)
	print("PASS m15 actual chest Store cold reads: fixed rewards and capacity retry")
	quit(0)


func _case(
	battle: RefCounted, initial: Dictionary, store: RefCounted, previous: Dictionary, sample: Array
) -> bool:
	var state: Dictionary = initial.duplicate(true)
	state["warehouse"] = []
	for index: int in range(40):
		state["warehouse"].append(
			{"id": "m15:warehouse:%d" % index, "templateId": 2, "durability": 1}
		)
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = sample[1]
			actor["y"] = sample[2]
			actor["action"] = 0
			actor["inventory"] = []
			actor["equippedInstanceId"] = ""
			for index: int in range(6):
				actor["inventory"].append(
					{"id": "m15:bag:%d" % index, "templateId": 2, "durability": 1}
				)
		elif actor["visible"] and actor["x"] == sample[1] and actor["y"] == sample[2]:
			actor["visible"] = false
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore actual chest double-full boundary"
	):
		return false
	var cold: Dictionary = _cold(store, previous, battle)
	if not _expect(cold["ok"], "Fresh unclaimed chest reads"):
		return false
	var current: RefCounted = cold["battle"]
	draws = 0
	var full: Dictionary = current.open_chest(0)
	if not _expect(
		(
			full.get("ok", false)
			and not full.get("claimed", true)
			and full.get("reason") == "WAREHOUSE_FULL"
			and draws == 0
			and not current.event_completed("location:" + sample[0])
		),
		"Double full leaves fixed chest unopened with no draw"
	):
		return false
	cold = _cold(store, previous, current)
	if not _expect(
		cold["ok"] and not cold["battle"].event_completed("location:" + sample[0]),
		"Fresh failed-capacity state remains unclaimed"
	):
		return false
	current = cold["battle"]
	state = current.snapshot()
	state["warehouse"].pop_back()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
	if not _expect(
		current.restore_snapshot(state)["ok"], "Restore next action with one warehouse slot"
	):
		return false
	draws = 0
	var claimed: Dictionary = current.open_chest(0)
	if not _expect(
		(
			claimed.get("ok", false)
			and claimed.get("claimed", false)
			and draws == 0
			and claimed["rewards"]["loot"][0]["item"]["templateId"] == sample[3]
			and claimed["rewards"]["loot"][0]["destination"] == "warehouse"
		),
		"Retry obtains the actual fixed item without drawing"
	):
		return false
	cold = _cold(store, previous, current)
	if not _expect(
		cold["ok"] and cold["battle"].event_completed("location:" + sample[0]),
		"Fresh claimed chest keeps consumed marker"
	):
		return false
	current = cold["battle"]
	state = current.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
	if not _expect(current.restore_snapshot(state)["ok"], "Restore next action after cold claim"):
		return false
	draws = 0
	var before: Dictionary = current.snapshot()
	var again: Dictionary = current.open_chest(0)
	return _expect(
		not again.get("ok", true) and current.snapshot() == before and draws == 0,
		"Claimed chest cannot be opened or rewarded again"
	)


func _cold(store: RefCounted, previous: Dictionary, battle: RefCounted) -> Dictionary:
	if not store.write(battle)["ok"]:
		return {"ok": false}
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	if not record is Dictionary:
		return {"ok": false}
	draws = 0
	var restored: Dictionary = Store.new(previous).decode(record, _roll)
	if (
		not restored.get("ok", false)
		or draws != 0
		or restored["battle"].snapshot() != battle.snapshot()
	):
		return {"ok": false, "reason": "Cold read changed state or drew random"}
	return restored


func _roll(_limit: int) -> int:
	draws += 1
	return 0


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
