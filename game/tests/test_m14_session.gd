extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const Content = preload("res://app/chapter_content.gd")
const M10 = preload("res://tests/test_m10_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var draws: int = 0


func _initialize() -> void:
	if not _route(M10.CONTEXTS[1]):
		return
	print("PASS m14 Session/Store: first route, pickup and completed world cold reads")
	quit(0)


func _route(context: Dictionary) -> bool:
	var prepared: Dictionary = M10.prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare controlled m10 route: " + str(prepared)):
		return false
	var prior: Dictionary = Session.new().open(CHAPTER, "m10", prepared["source"], _roll)
	if not _expect(prior["ok"], "Open actual m10: " + str(prior)):
		return false
	if not _expect(prior["battle"].win_with_assistance()["ok"], "Settle m10 victory"):
		return false
	var completed: Dictionary = prior["battle"].complete_victory(int(context["route"]))
	if not _expect(completed["ok"], "m10 produces progress for m14"):
		return false
	completed["progress"]["commandPolicy"] = 5
	var opened: Dictionary = Session.new().open(
		CHAPTER, "m14", {"progress": completed["progress"]}, _roll
	)
	if not _expect(opened["ok"], "Actual m10 progress opens m14: " + str(opened)):
		return false
	if not _growth_boundaries(opened):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	if not _expect(
		(
			state["campaign"]["route"] == context["route"]
			and state["campaign"]["worldStep"] == 9
			and state["commander"] == -1
			and state["commandPolicy"] == 5
		),
		"m14 retains route, world step and policy while clearing commander"
	):
		return false
	var path: String = "user://m14_session_%d_%d.json" % [Time.get_ticks_usec(), context["route"]]
	var store: RefCounted = Store.new(opened["content"], path)
	if not _cold_battle(store, prior["content"], battle):
		return false
	if not _pickup_capacity(store, prior["content"], battle):
		return false
	# A stable controlled state models two prior elemental knockdowns and a pickup.
	# The production restore path must preserve both without initialization or draws.
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] in [92, 93]:
			actor["hp"] = 1
			actor["flags"] |= 64
		elif actor["id"] == 94:
			actor["x"] = 5
			actor["y"] = 1
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
			actor["attributes"]["magic"] = 0
		elif actor["id"] == 0:
			actor["x"] = 4
			actor["y"] = 1
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
			actor["inventory"] = [{"id": "m14:controlled:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m14:controlled:sword"
		elif actor["id"] == 9:
			actor["x"] = 3
			actor["y"] = 1
			actor["action"] = 0
			actor["inventory"] = []
			actor["equippedInstanceId"] = ""
		elif actor["visible"] and actor["x"] in [3, 4, 5] and actor["y"] == 1:
			actor["visible"] = false
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore stable partial elemental fixture"
	):
		return false
	var waited: Dictionary = battle.wait_unit(9)
	if not _expect(
		waited["ok"] and waited.get("location", {}).get("claimed", false),
		"Wait claims the fixed location"
	):
		return false
	if not _cold_battle(store, prior["content"], battle):
		return false
	var saved: Dictionary = store.encode(battle)
	var cold: Dictionary = Store.new(prior["content"]).decode(
		JSON.parse_string(JSON.stringify(saved["record"])), _roll
	)
	if not _expect(
		(
			cold["battle"].unit(92)["hp"] == 1
			and (cold["battle"].unit(92)["flags"] & 64) != 0
			and cold["battle"].event_completed("location:wait_0")
		),
		"Cold read preserves partial knockdown and consumed pickup"
	):
		return false
	var final_hit: Dictionary = cold["battle"].attack_unit(0, 94)
	if not _expect(
		(
			final_hit["ok"]
			and not cold["battle"].unit(92)["visible"]
			and not cold["battle"].unit(93)["visible"]
			and not cold["battle"].unit(94)["visible"]
		),
		(
			"Cold partial knockdowns continue into final group retirement: result=%s actor=%s group=%s"
			% [
				str(final_hit),
				str(cold["battle"].unit(0)),
				str([cold["battle"].unit(92), cold["battle"].unit(93), cold["battle"].unit(94)])
			]
		)
	):
		return false
	# Use the existing assistance command to reach a legal completed world, not a victory battle save.
	if not _expect(battle.win_with_assistance()["ok"], "Complete m14 with assistance"):
		return false
	var finish: Dictionary = battle.complete_victory(int(context["route"]))
	if not _expect(finish["ok"], "m14 settlement produces completion progress"):
		return false
	var progress: Dictionary = finish["progress"]
	if not _expect(
		(
			progress["chapterCompleted"]
			and progress["worldStep"] == 10
			and progress["completedBattle"] == "m14"
		),
		"Completion retains terminal identity"
	):
		return false
	if not _expect(store.write_progress(progress)["ok"], "Write completed continue"):
		return false
	var original: String = FileAccess.get_file_as_string(path)
	for slot: int in range(4):
		var variant: Dictionary = progress.duplicate(true)
		variant["elapsedMinutes"] = 100 + slot
		if not _expect(store.write_slot(slot, variant)["ok"], "Write completion slot"):
			return false
	for slot: int in range(4):
		var read: Dictionary = Store.new(prior["content"], path).read_slot(slot)
		if not _expect(
			(
				read["ok"]
				and read["progress"]["elapsedMinutes"] == 100 + slot
				and read["progress"]["chapterResult"] == progress["chapterResult"]
			),
			"Fresh slot preserves its metadata and completion result"
		):
			return false
		DirAccess.remove_absolute(path.get_basename() + "_slot_%d.json" % (slot + 1))
	var read: Dictionary = Store.new(prior["content"], path).read()
	if not _expect(
		(
			read["ok"]
			and read["progress"] == progress
			and FileAccess.get_file_as_string(path) == original
		),
		"Cold continue and slot reads preserve the completed world"
	):
		return false
	if not _expect(
		(
			Session.new().open(CHAPTER, "m14", {"progress": read["progress"]}).get("error")
			== "CHAPTER_ALREADY_COMPLETED"
		),
		"Completed world cannot start another battle"
	):
		return false
	DirAccess.remove_absolute(path)
	return true


func _growth_boundaries(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var loader := Content.new()
	var source: Dictionary = {}
	for spawn: Dictionary in content["spawns"]:
		if spawn.get("growthTemplateId") == 20 and spawn.get("classId") == 40:
			source = spawn
			break
	if not _expect(not source.is_empty(), "Actual m14 exposes the elemental spawn growth boundary"):
		return false
	if not _expect(
		loader._spawn_references_valid([source], content["rules"])["ok"],
		"Enemy level20 group10 explicit elemental stats permit derived growth20"
	):
		return false
	for mutation: Dictionary in [
		{"level": 19}, {"classId": 0}, {"faction": 0}, {"growthTemplateId": 255}
	]:
		var bad: Dictionary = source.duplicate(true)
		bad.merge(mutation, true)
		if not _expect(
			not loader._spawn_references_valid([bad], content["rules"])["ok"],
			"Missing growth template is rejected outside the elemental boundary: " + str(mutation)
		):
			return false
	var record: Dictionary = Store.new(content).encode(opened["battle"])
	if not _expect(record["ok"], "Actual elemental state encodes before tampering"):
		return false
	for mutation: Dictionary in [{"growthTemplateId": 255}, {"classId": 0}, {"level": 19}]:
		var bad: Dictionary = JSON.parse_string(JSON.stringify(record["record"]))
		for unit: Dictionary in bad["state"]["units"]:
			if unit["id"] == 92:
				unit.merge(mutation, true)
				break
		if not _expect(
			not Store.new(content).decode(bad, _roll)["ok"],
			"Fresh Store rejects altered elemental growth, class and level: " + str(mutation)
		):
			return false
	return true


func _pickup_capacity(store: RefCounted, previous_content: Dictionary, battle: RefCounted) -> bool:
	var initial: Dictionary = battle.snapshot()
	for capacity: int in [39, 40]:
		var state: Dictionary = initial.duplicate(true)
		state["warehouse"] = []
		for index: int in range(capacity):
			state["warehouse"].append(
				{"id": "m14_storage_%d" % index, "templateId": 2, "durability": 1}
			)
		for actor: Dictionary in state["units"]:
			if actor["id"] == 0:
				actor["x"] = 3
				actor["y"] = 1
				actor["inventory"] = []
				actor["equippedInstanceId"] = ""
				for index: int in range(6):
					actor["inventory"].append(
						{"id": "m14_bag_%d" % index, "templateId": 2, "durability": 1}
					)
			elif actor["visible"] and actor["x"] == 3 and actor["y"] == 1:
				actor["visible"] = false
		if not _expect(battle.restore_snapshot(state)["ok"], "Capacity fixture restores"):
			return false
		var result: Dictionary = battle.wait_unit(0)
		var claimed: bool = capacity == 39
		if not _expect(
			(
				result["ok"]
				and result["location"]["claimed"] == claimed
				and battle.event_completed("location:wait_0") == claimed
			),
			"Full bag stores the fixed item in available warehouse; full warehouse leaves it unclaimed"
		):
			return false
		if not _cold_battle(store, previous_content, battle):
			return false
	return _expect(
		battle.restore_snapshot(initial)["ok"], "Restore original m14 state after capacity cases"
	)


func _cold_battle(store: RefCounted, previous_content: Dictionary, battle: RefCounted) -> bool:
	var saved: Dictionary = store.encode(battle)
	if not _expect(saved["ok"], "Stable battle encodes: " + str(saved)):
		return false
	if not _expect(
		store.write(battle)["ok"], "Write complete battle JSON to isolated continue path"
	):
		return false
	var file_record: Variant = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	if not _expect(file_record is Dictionary, "Read the complete saved JSON from disk"):
		return false
	draws = 0
	var cold: Dictionary = Store.new(previous_content).decode(file_record, _roll)
	return _expect(
		cold["ok"] and draws == 0 and cold["battle"].snapshot() == battle.snapshot(),
		"Fresh Store/Session decodes complete battle JSON without rerolls"
	)


func _roll(_limit: int) -> int:
	draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
