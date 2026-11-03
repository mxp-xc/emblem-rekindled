extends SceneTree

const NativeHP = preload("res://features/battle/native_battle_hp.gd")


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not content["ok"]:
		fail("Chapter content unavailable: " + str(content))
		return
	var clips: Dictionary = content["battleClips"]
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_battle_hp.json")
	)
	for name: String in oracle["cases"]:
		var sample: Dictionary = oracle["cases"][name]
		var attacker: Dictionary = clips["appearances"][sample.get(
			"clipAppearance", sample["attackerAppearance"]
		)]
		var defender: Dictionary = clips["appearances"][sample["defenderAppearance"]]
		var hp: RefCounted = NativeHP.new(
			clips["actionGroups"][attacker["actionGroup"]],
			clips["defenseGroups"][defender["defenseGroup"]],
			sample["outcome"],
			int(sample["sourceSlot"]),
			int(oracle["initialAttackerHp"]),
			int(oracle["initialDefenderHp"]),
			int(sample["damage"]),
			int(sample["recovery"])
		)
		for row: Array in sample["ticks"]:
			hp.advance()
			var actual: Array = [
				hp.tick * 50,
				hp.tick * 65,
				hp.attacker_hp,
				hp.defender_hp,
				hp.attacker_state,
				hp.attacker_step,
				hp.last_action_units,
				hp.damage_active,
				hp.recovery_active
			]
			for index: int in range(actual.size()):
				if actual[index] != row[index]:
					fail(
						(
							"Native HP mismatch %s tick %d field %d: %s != %s"
							% [name, hp.tick, index, actual[index], row[index]]
						)
					)
					return
			if hp.finished != (hp.tick == int(sample["endTick"])):
				fail("Native HP completion mismatch %s tick %d" % [name, hp.tick])
				return
	print("PASS: generated motion and 238 native HP timelines")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
