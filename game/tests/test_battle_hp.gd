extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://features/battle/battle_hp.gd")
	if script == null:
		fail("Source-timed presentation HP model is missing")
		return
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not content["ok"]:
		fail("The HP oracle requires validated current chapter content: " + str(content))
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
		var key: String = (
			"%s/%s/%d/%s"
			% [
				attacker["actionGroup"],
				defender["defenseGroup"],
				sample["sourceSlot"],
				sample["outcome"]
			]
		)
		var clip: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(
				content["entry"]["resourceDirectory"].path_join(clips["clips"][key])
			)
		)
		var hp: RefCounted = script.new(
			clip,
			int(oracle["initialAttackerHp"]),
			int(oracle["initialDefenderHp"]),
			int(sample["damage"]),
			int(sample["recovery"]),
			int(clips["logicTickUnits"])
		)
		for row: Array in sample["ticks"]:
			hp.advance()
			var actual: Array = [
				hp.tick * int(clips["logicTickUnits"]),
				hp.tick * int(clips["tickMillis"]),
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
							"Source HP timing mismatch %s tick%d field%d: %s != %s"
							% [name, hp.tick, index, actual[index], row[index]]
						)
					)
					return
			if hp.finished != (hp.tick == int(sample["endTick"])):
				fail("Source completion tick mismatch: " + name)
				return
	print(
		"PASS battle HP: 238 source hit/miss/critical, slot order, damage/recovery/death/J timelines"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
