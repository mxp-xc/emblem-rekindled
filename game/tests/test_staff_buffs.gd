extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
var draws: Array[int] = []


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not _effects(content) or not _boundaries(content) or not _rewards_and_restore(content):
		return
	if not _phase_bits(content) or not _cleanup_and_ai(content):
		return
	print("PASS staff buffs: effects/targets, atomic action/XP/growth/restore, cleanup/phases, AI")
	quit(0)


func _effects(content: Dictionary) -> bool:
	# template, previous effect, expected strength delta, expected magic delta.
	for sample: Array in [
		[55, 0, 5, 0],
		[56, 0, 0, 5],
		[55, 8, 0, 0],
		[56, 32, 0, 0],
		[55, 32, 5, -5],
		[56, 8, -5, 5],
		[55, 40, 0, -5],
		[56, 40, -5, 0]
	]:
		var battle: RefCounted = _fixture(content, sample[0])
		if battle == null:
			return false
		var state: Dictionary = battle.snapshot()
		for actor: Dictionary in state["units"]:
			if actor["id"] == 0:
				actor["flags"] = sample[1] | 16 | 128
		if not _expect(
			battle.restore_snapshot(state)["ok"], "Restore an existing auxiliary effect"
		):
			return false
		var before: Dictionary = battle.unit_information(0)["basic"]
		var caster: Dictionary = battle.unit(9)
		var target: Dictionary = battle.unit(0)
		draws.clear()
		var result: Dictionary = battle.heal_unit(9, 0, "staff")
		var after: Dictionary = battle.unit_information(0)["basic"]
		if not _expect(
			(
				result["ok"]
				and result["kind"] == "staff_buff"
				and after["strength"] == before["strength"] + sample[2]
				and after["magic"] == before["magic"] + sample[3]
				and battle.unit(0)["flags"] == (24 | 128 if sample[0] == 55 else 48 | 128)
				and battle.unit(0)["hp"] == target["hp"]
				and battle.unit(9)["hp"] == caster["hp"]
				and battle.unit(0)["attributes"] == target["attributes"]
				and battle.unit(0)["experience"] == target["experience"]
				and battle.unit(9)["inventory"][0]["durability"] == 17
				and battle.unit(9)["experience"] == 12
				and battle.unit(9)["action"] == 2
				and battle.unit(9)["proficiency"] == caster["proficiency"]
				and draws.is_empty()
			),
			"55/56 replace each other, allow full HP/repeat and settle once without HP/permanent stats/RNG"
		):
			return false
		var settled: Dictionary = battle.snapshot()
		if not _expect(
			not battle.heal_unit(9, 0, "staff")["ok"] and battle.snapshot() == settled,
			"No repeated settlement"
		):
			return false
	return true


func _boundaries(content: Dictionary) -> bool:
	var battle: RefCounted = _fixture(content, 55)
	if battle == null:
		return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 10 or actor["id"] == 59:
			actor["visible"] = true
			actor["x"] = 9 if actor["id"] == 10 else 10
			actor["y"] = 10 if actor["id"] == 10 else 11
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Prepare allied-faction and enemy neighbors"
	):
		return false
	var targets: Array[int] = battle.heal_targets(9, "staff")
	if not _expect(
		(
			targets.size() == 2
			and 0 in targets
			and 10 in targets
			and 9 not in targets
			and 59 not in targets
		),
		"Staff chooses same-alliance neighbors across factions, never self/enemy/hidden"
	):
		return false
	for target: int in [9, 59, 95, 999]:
		var before: Dictionary = battle.snapshot()
		draws.clear()
		if not _expect(
			(
				not battle.heal_unit(9, target, "staff")["ok"]
				and battle.snapshot() == before
				and draws.is_empty()
			),
			"Self/enemy/hidden/absent targets must reject without a partial action"
		):
			return false
	for position: Vector2i in [Vector2i(8, 10), Vector2i(7, 11)]:
		var moved: Dictionary = state.duplicate(true)
		for actor: Dictionary in moved["units"]:
			if actor["id"] == 0:
				actor["x"] = position.x
				actor["y"] = position.y
		if not _expect(battle.restore_snapshot(moved)["ok"], "Prepare an out-of-range target"):
			return false
		var before: Dictionary = battle.snapshot()
		draws.clear()
		if not _expect(
			(
				0 not in battle.heal_targets(9, "staff")
				and not battle.heal_unit(9, 0, "staff")["ok"]
				and battle.snapshot() == before
				and draws.is_empty()
			),
			"Diagonal/distance2 must reject atomically without RNG"
		):
			return false
	for sample: Array in [[55, 0, 9], [57, 18, 9], [1, 18, 9], [55, 18, 0]]:
		battle = _fixture(content, sample[0], sample[1], sample[2])
		if battle == null:
			return false
		var before: Dictionary = battle.snapshot()
		draws.clear()
		if not _expect(
			(
				battle.healing_field(sample[2], "staff").is_empty()
				and not battle.heal_unit(sample[2], 0 if sample[2] == 9 else 9, "staff")["ok"]
				and battle.snapshot() == before
				and draws.is_empty()
			),
			"Depleted/wrong staff or missing capability rejects without changes"
		):
			return false
	return true


func _rewards_and_restore(content: Dictionary) -> bool:
	for level: int in [1, 19, 20]:
		var battle: RefCounted = _fixture(content, 56, 1)
		if battle == null:
			return false
		var state: Dictionary = battle.snapshot()
		for actor: Dictionary in state["units"]:
			if actor["id"] == 9:
				actor["experience"] = 99
				actor["level"] = level
		if not _expect(battle.restore_snapshot(state)["ok"], "Prepare staff XP boundary"):
			return false
		draws.clear()
		var result: Dictionary = battle.heal_unit(9, 0, "staff")
		var reward: Dictionary = result["rewards"]["experience"]
		if not _expect(
			(
				result["ok"]
				and result["expiredItem"]["templateId"] == 56
				and battle.unit(9)["inventory"].is_empty()
				and battle.unit(9)["action"] == 2
				and battle.unit(0)["hp"] == 30
			),
			"Last charge removes held staff and retains one action/expiry without HP changes"
		):
			return false
		if level == 20:
			if not _expect(
				reward.is_empty() and battle.unit(9)["experience"] == 99 and draws.is_empty(),
				"Capped staff XP suppresses growth, not the action"
			):
				return false
		elif not _expect(
			(
				battle.unit(9)["level"] == level + 1
				and battle.unit(9)["experience"] == (11 if level == 1 else 0)
				and draws.size() == 8
				and not reward["growth"].is_empty()
			),
			"Staff XP uses existing modulo/level/growth chain with only eight growth draws"
		):
			return false
		var store: RefCounted = load("res://persistence/battle_store.gd").new(content)
		var encoded: Dictionary = store.encode(battle)
		var before_draws: Array[int] = draws.duplicate()
		if not _expect(encoded["ok"], "Encode current auxiliary effect"):
			return false
		var decoded: Dictionary = store.decode(
			JSON.parse_string(JSON.stringify(encoded["record"])), _roll
		)
		if not _expect(
			(
				decoded["ok"]
				and decoded["battle"].snapshot() == battle.snapshot()
				and draws == before_draws
				and decoded["battle"].unit(0)["flags"] == 32
			),
			"Cold JSON restores the temporary flag without recasting or redrawing"
		):
			return false
	return true


func _fixture(
	content: Dictionary, template: int, durability: int = 18, owner: int = 9
) -> RefCounted:
	var battle := Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		actor["visible"] = actor["id"] in [0, 9, 59]
		if actor["id"] == owner:
			actor["inventory"] = [{"id": "staff", "templateId": template, "durability": durability}]
			actor["equippedInstanceId"] = ""
	var restored: Dictionary = battle.restore_snapshot(state)
	if not _expect(restored["ok"], "Prepare held staff fixture: " + str(restored)):
		return null
	return battle


func _cleanup_and_ai(content: Dictionary) -> bool:
	var battle := Battle.new(content, _roll)
	var combat: RefCounted = load("res://gameplay/combat_rules.gd").new(
		content["rules"], content["map"]["terrain"]
	)
	var inventory: RefCounted = load("res://gameplay/unit_inventory.gd").new(combat, _roll)
	for empty: bool in [false, true]:
		var actor: Dictionary = battle.unit(0)
		actor["flags"] = 8 | 16 | 32 | 128
		if empty:
			actor["inventory"] = []
		inventory.cleanup_combat(actor)
		if not _expect(
			actor["flags"] == (184 if empty else 144),
			"Combat cleanup retains original empty-inventory boundary and unrelated bits"
		):
			return false
	var samples: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_ai.json")
	)
	for sample: Dictionary in samples:
		if sample["case"] != "heal66":
			continue
		for template: int in [53, 54, 55, 56]:
			var units: Array = sample["units"].duplicate(true)
			var actor: Dictionary = {}
			for current: Dictionary in units:
				if current["id"] == 66:
					actor = current
					actor["inventory"] = [
						{"id": "ai_staff", "templateId": template, "durability": 18}
					]
					actor["equippedInstanceId"] = ""
			var ai: RefCounted = load("res://gameplay/tactical_ai.gd").new(content)
			var plan: Dictionary = ai.plan(actor, units, {}, 0, 1)
			if not _expect(
				(plan["healTarget"] >= 0) == (template in [53, 54]),
				"AI remains limited to HP staffs53/54, never auxiliary55/56"
			):
				return false
	return true


func _phase_bits(source: Dictionary) -> bool:
	var content: Dictionary = source.duplicate(true)
	content["story"]["outcomeRules"]["checks"] = []
	content["story"]["turnEvents"] = []
	var battle := Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		actor["flags"] = 8 | 16 | 32 | 64 | 128
	if not _expect(battle.restore_snapshot(state)["ok"], "Prepare all phase status bits"):
		return false
	for expected_phase: int in [1, 2, 0]:
		while battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"], "Complete automatic wait"
			):
				return false
		var advanced: Dictionary = battle.end_phase()
		if not _expect(advanced["ok"] and battle.phase == expected_phase, "Advance one faction"):
			return false
		for actor: Dictionary in battle.snapshot()["units"]:
			if not _expect(
				actor["flags"] == (16 | 128 if expected_phase == 0 else 8 | 16 | 32 | 128),
				"Every phase clears64; only new player phase clears8/32 while preserving16/128"
			):
				return false
	return true


func _roll(limit: int) -> int:
	draws.append(limit)
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
