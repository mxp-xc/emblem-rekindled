extends SceneTree

const M14 = preload("res://tests/test_m14_outcomes.gd")
const Combat = preload("res://gameplay/combat_rules.gd")


func _initialize() -> void:
	for complete: bool in [false, true]:
		if not _map_experience(complete):
			return
	if not _full_enemy_phase():
		return
	print("PASS m14 actual Session map experience qualification and complete enemy phase")
	quit(0)


func _map_experience(complete: bool) -> bool:
	var opened: Dictionary = M14.prepare(1, _zero)
	if not _expect(opened["ok"], "Open actual route1 m14"):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		match int(actor["id"]):
			8:
				actor["x"] = 7
				actor["y"] = 10
				actor["level"] = 1
				actor["experience"] = 0
				actor["attributes"]["skill"] = 30
				actor["attributes"]["magic"] = 30
				actor["inventory"] = [{"id": "m14:map:50", "templateId": 50, "durability": 10}]
				actor["equippedInstanceId"] = "m14:map:50"
			92:
				actor["x"] = 9
				actor["y"] = 10
				actor["hp"] = 1
				actor["attributes"]["magic"] = 0
			93, 94:
				actor["x"] = 12 if actor["id"] == 93 else 15
				actor["y"] = 10
				if complete:
					actor["hp"] = 1
					actor["flags"] |= 64
			_:
				if actor["visible"] and actor["y"] == 10 and actor["x"] in [7, 9, 12, 15]:
					actor["visible"] = false
	if not _expect(
		battle.restore_snapshot(state)["ok"],
		"Restore valid controlled map attack: " + str(complete)
	):
		return false
	var combat := Combat.new(opened["content"]["rules"], opened["content"]["map"]["terrain"])
	var expected: int = combat.experience_gain(
		battle.unit(8), battle.unit(92), complete, true, false
	)
	var result: Dictionary = battle.cast_map_attack(8, "m14:map:50", 92)
	if not _expect(
		(
			result["ok"]
			and result["targetIds"] == [92]
			and result["rewards"]["experience"].get("amount") == expected
		),
		"Actual m14 map target uses the correct kill qualification: " + str(result)
	):
		return false
	if (
		not complete
		and not _expect(
			expected == 12 and battle.unit(92)["visible"] and battle.unit(92)["hp"] == 1,
			"First map knockdown awards 12 and keeps the element visible"
		)
	):
		return false
	if (
		complete
		and not _expect(
			(
				not battle.unit(92)["visible"]
				and not battle.unit(93)["visible"]
				and not battle.unit(94)["visible"]
			),
			"Qualified final map knockdown retires the whole group"
		)
	):
		return false
	print(
		(
			"m14 map experience complete=%s amount=%d (legal magic/skill 30; original fixture used 100)"
			% [str(complete), expected]
		)
	)
	return true


func _full_enemy_phase() -> bool:
	var opened: Dictionary = M14.prepare(1, _zero)
	if not _expect(opened["ok"], "Open actual route1 m14 for full phase cycle"):
		return false
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		match int(actor["id"]):
			0:
				actor["x"] = 8
				actor["y"] = 10
				actor["attributes"]["strength"] = 30
				actor["attributes"]["skill"] = 30
				actor["inventory"] = [{"id": "m14:phase:sword", "templateId": 1, "durability": 30}]
				actor["equippedInstanceId"] = "m14:phase:sword"
			92, 94:
				actor["x"] = 9 if actor["id"] == 92 else 8
				actor["y"] = 10 if actor["id"] == 92 else 11
				actor["hp"] = 1
				actor["attributes"]["defense"] = 0
			_:
				if (
					actor["visible"]
					and (
						Vector2i(actor["x"], actor["y"])
						in [Vector2i(8, 10), Vector2i(9, 10), Vector2i(8, 11)]
					)
				):
					actor["visible"] = false
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore controlled ordinary attack boundary"
	):
		return false
	var first: Dictionary = battle.attack_unit(0, 92)
	if not _expect(
		first["ok"] and (battle.unit(92)["flags"] & 64) != 0 and battle.unit(92)["visible"],
		"Ordinary knockdown sets current-phase marker"
	):
		return false
	for phase: int in [1, 2, 0]:
		var advanced: Dictionary = battle.end_phase()
		if not _expect(
			advanced["ok"] and battle.phase == phase,
			"Advance actual ally/enemy/player phase: " + str(advanced)
		):
			return false
		while phase != 0 and battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"],
				"Drain each actual automatic action"
			):
				return false
	if not _expect(
		(battle.unit(92)["flags"] & 64) == 0,
		"A full automatic cycle clears the earlier elemental marker"
	):
		return false
	var last: Dictionary = battle.attack_unit(0, 94)
	return _expect(
		(
			last["ok"]
			and battle.unit(94)["visible"]
			and battle.unit(94)["hp"] == 1
			and battle.unit(92)["visible"]
		),
		"A later knockdown cannot combine with the prior phase marker"
	)


func _zero(_limit: int) -> int:
	return 0


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
