extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
const Progression = preload("res://gameplay/unit_progression.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
var _draws: Array[int] = []
var _high: bool = false
var _content: Dictionary


func _initialize() -> void:
	_content = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not _expect(_content.get("ok", false), "Load current chapter content"):
		return
	_content["story"]["outcomeRules"]["checks"] = []
	_content["story"]["combatEvents"] = _content["story"].get("combatEvents", [])
	_content["story"]["combatEvents"].append(
		{
			"id": "controlled_death",
			"unitId": 59,
			"trigger": "unitDeath",
			"beforeRetirement": "controlled_death_scene"
		}
	)
	if not _consumables() or not _staff() or not _promotion_rules() or not _revival():
		return
	print("PASS m10 item abilities: gold/fruit boundaries, two-stage staffs, promotion and revival")
	quit(0)


func _fixture(template: int, owner: int = 0, charges: int = 1) -> RefCounted:
	var battle := Battle.new(_content, _roll)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		actor["visible"] = actor["id"] in [0, 9, 59]
		if actor["id"] == owner:
			actor["inventory"].append(
				{"id": "ability", "templateId": template, "durability": charges}
			)
		if actor["id"] == 0:
			actor["hp"] = 23
	var restored: Dictionary = battle.restore_snapshot(state)
	if not _expect(restored["ok"], "Restore controlled held item: " + str(restored)):
		return null
	_draws.clear()
	return battle


func _consumables() -> bool:
	for high: bool in [false, true]:
		_high = high
		var battle: RefCounted = _fixture(63)
		if battle == null:
			return false
		var before: Dictionary = battle.unit(0)
		var result: Dictionary = battle.use_item(0, "ability")
		if not _expect(
			(
				result["ok"]
				and result["rolledGold"] == (3000 if high else 1000)
				and _draws == [2001]
				and result["creditedGold"] == result["rolledGold"]
				and battle.unit(0)["experience"] == before["experience"]
				and battle.unit(0)["proficiency"] == before["proficiency"]
				and battle.unit(0)["action"] == 2
			),
			"Gold draws once with inclusive endpoints and no XP"
		):
			return false
		var settled: Dictionary = battle.snapshot()
		if not _expect(
			not battle.use_item(0, "ability")["ok"] and battle.snapshot() == settled,
			"Repeated item submission cannot award gold twice"
		):
			return false
	_high = false
	var stats: Array[String] = [
		"strength", "skill", "speed", "luck", "defense", "magic", "maxHp", "move"
	]
	for index: int in range(stats.size()):
		for full: bool in [false, true]:
			var battle: RefCounted = _fixture(68 + index)
			if battle == null:
				return false
			var state: Dictionary = battle.snapshot()
			var stat: String = stats[index]
			var cap: int = 60 if stat == "maxHp" else (10 if stat == "move" else 30)
			for actor: Dictionary in state["units"]:
				if actor["id"] == 0:
					if stat in ["maxHp", "move"]:
						actor[stat] = cap if full else 5
						if stat == "maxHp":
							actor["hp"] = 4
					else:
						actor["attributes"][stat] = cap if full else 5
			if not _expect(battle.restore_snapshot(state)["ok"], "Prepare fruit boundary"):
				return false
			var before: Dictionary = battle.unit(0)
			_draws.clear()
			var result: Dictionary = battle.use_item(0, "ability")
			if not _expect(
				(
					result["ok"]
					and result["consumed"]
					and (
						result["statAfter"]
						== (cap if full else 5 + (3 if index == 6 else (1 if index == 7 else 2)))
					)
					and result["hpAfter"] == before["hp"]
					and _draws.is_empty()
					and battle.unit(0)["inventory"].size() == before["inventory"].size() - 1
				),
				"Fruit full/ordinary consumes only itself without RNG or healing"
			):
				return false
	return true


func _staff() -> bool:
	for template: int in [57, 58]:
		var battle: RefCounted = _fixture(template, 9)
		if battle == null:
			return false
		var before: Dictionary = battle.snapshot()
		if not _expect(
			(
				0 in battle.staff_targets(9, "ability")
				and 9 not in battle.staff_targets(9, "ability")
				and 59 not in battle.staff_targets(9, "ability")
				and battle.snapshot() == before
			),
			"Staff queries are pure and same-alliance adjacent only"
		):
			return false
		var result: Dictionary
		var target_before: Dictionary = battle.unit(0)
		if template == 57:
			var options: Array[Dictionary] = battle.repair_options(9, 0, "ability")
			var held: Dictionary = options[0]
			result = battle.repair_unit(9, 0, "ability", held["id"])
			if not _expect(
				result["durabilityAfter"] == held["durability"],
				"Full durability still repairs and consumes"
			):
				return false
		else:
			var caster: Dictionary = battle.unit(9)
			var illegal: Dictionary = battle.teleport_unit(
				9, 0, "ability", Vector2i(caster["x"], caster["y"])
			)
			if not _expect(
				not illegal["ok"] and battle.snapshot() == before,
				"Occupied teleport rejects atomically"
			):
				return false
			var field: Dictionary = battle.teleport_field(9, 0, "ability")
			var destination: Vector2i = field.keys()[0]
			result = battle.teleport_unit(9, 0, "ability", destination)
			if not _expect(
				Vector2i(battle.unit(0)["x"], battle.unit(0)["y"]) == destination,
				"Teleport commits the selected global empty destination"
			):
				return false
		if not _expect(
			(
				result["ok"]
				and result["expiredItem"]["templateId"] == template
				and battle.unit(9)["action"] == 2
				and battle.unit(9)["experience"] == 12
				and battle.unit(0)["hp"] == target_before["hp"]
				and battle.unit(0)["action"] == target_before["action"]
				and battle.unit(0)["inventory"] == target_before["inventory"]
				and _draws.is_empty()
			),
			"Final staff selection consumes once, awards XP and preserves target action/HP/inventory"
		):
			return false
	return true


func _promotion_rules() -> bool:
	var progression := Progression.new(_content["rules"])
	var combat := Combat.new(_content["rules"], _content["map"]["terrain"])
	if not _expect(
		_content["rules"].get("promotions", []).size() == 6,
		"Chapter exports six original promotion rules"
	):
		return false
	var battle := Battle.new(_content, _roll)
	for row: Dictionary in _content["rules"]["promotions"]:
		var actor: Dictionary = battle.unit(0)
		actor["classId"] = int(row["fromClassId"])
		actor["level"] = int(row["minimumLevel"]) - 1
		if not _expect(not progression.eligible(actor), "Promotion refuses below threshold"):
			return false
		actor["level"] += 1
		actor["experience"] = 37
		actor["proficiency"] = 55
		actor["hp"] = 23
		actor["maxHp"] = 60
		actor["attributes"]["strength"] = 30
		var before: Dictionary = actor.duplicate(true)
		_draws.clear()
		var result: Dictionary = progression.apply(actor, combat)
		if not _expect(
			(
				result["ok"]
				and actor["classId"] == row["toClassId"]
				and actor["hp"] == 23
				and actor["level"] == before["level"]
				and actor["experience"] == 37
				and actor["proficiency"] == 55
				and actor["maxHp"] == 60 + row["gains"]["maxHp"]
				and actor["attributes"]["strength"] == 30 + row["gains"]["strength"]
				and _draws.is_empty()
			),
			"Six finite promotions retain training/current HP and permit fixed over-cap gains"
		):
			return false
		if not _expect(not progression.eligible(actor), "Stage1 cannot consume another76"):
			return false
	return true


func _revival() -> bool:
	var battle: RefCounted = _fixture(80, 59)
	if battle == null:
		return false
	var state: Dictionary = battle.snapshot()
	var attacker: Dictionary = battle.unit(0)
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 59:
			actor["hp"] = 1
			actor["x"] = attacker["x"]
			actor["y"] = int(attacker["y"]) + 1
			actor["attributes"]["defense"] = 0
			actor["equippedInstanceId"] = ""
			actor["dropTemplateId"] = 63
			actor["inventory"].append({"id": "markedGold", "templateId": 63, "durability": 1})
	if not _expect(battle.restore_snapshot(state)["ok"], "Prepare actual lethal ordinary attack"):
		return false
	var result: Dictionary = battle.attack_unit(0, 59)
	if not _expect(
		(
			result["ok"]
			and result["revivals"].size() == 1
			and battle.unit(59)["visible"]
			and battle.unit(59)["hp"] == battle.unit(59)["maxHp"]
			and (int(battle.unit(59)["flags"]) & 64) != 0
			and result["retirements"].is_empty()
			and not battle.event_completed("controlled_death")
			and result["rewards"]["loot"].size() == 1
			and not result["rewards"]["experience"].is_empty()
		),
		"Entire lethal combat awards knockdown XP then revives without death retirement"
	):
		return false
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["action"] = 0
		if actor["id"] == 59:
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Restore revived state without another ring"
	):
		return false
	result = battle.attack_unit(0, 59)
	return _expect(
		(
			result["ok"]
			and result["revivals"].is_empty()
			and battle.event_completed("controlled_death")
			and result["retirements"].size() == 1
		),
		"Revival does not burn death marker; a later ordinary death triggers it once"
	)


func _roll(limit: int) -> int:
	_draws.append(limit)
	return limit - 1 if _high else 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
