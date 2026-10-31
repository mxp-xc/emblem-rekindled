extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = _battle(content, 17)
	if not battle.has_method("heal_unit") or not battle.has_method("use_item"):
		fail("Healing and held-item commands are missing")
		return
	var staff: Dictionary = battle.unit(9)["inventory"][0]
	if not battle.has_method("healing_field"):
		fail("Staff targeting must expose its original range independently of target HP")
		return
	var field: Dictionary = battle.healing_field(9, staff["id"])
	if field.size() != 4 or not field.has(Vector2i(10, 11)) or field.has(Vector2i(9, 11)):
		fail("The range-one staff field includes all four orthogonal cells, excluding its caster")
		return
	if not battle.healing_field(0, staff["id"]).is_empty():
		fail("A foreign held staff cannot supply another actor's targeting range")
		return
	if 0 not in battle.heal_targets(9, staff["id"]):
		fail("Adjacent wounded allied hero must be a valid staff target")
		return
	var result: Dictionary = battle.heal_unit(9, 0, staff["id"])
	if (
		not result["ok"]
		or result["healed"] != 13
		or battle.unit(0)["hp"] != 30
		or battle.unit(9)["action"] != 2
		or battle.unit(9)["experience"] != 12
		or battle.unit(9)["inventory"][0]["durability"] != staff["durability"] - 1
	):
		fail(
			"Staff must heal M+10 capped at maxHP, consume one held charge/action and grant original XP"
		)
		return
	var before: Dictionary = battle.snapshot()
	if battle.heal_unit(9, 0, staff["id"])["ok"] or battle.snapshot() != before:
		fail("Healing cannot be repeated after action completion")
		return
	battle = _battle(content, 17)
	var herb: Dictionary = battle.unit(0)["inventory"][1]
	if (
		not battle.use_item(0, herb["id"])["ok"]
		or battle.unit(0)["hp"] != 27
		or battle.unit(0)["inventory"][1]["durability"] != 2
		or battle.unit(0)["action"] != 2
		or battle.unit(0)["experience"] != 0
	):
		fail("Herb must heal ten, consume one held charge/action, and award no XP")
		return
	battle = _battle(content, 10)
	var sword: Dictionary = battle.unit(0)["inventory"][0]
	if (
		not battle.use_item(0, sword["id"])["ok"]
		or battle.unit(0)["hp"] != 26
		or battle.unit(0)["inventory"][0]["durability"] != 14
	):
		fail("Holy sword self-heal must use original weapon power and current durability")
		return
	battle = _battle(content, 30)
	herb = battle.unit(0)["inventory"][1]
	before = battle.snapshot()
	if battle.use_item(9, herb["id"])["ok"] or battle.snapshot() != before:
		fail("A foreign item must reject without partial changes")
		return
	result = battle.heal_unit(9, 0, staff["id"])
	if (
		not result["ok"]
		or result["healed"] != 0
		or battle.unit(0)["hp"] != 30
		or battle.unit(9)["action"] != 2
		or battle.unit(9)["experience"] != 12
		or battle.unit(9)["inventory"][0]["durability"] != 22
	):
		fail("Original player staff use accepts full HP, consumes a charge/action and grants XP")
		return
	result = battle.use_item(0, herb["id"])
	if (
		not result["ok"]
		or result["consumed"]
		or battle.unit(0)["action"] != 2
		or battle.unit(0)["inventory"][1]["durability"] != 3
	):
		fail("Original full-HP self-use ends action without consuming durability")
		return
	for template: int in [9, 60, 53]:
		battle = _battle(content, 20)
		var state: Dictionary = battle.snapshot()
		var owner: int = 9 if template == 53 else 0
		var instance_id: String
		for current: Dictionary in state["units"]:
			if current["id"] != owner:
				continue
			for held: Dictionary in current["inventory"]:
				if held["templateId"] == template:
					held["durability"] = 1
					instance_id = held["id"]
		battle.restore_snapshot(state)
		result = (
			battle.heal_unit(9, 0, instance_id)
			if template == 53
			else battle.use_item(0, instance_id)
		)
		if result.get("expiredItem", {}).get("templateId") != template:
			fail(
				"Last herb/holy/staff charge must retain its removed item for the source expiry notice"
			)
			return
		if battle.unit(0)["hp"] != 30 or battle.unit(owner)["action"] != 2:
			fail(
				"Expiry presentation metadata must preserve successful healing and one consumed action"
			)
			return
	print("PASS support: staff targets/amount/XP, herb, holy heal, full HP, ownership, no repeat")
	quit(0)


func _battle(content: Dictionary, hp: int) -> RefCounted:
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(_limit: int) -> int: return 0
	)
	var state: Dictionary = battle.snapshot()
	for unit: Dictionary in state["units"]:
		if unit["id"] == 0:
			unit["hp"] = hp
	battle.restore_snapshot(state)
	return battle


func fail(message: String) -> void:
	push_error(message)
	quit(1)
