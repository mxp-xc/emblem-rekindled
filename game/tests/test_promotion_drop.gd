extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _draws: Array[int] = []
var _source: Dictionary = {}


func _initialize() -> void:
	if not _missing_targets() or not _complete_targets() or not _warehouse_and_unmarked():
		return
	if not _shared_existing_emblem():
		return
	print("PASS promotion drops: prospective recipient preflight, counters, commander and capacity")
	quit(0)


func _open() -> Dictionary:
	if _source.is_empty():
		var first: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, _roll)
		if not first["ok"]:
			return first
		first["battle"].win_with_assistance()
		var completed: Dictionary = first["battle"].complete_victory(0)
		if not completed["ok"]:
			return completed
		var arrived: Dictionary = Session.new().open(
			CHAPTER, "m1", {"progress": completed["progress"]}, _roll
		)
		if not arrived["ok"]:
			return arrived
		var advanced: Dictionary = Rounds.advance(arrived["battle"])
		if not advanced["ok"]:
			return advanced
		if not (
			arrived["battle"].event_completed("allied_arrival")
			and arrived["battle"].round_number == 2
			and arrived["battle"].phase == 0
		):
			return {"ok": false, "error": "M1_ARRIVAL_REQUIRED"}
		_source = arrived["battle"].snapshot().duplicate(true)
	var opened: Dictionary = Session.new().open(
		CHAPTER, "m1", {"snapshot": _source.duplicate(true)}, _roll
	)
	if not opened["ok"]:
		return opened
	opened["content"]["story"]["outcomeRules"]["checks"] = []
	opened["battle"].adopt_content(opened["content"])
	return opened


func _fixture(
	verified_target: bool, mode: String, bag: String = "open", marked: bool = true
) -> Dictionary:
	var opened: Dictionary = _open()
	if not _expect(
		opened["ok"], "Open real chapter context for drop fixture: " + str(opened.get("error", ""))
	):
		return {}
	var battle: RefCounted = opened["battle"]
	if not verified_target:
		# Fault only derived future presentation, keeping the same legal m1 input.
		opened["content"]["promotionTargets"] = opened["content"]["promotionTargets"].duplicate()
		opened["content"]["promotionTargets"].erase(0)
		opened["content"]["promotionErrors"] = opened["content"]["promotionErrors"].duplicate()
		opened["content"]["promotionErrors"][0] = "controlled missing future profile"
		battle.adopt_content(opened["content"])
	var enemy_id: int = 60
	var fighter_id: int = 15 if mode == "ally" else 0
	var origin: Dictionary = battle.unit(0)
	var state: Dictionary = battle.snapshot()
	state["commander"] = 0
	for actor: Dictionary in state["units"]:
		actor["visible"] = actor["id"] in [0, enemy_id, fighter_id]
		actor["flags"] = int(actor["flags"]) & ~1 if actor["visible"] else int(actor["flags"]) | 1
		if actor["id"] == 0:
			actor["level"] = 9
			actor["experience"] = 99
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
			actor["attributes"]["defense"] = 30
			actor["inventory"] = [
				{
					"id": "winnerWeapon",
					"templateId": 9,
					"durability": 1 if bag == "weapon_break" else 15
				}
			]
			actor["equippedInstanceId"] = "winnerWeapon"
			if bag != "open":
				actor["inventory"].append(
					{
						"id": "second",
						"templateId": 65 if bag == "shield_break" else 64,
						"durability": 1
					}
				)
				for index: int in range(4):
					actor["inventory"].append(
						{"id": "full_%d" % index, "templateId": 68 + index, "durability": 1}
					)
		if actor["id"] == fighter_id and mode == "ally":
			actor["x"] = origin["x"]
			actor["y"] = int(origin["y"]) + 1
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
			actor["inventory"] = [{"id": "allyWeapon", "templateId": 34, "durability": 20}]
			actor["equippedInstanceId"] = "allyWeapon"
		if actor["id"] == enemy_id:
			actor["level"] = 9
			actor["x"] = origin["x"]
			actor["y"] = int(origin["y"]) + (3 if mode == "ally" else 1)
			actor["hp"] = 1
			actor["attributes"]["strength"] = 0
			actor["attributes"]["skill"] = 30
			actor["attributes"]["defense"] = 0
			actor["inventory"] = [
				{"id": "enemyWeapon", "templateId": 13, "durability": 30},
				{"id": "dropped76", "templateId": 76, "durability": 1}
			]
			actor["equippedInstanceId"] = "enemyWeapon" if mode == "counter" else ""
			actor["dropTemplateId"] = 76 if marked else 0
	var restored: Dictionary = battle.restore_snapshot(state)
	if not _expect(restored["ok"], "Restore legal drop boundary: " + str(restored)):
		return {}
	var wanted_phase: int = 2 if mode == "counter" else (1 if mode == "ally" else 0)
	while battle.phase != wanted_phase:
		while battle.automatic_actor() >= 0:
			var waited: Dictionary = battle.wait_unit(battle.automatic_actor())
			if not _expect(waited["ok"], "Wait to controlled drop phase"):
				return {}
		if not _expect(battle.end_phase()["ok"], "Advance to actual counter or allied phase"):
			return {}
	_draws.clear()
	return {
		"battle": battle,
		"content": opened["content"],
		"actor": enemy_id if mode == "counter" else fighter_id,
		"target": 0 if mode == "counter" else enemy_id
	}


func _missing_targets() -> bool:
	for sample: Array in [
		["normal", "open"],
		["counter", "open"],
		["ally", "open"],
		["normal", "weapon_break"],
		["counter", "shield_break"]
	]:
		var prepared: Dictionary = _fixture(false, sample[0], sample[1])
		if prepared.is_empty():
			return false
		var battle: RefCounted = prepared["battle"]
		var before: Dictionary = battle.snapshot()
		var result: Dictionary = battle.attack_unit(prepared["actor"], prepared["target"])
		if not _expect(
			(
				not result["ok"]
				and result["error"] == "PROMOTION_PRESENTATION_UNAVAILABLE"
				and battle.snapshot() == before
				and _draws.is_empty()
			),
			"Prospective normal/counter/commander drop owner rejects atomically before combat or loot"
		):
			return false
	return true


func _complete_targets() -> bool:
	for sample: Array in [
		["normal", "open"],
		["counter", "open"],
		["normal", "weapon_break"],
		["counter", "shield_break"]
	]:
		var prepared: Dictionary = _fixture(true, sample[0], sample[1])
		if prepared.is_empty():
			return false
		var battle: RefCounted = prepared["battle"]
		var result: Dictionary = battle.attack_unit(prepared["actor"], prepared["target"])
		if not _expect(
			(
				result["ok"]
				and battle.unit(0)["classId"] == 1
				and battle.unit(0)["level"] == 10
				and result["rewards"]["experience"]["promotion"]["unit"] == 0
				and result["rewards"]["loot"][0]["destination"] == "inventory"
				and result["rewards"]["loot"][0]["item"]["id"] == "dropped76"
				and not battle.unit(0)["inventory"].any(
					func(held: Dictionary) -> bool: return held["templateId"] == 76
				)
			),
			"Verified m1 target accepts new drop then automatically consumes76 after ordinary XP"
		):
			return false
	return true


func _warehouse_and_unmarked() -> bool:
	for mode: String in ["normal", "ally"]:
		var prepared: Dictionary = _fixture(false, mode, "warehouse")
		if prepared.is_empty():
			return false
		var battle: RefCounted = prepared["battle"]
		var result: Dictionary = battle.attack_unit(prepared["actor"], prepared["target"])
		if not _expect(
			(
				result["ok"]
				and battle.unit(0)["classId"] == 0
				and battle.unit(0)["level"] == 10
				and result["rewards"]["loot"][0]["destination"] == "warehouse"
				and battle.snapshot()["warehouse"].any(
					func(held: Dictionary) -> bool: return held["id"] == "dropped76"
				)
			),
			"Definitely full recipient bag sends76 to warehouse without requiring unavailable promotion"
		):
			return false
	var prepared: Dictionary = _fixture(false, "normal", "open", false)
	if prepared.is_empty():
		return false
	var battle: RefCounted = prepared["battle"]
	var result: Dictionary = battle.attack_unit(prepared["actor"], prepared["target"])
	return _expect(
		(
			result["ok"]
			and result["rewards"]["loot"].is_empty()
			and battle.unit(0)["classId"] == 0
			and battle.unit(0)["level"] == 10
		),
		"Unmarked held76 is not a drop and does not introduce a promotion resource requirement"
	)


func _shared_existing_emblem() -> bool:
	var prepared: Dictionary = _fixture(false, "normal", "open", false)
	if prepared.is_empty():
		return false
	var battle: RefCounted = prepared["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["visible"] = true
			actor["level"] = 9
			actor["experience"] = 99
			actor["inventory"].append({"id": "shared76", "templateId": 76, "durability": 1})
	var restored: Dictionary = battle.restore_snapshot(state)
	if not _expect(restored["ok"], "Restore actual preexisting shared recipient emblem"):
		return false
	prepared["content"]["promotionTargets"].erase(9)
	prepared["content"]["promotionErrors"][9] = "controlled missing shared future profile"
	battle.adopt_content(prepared["content"])
	battle.share_experience = true
	var before: Dictionary = battle.snapshot()
	_draws.clear()
	var result: Dictionary = battle.attack_unit(prepared["actor"], prepared["target"])
	return _expect(
		not result["ok"] and battle.snapshot() == before and _draws.is_empty(),
		"Prospective drop check retains preexisting shared-emblem atomic preflight"
	)


func _roll(limit: int) -> int:
	_draws.append(limit)
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
