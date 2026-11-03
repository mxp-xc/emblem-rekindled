extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const M11 = preload("res://tests/test_m11_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var draws: int = 0


func _initialize() -> void:
	if not _route(M11.CONTEXTS[0]):
		return
	print("PASS m15 Session/Store: first route, outcomes and completed world cold reads")
	quit(0)


func _route(context: Dictionary) -> bool:
	var prepared: Dictionary = M11.prepare(context, _roll)
	if not _expect(prepared["ok"], "Prepare controlled m11 route: " + str(prepared)):
		return false
	var prior: Dictionary = Session.new().open(CHAPTER, "m11", prepared["source"], _roll)
	if not _expect(prior["ok"], "Open actual m11: " + str(prior)):
		return false
	if not _expect(prior["battle"].win_with_assistance()["ok"], "Settle m11 victory"):
		return false
	var settled: Dictionary = prior["battle"].complete_victory(int(context["route"]))
	if not _expect(settled["ok"], "Produce real m11 completion progress"):
		return false
	var opened: Dictionary = Session.new().open(
		CHAPTER, "m15", {"progress": settled["progress"]}, _roll
	)
	if not _expect(opened["ok"], "Actual m11 progress opens m15: " + str(opened)):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	if not _expect(
		(
			state["campaign"]["route"] == context["route"]
			and state["campaign"]["worldStep"] == 9
			and state["commander"] == -1
			and state["units"].size() == 63
		),
		"m15 preserves route, step, no initial commander and 63 units"
	):
		return false
	var actual_party: Array = []
	for actor: Dictionary in state["units"]:
		if actor["formal"]:
			actual_party.append(actor["id"])
	var expected: Array = context["party"].duplicate()
	expected[0] = 9
	expected[1] = 0
	if not _expect(
		actual_party == expected, "Formal vector follows source order independently of slots"
	):
		return false
	if not _outcomes(opened["content"], state):
		return false
	var path: String = "user://m15_session_%d_%d.json" % [Time.get_ticks_usec(), context["route"]]
	var store: RefCounted = Store.new(opened["content"], path)
	if _cold_battle(store, prior["content"], battle).is_empty():
		return false
	if not _effective_after_cold(store, prior["content"], opened["content"], battle):
		return false
	if not _revival_after_cold(store, prior["content"], battle):
		return false
	if not _expect(battle.win_with_assistance()["ok"], "Assisted m15 victory"):
		return false
	var finish: Dictionary = battle.complete_victory(int(context["route"]))
	if not _expect(finish["ok"], "m15 settles terminal world"):
		return false
	var progress: Dictionary = finish["progress"]
	if not _expect(
		(
			progress["chapterCompleted"]
			and progress["worldStep"] == 10
			and progress["completedBattle"] == "m15"
		),
		"m15 completion keeps terminal identity"
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
			"Fresh slot keeps its own metadata and result"
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
		"Fresh continue preserves completed world"
	):
		return false
	if not _expect(
		(
			Session.new().open(CHAPTER, "m15", {"progress": read["progress"]}).get("error")
			== "CHAPTER_ALREADY_COMPLETED"
		),
		"Completed world cannot start another battle"
	):
		return false
	DirAccess.remove_absolute(path)
	return true


func _outcomes(content: Dictionary, state: Dictionary) -> bool:
	var rules := Events.new(content)
	var units: Array = state["units"].duplicate(true)
	if not _expect(rules.outcome(units).is_empty(), "Initial hidden 89 alone is not victory"):
		return false
	for actor: Dictionary in units:
		if actor["id"] == 83:
			actor["visible"] = false
			actor["hp"] = 0
	if not _expect(
		rules.outcome(units).get("kind") == "victory", "83 retirement with initially hidden 89 wins"
	):
		return false
	for actor: Dictionary in units:
		if actor["id"] == 0:
			actor["visible"] = false
			actor["hp"] = 0
	return _expect(
		rules.outcome(units).get("kind") == "defeat",
		"Alm retirement takes priority over boss victory"
	)


func _effective_after_cold(
	store: RefCounted, previous_content: Dictionary, content: Dictionary, battle: RefCounted
) -> bool:
	var original: Dictionary = battle.snapshot()
	var state: Dictionary = original.duplicate(true)
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["inventory"] = [{"id": "m15:effective:sword", "templateId": 9, "durability": 15}]
			actor["equippedInstanceId"] = "m15:effective:sword"
			actor["attributes"]["strength"] = 30
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore valid holy sword fixture"):
		return false
	var cold: Dictionary = _cold_battle(store, previous_content, battle)
	if cold.is_empty():
		return false
	var actor: Dictionary = cold["battle"].unit(0)
	var target: Dictionary = cold["battle"].unit(20).duplicate(true)
	if not _expect(
		int(target["classGroup"]) in [7, 8, 9], "Actual m15 target is an effective group"
	):
		return false
	# Remove the target weapon from both forecasts to isolate effective power from weapon advantage.
	target["inventory"] = []
	target["equippedInstanceId"] = ""
	var combat := Combat.new(content["rules"], content["map"]["terrain"])
	var effective: int = combat.forecast(actor, target)["damage"]
	target["classGroup"] = 0
	var normal: int = combat.forecast(actor, target)["damage"]
	if not _expect(
		effective == normal + int(combat.item_definition(9)["power"]),
		"Holy sword remains effective after actual Store cold read"
	):
		return false
	return _expect(
		battle.restore_snapshot(original)["ok"], "Restore initial battle after holy sword check"
	)


func _revival_after_cold(
	store: RefCounted, previous_content: Dictionary, battle: RefCounted
) -> bool:
	var original: Dictionary = battle.snapshot()
	var state: Dictionary = original.duplicate(true)
	for actor: Dictionary in state["units"]:
		if actor["id"] == 83:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 1
		elif actor["id"] == 89:
			actor["x"] = 5
			actor["y"] = 1
			actor["visible"] = true
			actor["flags"] &= ~1
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
		elif actor["id"] == 0:
			actor["x"] = 4
			actor["y"] = 1
			actor["action"] = 0
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
			actor["inventory"] = [{"id": "m15:controlled:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m15:controlled:sword"
		elif actor["visible"] and actor["x"] in [4, 5] and actor["y"] == 1:
			actor["visible"] = false
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore legal pre-89 revival boundary"):
		return false
	var cold: Dictionary = _cold_battle(store, previous_content, battle)
	if cold.is_empty():
		return false
	var hit: Dictionary = cold["battle"].attack_unit(0, 89)
	if not _expect(
		(
			hit["ok"]
			and cold["battle"].unit(89)["visible"]
			and cold["battle"].unit(89)["hp"] > 0
			and cold["battle"].outcome.is_empty()
		),
		"89 consumes revival and prevents victory after first hit: " + str(hit)
	):
		return false
	var after: Dictionary = cold["battle"].snapshot()
	for actor: Dictionary in after["units"]:
		if actor["id"] == 89:
			actor["hp"] = 1
		elif actor["id"] == 0:
			actor["action"] = 0
	if not _expect(
		cold["battle"].restore_snapshot(after)["ok"], "Restore controlled second-strike boundary"
	):
		return false
	var final: Dictionary = cold["battle"].attack_unit(0, 89)
	if not _expect(
		(
			final["ok"]
			and not cold["battle"].unit(89)["visible"]
			and cold["battle"].outcome.get("kind") == "victory"
		),
		"Final 89 retirement wins after revival: " + str(final)
	):
		return false
	return _expect(
		battle.restore_snapshot(original)["ok"],
		"Restore initial m15 state after controlled revival"
	)


func _cold_battle(
	store: RefCounted, previous_content: Dictionary, battle: RefCounted
) -> Dictionary:
	if not _expect(store.write(battle)["ok"], "Write complete isolated battle JSON"):
		return {}
	var record: Variant = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	if not _expect(record is Dictionary, "Read written battle JSON"):
		return {}
	draws = 0
	var cold: Dictionary = Store.new(previous_content).decode(record, _roll)
	if not _expect(
		cold["ok"] and draws == 0 and cold["battle"].snapshot() == battle.snapshot(),
		"Fresh Store/Session preserves full state without rerolls"
	):
		return {}
	return cold


func _roll(_limit: int) -> int:
	draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
