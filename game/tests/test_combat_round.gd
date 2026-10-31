extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 21]
		elif spawn["id"] == 59:
			spawn["position"] = [9, 21]
	var script: Script = load("res://gameplay/battle_state.gd")
	if not script.new(content).has_method("attack_unit"):
		fail("Battle attack command is missing")
		return
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_combat.json")
	)
	for sample: Dictionary in oracle["controlledRounds"]:
		var battle: RefCounted = script.new(
			content, func(limit: int) -> int: return int(sample["fixedRoll"]) % limit
		)
		var result: Dictionary = battle.attack_unit(0, 59)
		if not result["ok"] or result["strikes"].size() != sample["strikes"].size():
			fail("Attack sequence differs from original controlled round")
			return
		for index: int in range(result["strikes"].size()):
			var strike: Dictionary = result["strikes"][index]
			var expected: Array = sample["strikes"][index].map(
				func(value: Variant) -> int: return int(value)
			)
			var actual: Array = [
				int(strike["counter"]),
				0 if strike["hit"] else 1,
				0 if strike["critical"] else 1,
				strike["hpBefore"],
				strike["hpAfter"],
				strike["damage"],
				strike["heal"]
			]
			if actual != expected:
				fail(
					(
						"Strike %d differs at roll %s: %s != %s"
						% [index, sample["fixedRoll"], actual, expected]
					)
				)
				return
		var alm: Dictionary = battle.unit(0)
		var enemy: Dictionary = battle.unit(59)
		if (
			alm["hp"] != sample["almHp"]
			or enemy["hp"] != sample["enemyHp"]
			or alm["proficiency"] != sample["almProficiency"]
			or enemy["proficiency"] != sample["enemyProficiency"]
		):
			fail("HP or proficiency differs from original round")
			return
		if (
			_durability(alm, 9) != sample["almItems"][0][1]
			or _durability(enemy, 13) != sample["enemyItems"][0][1]
		):
			fail("Hit/miss durability differs from original round")
			return
		var before: Dictionary = battle.snapshot()
		if battle.attack_unit(0, 59)["ok"] or battle.snapshot() != before:
			fail("Attack cannot be committed twice")
			return
	print(
		"PASS combat round: original hit/counter/follow-up, miss, critical, durability, no repeat"
	)
	quit(0)


func _durability(unit: Dictionary, template_id: int) -> int:
	for item: Dictionary in unit["inventory"]:
		if int(item["templateId"]) == template_id:
			return int(item["durability"])
	return -1


func fail(message: String) -> void:
	push_error(message)
	quit(1)
