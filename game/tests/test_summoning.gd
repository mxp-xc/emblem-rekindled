extends SceneTree

const Matrix = preload("res://tests/test_m8_content.gd")
const M2 = preload("res://tests/test_m2_content.gd")
const M4 = preload("res://tests/test_m4_content.gd")
const AI = preload("res://gameplay/tactical_ai.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Session = preload("res://app/chapter_session.gd")
const Summons = preload("res://gameplay/battle_summons.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const Inventory = preload("res://gameplay/unit_inventory.gd")
var _draws: Array[int] = []
var _class_pick: int = 0
var _last: bool = false


func _initialize() -> void:
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[5], _zero)
	if not _expect(prepared["ok"], "Prepare actual m8 domain source"):
		return
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m8", prepared["source"], _zero)
	if not _expect(opened["ok"], "Open actual m8 domain content"):
		return
	if not _placement() or not _births(opened) or not _ai_cases(opened) or not _command(opened):
		return
	print("PASS summoning: placement, six families, ordered RNG, level22 and atomic staff command")
	quit(0)


func _placement() -> bool:
	var actor: Dictionary = {"id": 1, "faction": 0, "x": 1, "y": 1, "visible": true, "hp": 1}
	var map: Dictionary = {"width": 3, "height": 3, "terrain": [[255, 255, 255]]}
	var units: Array = [actor]
	var expected: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 2), Vector2i(2, 1)]
	for point: Vector2i in expected:
		var placed: Dictionary = Summons.placement(actor, units, map)
		if not _expect(
			placed["ok"] and placed["unitId"] == 20 and placed["to"] == point,
			"First unoccupied orthogonal neighbor follows left/up/down/right without terrain filtering"
		):
			return false
		units.append(
			{"id": 100 + units.size(), "x": point.x, "y": point.y, "visible": true, "hp": 0}
		)
	if not _expect(
		not Summons.placement(actor, units, map)["ok"], "Visible HP0 blocks all four neighbors"
	):
		return false
	units[1]["visible"] = false
	units[1]["hp"] = 1
	if not _expect(
		Summons.placement(actor, units, map)["to"] == expected[0],
		"Hidden living actor does not block a cell"
	):
		return false
	units = [actor]
	for id: int in range(20, 30):
		units.append({"id": id, "x": 0, "y": 0, "visible": false, "hp": 1})
	var before: Array = units.duplicate(true)
	if not _expect(
		not Summons.placement(actor, units, map)["ok"] and units == before,
		"Hidden living actors occupy the ID pool; query mutates nothing"
	):
		return false
	units[1]["hp"] = 0
	if not _expect(
		Summons.placement(actor, units, map)["unitId"] == 20,
		"First dead hidden ID can be reclaimed"
	):
		return false
	actor["x"] = 0
	actor["y"] = 0
	actor["faction"] = 2
	var edge: Dictionary = Summons.placement(actor, [actor], map)
	return _expect(
		edge["unitId"] == 70 and edge["to"] == Vector2i(0, 1),
		"Enemy uses pool70 and skips out-of-bounds left/up"
	)


func _births(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var combat: RefCounted = Combat.new(content["rules"], content["map"]["terrain"])
	var inventory: RefCounted = Inventory.new(combat, _roll)
	var summons: RefCounted = Summons.new(content, combat, inventory, _roll)
	var indices: Array[int] = [0, 3, 4, 7, 8, 11]
	var classes: Array[int] = [28, 29, 32, 33, 36, 37]
	for faction: int in [0, 2]:
		for index: int in range(indices.size()):
			var actor: Dictionary = opened["battle"].unit(1).duplicate(true)
			actor["faction"] = faction
			actor["level"] = 1
			_draws.clear()
			_class_pick = indices[index]
			_last = false
			var born: Dictionary = summons.birth(actor, [actor], [], {})
			if not _expect(born["ok"], "Birth each original weighted class family"):
				return false
			var unit: Dictionary = born["unit"]
			if (
				index == 0
				and not _expect(
					(
						(
							unit["attributes"]
							== {
								"strength": 5,
								"skill": 1,
								"speed": 1,
								"defense": 5,
								"magic": 0,
								"luck": 0
							}
						)
						and unit["maxHp"] == 35
						and unit["move"] == 4
					),
					"Class28 level1 with zero noise matches original base38/growth17 worked example"
				)
			):
				return false
			var weapon: int = 29 if index < 2 else 30 if index < 4 else 40
			var expected: Array[int] = [5, 12]
			if index >= 4:
				expected.append(6)
			expected.append_array([1 if index >= 4 else 4, 3, 3, 3, 3, 6, 3, 1])
			if not _expect(
				(
					unit["classId"] == classes[index]
					and unit["level"] == 1
					and unit["faction"] == (1 if faction == 0 else 2)
					and not unit["formal"]
					and unit["id"] == (20 if faction == 0 else 70)
					and unit["inventory"][0]["templateId"] == weapon
					and _draws == expected
				),
				"Class, alliance, default weapon and level/class/weapon/eight-noise draw order match oracle"
			):
				return false
	# A compiled replacement changes only this runtime unit, never its catalog source.
	var family_key: String = content["_library"]["summons"]["1"]["28"]["20"]
	var source_sprite: String = content["_library"]["profiles"][family_key]["unit"]["sprite"]
	var replacement: String = "res://tests/fixtures/texture_overrides/authored/replacement.png"
	var overridden: Dictionary = content.duplicate()
	overridden["_textureOverrides"] = content.get("_textureOverrides", {}).duplicate()
	overridden["_textureOverrides"][source_sprite] = replacement
	var replaced_summons: RefCounted = Summons.new(overridden, combat, inventory, _roll)
	_draws.clear()
	_class_pick = 0
	_last = false
	var replaced: Dictionary = replaced_summons.birth(
		opened["battle"].unit(1), [opened["battle"].unit(1)], [], {}
	)
	if not _expect(
		(
			replaced["ok"]
			and replaced["unit"]["sprite"] == replacement
			and content["_library"]["profiles"][family_key]["unit"]["sprite"] == source_sprite
		),
		"Compiled sprite override reaches the born actor without mutating its immutable library profile"
	):
		return false
	var high: Dictionary = opened["battle"].unit(1).duplicate(true)
	high["level"] = 20
	_class_pick = 8
	_last = true
	_draws.clear()
	var first: Dictionary = summons.birth(high, [high], [], {})
	if not _expect(
		(
			first["ok"]
			and first["unit"]["level"] == 22
			and first["unit"]["classId"] == 37
			and first["unit"]["inventory"][0]["templateId"] == 45
		),
		"Level20 can produce trusted level22, promoted37 and last legal weapon45"
	):
		return false
	if not _expect(
		(
			(
				first["unit"]["attributes"]
				== {"strength": 0, "skill": 12, "speed": 14, "defense": 10, "magic": 13, "luck": 9}
			)
			and first["unit"]["maxHp"] == 37
			and first["unit"]["move"] == 6
		),
		"Class37 level22 with max noise matches original base47/growth19 worked example"
	):
		return false
	var corpse: Dictionary = first["unit"].duplicate(true)
	corpse["hp"] = 0
	corpse["visible"] = false
	var old_item: String = corpse["inventory"][0]["id"]
	var second: Dictionary = summons.birth(
		high,
		[high, corpse],
		[corpse["inventory"][0]],
		{"nextGeneration": 2, "bindings": [first["binding"]]}
	)
	return _expect(
		(
			second["ok"]
			and second["unit"]["id"] == 20
			and second["unit"]["inventory"][0]["id"] != old_item
		),
		"Recycled unit ID gets a new opaque held-item identity without warehouse collision"
	)


func _command(opened: Dictionary) -> bool:
	var battle: RefCounted = Battle.new(opened["content"], _roll, false)
	if not _expect(
		battle.restore_snapshot(opened["battle"].snapshot())["ok"], "Restore command boundary"
	):
		return false
	_class_pick = 0
	_last = false
	_draws.clear()
	var staff: String = ""
	for held: Dictionary in battle.unit(1)["inventory"]:
		if held["templateId"] == 59:
			staff = held["id"]
	var before: Dictionary = battle.snapshot()
	if not _expect(
		battle.can_summon(1, staff) and battle.snapshot() == before and _draws.is_empty(),
		"Availability is a pure query"
	):
		return false
	var invalid: Dictionary = battle.summon_unit(1, "not owned")
	if not _expect(
		not invalid["ok"] and battle.snapshot() == before, "Invalid item rejects atomically"
	):
		return false
	var used: Dictionary = battle.summon_unit(1, staff)
	if not _expect(
		(
			used["ok"]
			and used["births"].size() == 1
			and battle.unit(1)["action"] == 2
			and battle.unit(1)["experience"] == 12
		),
		"One summon commits caster action and common staff experience once"
	):
		return false
	for held: Dictionary in battle.unit(1)["inventory"]:
		if held["id"] == staff:
			if not _expect(held["durability"] == 9, "Summoning consumes one durability"):
				return false
	var after: Dictionary = battle.snapshot()
	return _expect(
		not battle.summon_unit(1, staff)["ok"] and battle.snapshot() == after,
		"Already committed actor cannot summon twice"
	)


func _ai_cases(opened: Dictionary) -> bool:
	if not _ai_choice(opened, 87):
		return false
	for older: Dictionary in [
		{"map": "m2", "prepared": M2.prepare(M2.CONTEXTS[0], _zero), "caster": 35},
		{"map": "m4", "prepared": M4.prepare(M4.CONTEXTS[0], _zero), "caster": 30}
	]:
		var prepared: Dictionary = older["prepared"]
		if not _expect(prepared["ok"], "Prepare earlier actual 59 holder"):
			return false
		var prior: Dictionary = Session.new().open(
			Matrix.CHAPTER, older["map"], {"progress": prepared["progress"]}, _zero
		)
		if (
			not _expect(prior["ok"], "Open earlier actual 59 map")
			or not _ai_choice(prior, older["caster"])
		):
			return false
	return true


func _ai_choice(opened: Dictionary, caster: int) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	var instance: String = ""
	var protected: Array[int] = []
	for check: Dictionary in opened["content"]["story"]["outcomeRules"]["checks"]:
		if check["condition"] == "unitRetired":
			protected.append(int(check["unitId"]))
	for actor: Dictionary in state["units"]:
		if int(actor["id"]) != caster:
			if int(actor["id"]) in protected:
				actor["hp"] = actor["maxHp"]
				actor["visible"] = true
				actor["flags"] &= ~1
				actor["move"] = 0
			elif actor["faction"] != 0:
				actor["hp"] = 0
				actor["visible"] = false
				actor["flags"] |= 1
			continue
		actor["move"] = 0
		actor["visible"] = true
		actor["flags"] &= ~1
		for held: Dictionary in actor["inventory"]:
			if int(held["templateId"]) == 59:
				instance = held["id"]
				actor["inventory"] = [held]
				actor["equippedInstanceId"] = ""
				break
	if not _expect(not instance.is_empty(), "Earlier and current caster really holds59"):
		return false
	var battle: RefCounted = Battle.new(opened["content"], _roll, false)
	var restored: Dictionary = battle.restore_snapshot(state)
	if not _expect(restored["ok"], "Restore explicit AI-only boundary: " + str(restored)):
		return false
	var ended: Dictionary = battle.end_phase()
	if not _expect(ended["ok"], "Enter the real automatic queue"):
		return false
	var steps: int = 0
	while battle.automatic_actor() != caster and steps < state["units"].size() * 3:
		var prior_actor: int = battle.automatic_actor()
		var progressed: Dictionary = (
			battle.end_phase() if prior_actor < 0 else battle.wait_unit(prior_actor)
		)
		if not _expect(progressed["ok"], "Wait existing actors until the actual staff caster"):
			return false
		steps += 1
	if not _expect(battle.automatic_actor() == caster, "Existing phase queue reaches staff caster"):
		return false
	_draws.clear()
	var begun: Dictionary = battle.begin_automatic_action(caster)
	if not _expect(
		(
			begun["ok"]
			and begun["plan"]["summonItem"] == instance
			and begun["plan"]["actionMode"] == "summon"
			and _draws.is_empty()
		),
		"AI selects its original-cell59 candidate without RNG"
	):
		return false
	_class_pick = 0
	_last = false
	var result: Dictionary = battle.summon_unit(caster, instance)
	if not _expect(
		result["ok"] and result["births"].size() == 1,
		"AI executes the selected staff through shared command"
	):
		return false
	var birth_id: int = int(result["births"][0]["unit"])
	steps = 0
	while battle.automatic_actor() >= 0 and steps < state["units"].size():
		var queued: int = battle.automatic_actor()
		if not _expect(queued != birth_id, "Newborn never enters the current automatic queue"):
			return false
		if not _expect(battle.wait_unit(queued)["ok"], "Drain remaining preexisting actors"):
			return false
		steps += 1
	if not _expect(
		battle.automatic_actor() == -1 and battle.unit(birth_id)["action"] == 0,
		"Newborn remains ready after the old phase queue finishes"
	):
		return false
	if not _expect(
		battle.end_phase()["ok"] and battle.phase == 0, "Return to the stable player phase"
	):
		return false
	var saved: Dictionary = JSON.parse_string(JSON.stringify(battle.snapshot()))
	_draws.clear()
	var cold: Dictionary = Session.new().open(
		Matrix.CHAPTER, opened["content"]["entry"]["battleId"], {"snapshot": saved}, _roll
	)
	return _expect(
		cold["ok"] and _draws.is_empty() and cold["battle"].unit(birth_id) == battle.unit(birth_id),
		"Earlier/current maps cold-open the summoned family and held items without RNG"
	)


func _roll(limit: int) -> int:
	_draws.append(limit)
	if _draws.size() == 2:
		return _class_pick
	return limit - 1 if _last else 0


func _zero(_limit: int) -> int:
	return 0


func _expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(1)
	return value
