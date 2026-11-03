extends SceneTree


func _initialize() -> void:
	var opened: Dictionary = load("res://app/chapter_session.gd").new().open(
		"res://content/chapter_1/chapter.json",
		"",
		{"new": true},
		func(_limit: int) -> int: return 0
	)
	if not opened["ok"]:
		fail(str(opened))
		return
	var content: Dictionary = opened["content"]
	var library: RefCounted = load("res://app/battle_clip_library.gd").new(content)
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_hit_death.json")
	)
	var additional: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_hit_death_seed42.json")
	)
	oracle["cases"].append_array(additional["cases"])
	for sample: Dictionary in oracle["cases"]:
		var attacker: Dictionary = opened["battle"].unit(0)
		var defender: Dictionary = opened["battle"].unit(54)
		attacker["hp"] = 20
		defender["hp"] = 40
		var participants: Array = (
			[attacker, defender] if int(sample["slot"]) == 0 else [defender, attacker]
		)
		var result := {
			"participants": participants,
			"resolvedWeapons": {"0": 9, "54": 40},
			"strikes":
			[
				{
					"attacker": 0,
					"defender": 54,
					"hit": true,
					"critical": false,
					"damage": int(sample["damage"]),
					"heal": 0
				}
			]
		}
		var prepared: Dictionary = library.prepare(result)
		if (
			not prepared["ok"]
			or not prepared["timelines"][0]["generated"]
			or not prepared["timelines"][0]["clip"].is_empty()
		):
			fail("Original hit must be generated without a sampled clip: " + str(sample))
			return
		prepared["visualSeed"] = int(sample.get("seed", 0))
		var animation: RefCounted = load("res://features/battle/battle_animation.gd").new(prepared)
		for index: int in range(sample["ticks"].size()):
			animation.advance()
			var expected: Dictionary = sample["ticks"][index]
			var offset: Array = animation.frame["backgroundOffset"]
			if (
				animation.hp[54] != int(expected["hp"])
				or (
					Vector2i(int(offset[0]), int(offset[1]))
					!= Vector2i(int(expected["offset"][0]), int(expected["offset"][1]))
				)
			):
				fail(
					(
						"HP or scene mismatch slot %d damage %d tick %d"
						% [sample["slot"], sample["damage"], index]
					)
				)
				return
			var actual: Array = animation.frame["layers"]
			var wanted: Array = expected["layers"]
			if actual.size() != wanted.size():
				fail(
					(
						"Layer count mismatch slot %d damage %d tick %d: %d vs %d"
						% [sample["slot"], sample["damage"], index, actual.size(), wanted.size()]
					)
				)
				return
			for layer_index: int in range(wanted.size()):
				if not matches_layer(actual[layer_index], wanted[layer_index], content):
					fail(
						(
							"Layer mismatch slot %d damage %d tick %d index %d: %s vs %s"
							% [
								sample["slot"],
								sample["damage"],
								index,
								layer_index,
								actual[layer_index],
								wanted[layer_index]
							]
						)
					)
					return
	print("PASS: native hit and death frames for both source slots")
	quit(0)


func matches_layer(actual: Dictionary, expected: Array, content: Dictionary) -> bool:
	if expected[0] == "actor":
		return (
			actual.get("actor") == expected[1]
			and int(actual["frame"]) == int(expected[2])
			and int(actual["x"]) == int(expected[3])
			and int(actual["y"]) == int(expected[4])
			and actual["foreground"] == expected[5]
		)
	if actual.has("actor"):
		return false
	var texture: String = str(actual.get("textureSource", ""))
	if texture.is_empty():
		texture = content["battleClips"]["textures"][actual["texture"]]["texture"]
	return (
		texture.get_file() == expected[1]
		and int(actual["x"]) == int(expected[2])
		and int(actual["y"]) == int(expected[3])
		and actual["foreground"] == expected[4]
	)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
