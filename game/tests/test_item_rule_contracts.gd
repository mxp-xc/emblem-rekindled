extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(_limit: int) -> int: return 0
	)
	var combat: RefCounted = load("res://gameplay/combat_rules.gd").new(
		content["rules"], content["map"]["terrain"]
	)
	var inventory: RefCounted = load("res://gameplay/unit_inventory.gd").new(
		combat, func(_limit: int) -> int: return 0
	)
	var records: RefCounted = load("res://gameplay/unit_record.gd").new(content, combat)
	for sample: Array in [
		[9, 1, true],
		[9, 0, false],
		[23, 1, false],
		[53, 1, false],
		[55, 1, false],
		[56, 1, false],
		[60, 1, false],
		[999, 1, false]
	]:
		var actor: Dictionary = battle.unit(0)
		var held: Dictionary = {
			"id": "equipment-case", "templateId": sample[0], "durability": sample[1]
		}
		actor["inventory"] = [held]
		actor["equippedInstanceId"] = held["id"]
		var before: Dictionary = actor.duplicate(true)
		if (
			combat.can_equip(actor, held) != sample[2]
			or inventory.can_equip(actor, held) != sample[2]
			or records.decode(actor, {})["ok"] != sample[2]
			or actor != before
		):
			fail(
				"Manual equipment and restored equipment must share readonly class/type/durability permission"
			)
			return
	var owner: Dictionary = battle.unit(0)
	owner["inventory"] = [
		{"id": "herb", "templateId": 60, "durability": 3},
		{"id": "empty-sword", "templateId": 9, "durability": 0},
		{"id": "first-sword", "templateId": 1, "durability": 2},
		{"id": "later-sword", "templateId": 9, "durability": 15}
	]
	inventory.auto_equip(owner)
	if (
		owner["equippedInstanceId"] != "first-sword"
		or owner["inventory"][0]["id"] != "first-sword"
		or owner["inventory"][1]["id"] != "herb"
	):
		fail(
			"Auto equipment must choose the first permitted instance and preserve the remaining order"
		)
		return
	for template: int in [9, 18, 26, 37, 60, 61, 62, 50, 53, 55, 56]:
		owner = battle.unit(0)
		owner["hp"] = 1
		var held: Dictionary = {"id": "use-case", "templateId": template, "durability": 2}
		owner["inventory"] = [held]
		owner["equippedInstanceId"] = ""
		var allowed: bool = template in [9, 18, 26, 37, 60, 61, 62]
		var candidate: bool = not inventory.candidates(owner, "use").is_empty()
		var result: Dictionary = inventory.use_item(owner, held["id"])
		if candidate != allowed or result["ok"] != allowed:
			fail("Self-use candidates and execution must agree without opening unsupported effects")
			return
		if allowed:
			var expected: int = int(combat.item_definition(template)["power"])
			if template == 60:
				expected = 10
			elif template == 61:
				expected = 20
			elif template == 62:
				expected = 29
			if result["healed"] != mini(expected, 29) or held["durability"] != 1:
				fail("Self-use must retain original recovery amounts and consume one held charge")
				return
		owner["hp"] = owner["maxHp"]
		var before: Dictionary = owner.duplicate(true)
		result = inventory.use_item(owner, held["id"])
		if allowed and (not result["ok"] or result["consumed"] or owner != before):
			fail("Full-HP self-use must succeed without consuming an item")
			return
	for template: int in range(53, 60):
		owner = battle.unit(9)
		var held: Dictionary = {"id": "staff-case", "templateId": template, "durability": 1}
		owner["inventory"] = [held]
		var allowed: bool = template in [53, 54, 55, 56]
		if inventory.can_heal_with(owner, held) != allowed or inventory.can_heal_with(owner, {}):
			fail("Only verified HP/auxiliary staffs53..56 may enter staff targeting")
			return
		held["durability"] = 0
		if inventory.can_heal_with(owner, held):
			fail("Depleted healing staves must be unavailable")
			return
		held["durability"] = 1
		owner["equipMask"] = 1
		if inventory.can_heal_with(owner, held):
			fail("Healing still requires the actor staff equipment mask")
			return
	owner = battle.unit(0)
	owner["inventory"] = [{"id": "protected", "templateId": 50, "durability": 0}]
	var before: Dictionary = owner.duplicate(true)
	if (
		not inventory.candidates(owner, "discard").is_empty()
		or inventory.discard(owner, "protected")["ok"]
		or owner != before
	):
		fail("Protected item 50 must be excluded from candidates and reject discard atomically")
		return
	for sample: Array in [
		[40, 44, 1], [44, 40, -1], [44, 42, 1], [42, 40, 1], [40, 41, 0], [46, 44, 0]
	]:
		var actor: Dictionary = battle.unit(0)
		var target: Dictionary = battle.unit(9)
		actor["inventory"] = [{"id": "first", "templateId": sample[0], "durability": 1}]
		target["inventory"] = [{"id": "second", "templateId": sample[1], "durability": 1}]
		actor["equippedInstanceId"] = "first"
		target["equippedInstanceId"] = "second"
		if combat.forecast(actor, target)["advantage"] != sample[2]:
			fail("Elemental forecast must preserve the original cycle and neutral non-elements")
			return
	print("PASS item rule contracts: equipment/restore order, self-use, staff, discard, elements")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
