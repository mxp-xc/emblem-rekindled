extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	var battle: RefCounted = opened["battle"]
	if (
		battle.snapshot().get("chapterStats")
		!= {"rounds": 1, "playerRetirements": 0, "allyRetirements": 0}
	):
		fail("A new chapter starts with one round and zero final retirements")
		return
	for expected_phase: int in [1, 2]:
		if not battle.end_phase()["ok"] or battle.phase != expected_phase:
			fail("A phase transition must retain its existing automatic-action contract")
			return
		if battle.snapshot()["chapterStats"]["rounds"] != 1:
			fail("Entering an automatic phase does not count another round")
			return
		while battle.automatic_actor() >= 0:
			var id: int = battle.automatic_actor()
			var began: Dictionary = battle.begin_automatic_action(id)
			if not began["ok"] or not battle.wait_unit(id)["ok"]:
				fail("Automatic actors can finish their action without combat")
				return
	if not battle.end_phase()["ok"] or battle.snapshot()["chapterStats"]["rounds"] != 2:
		fail("Returning from enemy phase to player phase increments the cumulative round once")
		return
	var saved: Dictionary = battle.snapshot()
	var restored: RefCounted = Battle.new(opened["content"])
	if (
		not restored.restore_snapshot(saved)["ok"]
		or restored.snapshot()["chapterStats"] != saved["chapterStats"]
	):
		fail("Restoring the same round never increments chapter statistics")
		return
	var no_commander: Dictionary = saved.duplicate(true)
	no_commander["commander"] = -1
	if not restored.restore_snapshot(no_commander)["ok"] or restored.snapshot()["commander"] != -1:
		fail("The existing no-commander battle sentinel stays valid for selection maps")
		return
	saved.erase("chapterStats")
	if (
		not restored.restore_snapshot(saved)["ok"]
		or (
			restored.snapshot()["chapterStats"]
			!= {"rounds": null, "playerRetirements": null, "allyRetirements": null}
		)
	):
		fail("Legacy battle records keep unknown history rather than inventing zero counts")
		return
	if not _automatic_changes(opened["content"]):
		return
	for faction: int in [0, 1]:
		if not _final_retirement(opened["content"], faction, false):
			return
	if not _final_retirement(opened["content"], 0, true):
		return
	if not _final_retirement(opened["content"], 1, false, true):
		return
	if not _final_retirement(opened["content"], 0, false, false, true):
		return
	print("PASS m13 runtime: new chapter counters, full-round increment, legacy unknown")
	quit(0)


func _automatic_changes(source: Dictionary) -> bool:
	var content: Dictionary = source.duplicate(true)
	content["story"]["outcomeRules"]["checks"] = []
	content["story"]["turnEvents"] = []
	var battle: RefCounted = Battle.new(content)
	var state: Dictionary = battle.snapshot()
	var ally: int = -1
	var enemy: int = -1
	for actor: Dictionary in state["units"]:
		if actor["visible"] and actor["faction"] == 1 and ally < 0:
			ally = int(actor["id"])
		if actor["visible"] and actor["faction"] == 2 and enemy < 0:
			enemy = int(actor["id"])
		actor["flags"] &= ~16
		actor["policy"] |= 4
	if ally < 0 or enemy < 0:
		fail("The automatic-phase fixture needs an allied and enemy actor")
		return false
	content["story"]["aiChanges"] = [
		{
			"beforeAutomaticPhase": {"round": 9, "faction": 1},
			"unitIds": [ally],
			"flagsSet": 16,
			"policyClear": 4
		},
		{
			"beforeAutomaticPhase": {"round": 9, "faction": 2},
			"unitIds": [enemy],
			"flagsSet": 16,
			"policyClear": 4
		}
	]
	battle.adopt_content(content)
	state["round"] = 9
	if not battle.restore_snapshot(state)["ok"] or not battle.end_phase()["ok"]:
		fail("Round-nine automatic changes start from a stable player phase")
		return false
	if (
		battle.phase != 1
		or (battle.unit(ally)["flags"] & 16) == 0
		or (battle.unit(ally)["policy"] & 4) != 0
		or (battle.unit(enemy)["flags"] & 16) != 0
	):
		fail(
			"Round-nine allied changes commit before allied actions without changing the enemy phase early"
		)
		return false
	while battle.automatic_actor() >= 0:
		battle.wait_unit(battle.automatic_actor())
	if (
		not battle.end_phase()["ok"]
		or battle.phase != 2
		or (battle.unit(enemy)["flags"] & 16) == 0
		or (battle.unit(enemy)["policy"] & 4) != 0
	):
		fail("Enemy changes wait until the round-nine enemy phase starts")
		return false
	return true


func _final_retirement(
	source: Dictionary, faction: int, revival: bool, special: bool = false, map_damage: bool = false
) -> bool:
	var content: Dictionary = source.duplicate(true)
	content["story"]["outcomeRules"]["checks"] = []
	content["story"]["turnEvents"] = []
	var battle: RefCounted = Battle.new(content, func(_limit: int) -> int: return 0)
	var state: Dictionary = battle.snapshot()
	var victim: int = -1
	for actor: Dictionary in state["units"]:
		if actor["visible"] and actor["faction"] == faction and victim < 0:
			victim = int(actor["id"])
	if victim < 0:
		fail("The retirement fixture needs the requested faction")
		return false
	var attacker: int = 54 if map_damage else 59
	if special:
		for definition: Dictionary in content["units"]:
			if definition["id"] == victim:
				definition["classId"] = 40
				definition["classGroup"] = 10
				definition["equipMask"] = 16
				definition.erase("promotionBaseClassId")
		battle.adopt_content(content)
	for actor: Dictionary in state["units"]:
		if actor["id"] == victim:
			actor["x"] = 8
			actor["y"] = 21
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
			actor["attributes"]["magic"] = 0
			actor["inventory"] = (
				[{"id": "retirement_ring", "templateId": 80, "durability": 1}] if revival else []
			)
			actor["equippedInstanceId"] = ""
			if special:
				actor["classId"] = 40
				actor["classGroup"] = 10
				actor["equipMask"] = 16
				actor["maxHp"] = 1
				actor["move"] = 0
				for stat: String in actor["attributes"]:
					actor["attributes"][stat] = 0
		elif actor["id"] == attacker:
			actor["x"] = 10 if map_damage else 9
			actor["y"] = 21
			actor["visible"] = true
			if map_damage:
				actor["inventory"] = [{"id": "statistics_cast", "templateId": 50, "durability": 14}]
				actor["equippedInstanceId"] = "statistics_cast"
		elif actor["x"] in [8, 9, 10] and actor["y"] == 21:
			actor["visible"] = false
	var restored: Dictionary = battle.restore_snapshot(state)
	if not restored["ok"]:
		fail(
			(
				"Controlled retirement fixture restores without counting direct hidden changes: "
				+ str(restored)
			)
		)
		return false
	for expected_phase: int in [1, 2]:
		if not battle.end_phase()["ok"] or battle.phase != expected_phase:
			fail("Retirement fixture reaches the enemy phase through the normal phase command")
			return false
		if expected_phase == 1:
			while battle.automatic_actor() >= 0:
				battle.wait_unit(battle.automatic_actor())
	var result: Dictionary = (
		battle.cast_map_attack(attacker, "statistics_cast", victim)
		if map_damage
		else battle.attack_unit(attacker, victim)
	)
	if not result["ok"]:
		fail(
			(
				"The enemy attack must run the normal damage and final-retirement pipeline: "
				+ str(result)
			)
		)
		return false
	var key: String = "playerRetirements" if faction == 0 else "allyRetirements"
	var expected: int = 0 if revival or special else 1
	if (
		battle.snapshot()["chapterStats"][key] != expected
		or battle.unit(victim)["visible"] != revival
	):
		fail("A real final retirement counts its faction once; resurrection counts no retirement")
		return false
	var settled: Dictionary = battle.snapshot()
	var repeated: Dictionary = (
		battle.cast_map_attack(attacker, "statistics_cast", victim)
		if map_damage
		else battle.attack_unit(attacker, victim)
	)
	if repeated["ok"] or battle.snapshot() != settled:
		fail("Replaying a committed attack cannot count another retirement")
		return false
	return true


func fail(message: String) -> void:
	push_error(message)
	quit(1)
