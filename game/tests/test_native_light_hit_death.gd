extends SceneTree

const TextureImage = preload("res://tests/support/texture_image.gd")


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
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_light_hit_death.json")
	)
	for sample: Dictionary in oracle["cases"]:
		var attacker: Dictionary = opened["battle"].unit(54)
		var defender: Dictionary = opened["battle"].unit(0)
		attacker["inventory"] = [{"id": "held", "templateId": 44, "durability": 3}]
		attacker["equippedInstanceId"] = "held"
		attacker["hp"] = 20
		defender["hp"] = 40
		var participants: Array = (
			[attacker, defender] if int(sample["slot"]) == 0 else [defender, attacker]
		)
		var result := {
			"participants": participants,
			"resolvedWeapons": {"54": 44, "0": 9},
			"strikes":
			[
				{
					"attacker": 54,
					"defender": 0,
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
		prepared["visualSeed"] = 0
		var animation: RefCounted = load("res://features/battle/battle_animation.gd").new(prepared)
		for index: int in range(sample["ticks"].size()):
			animation.advance()
			var expected: Dictionary = sample["ticks"][index]
			var offset: Array = animation.frame["backgroundOffset"]
			if (
				animation.hp[0] != int(expected["hp"])
				or (
					Vector2i(int(offset[0]), int(offset[1]))
					!= Vector2i(int(expected["offset"][0]), int(expected["offset"][1]))
				)
				or animation.frame["nativeSky"]["color"] != expected["sky"]
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
	var source: Variant = actual.get("textureSource")
	if source == null:
		source = content["battleClips"]["textures"][actual["texture"]]["texture"]
	var image: Image = TextureImage.read(source)
	var oracle: Image = TextureImage.read(expected[1])
	if image == null or oracle == null:
		return false
	var position := Vector2i(int(actual["x"]), int(actual["y"]))
	var clipped := Rect2i(position, image.get_size()).intersection(Rect2i(0, 0, 240, 320))
	if not clipped.has_area():
		return false
	var region := image.get_region(Rect2i(clipped.position - position, clipped.size))
	var used := region.get_used_rect()
	if clipped.position + used.position != Vector2i(int(expected[2]), int(expected[3])):
		return false
	region = region.get_region(used)
	region.convert(Image.FORMAT_RGBA8)
	oracle.convert(Image.FORMAT_RGBA8)
	return (
		region.get_size() == oracle.get_size()
		and region.get_data() == oracle.get_data()
		and actual["foreground"] == expected[4]
	)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
