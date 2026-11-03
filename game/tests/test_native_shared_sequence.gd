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
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_native_sequence.json")
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
		var prepared: Dictionary = library.prepare(
			{
				"participants": participants,
				"resolvedWeapons": {"54": 44, "0": 9},
				"strikes":
				[
					{
						"attacker": 54,
						"defender": 0,
						"hit": true,
						"critical": true,
						"damage": 7,
						"heal": 0
					},
					{
						"attacker": 54,
						"defender": 0,
						"hit": true,
						"critical": false,
						"damage": 7,
						"heal": 0
					}
				]
			}
		)
		if not prepared["ok"]:
			fail(str(prepared))
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
				or animation.frame["flash"] != expected["flash"]
			):
				fail(
					(
						"Sequence HP or scene mismatch slot %d tick %d: %s vs %s"
						% [sample["slot"], index, animation.frame, expected]
					)
				)
				return
			var remaining: int = int(animation.frame["nativeSky"]["criticalRemaining"])
			var pattern: Variant = ((12 - remaining) / 2) % 3 if remaining > 0 else null
			if (
				pattern != expected["skyPattern"]
				or animation.frame["nativeSky"]["color"] != expected["skyColor"]
			):
				fail("Sequence sky mismatch slot %d tick %d" % [sample["slot"], index])
				return
			var actual: Array = animation.frame["layers"]
			var wanted: Array = expected["layers"]
			if actual.size() != wanted.size():
				fail(
					(
						"Sequence layer count mismatch slot %d tick %d: %d vs %d"
						% [sample["slot"], index, actual.size(), wanted.size()]
					)
				)
				return
			for layer_index: int in range(wanted.size()):
				if not matches_layer(actual[layer_index], wanted[layer_index], content):
					fail(
						(
							"Sequence layer mismatch slot %d tick %d index %d: %s vs %s"
							% [
								sample["slot"],
								index,
								layer_index,
								actual[layer_index],
								wanted[layer_index]
							]
						)
					)
					return
	print("PASS: original consecutive actions share RNG and effect lifecycle")
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
	var image: Image
	if actual.has("beam"):
		image = Image.create(240, 320, false, Image.FORMAT_RGBA8)
		var age: int = int(actual["beam"]["elapsed"])
		var width: int = (
			9
			if age == 0 or age == int(actual["beam"]["duration"]) - 50
			else (12 if age == 50 else 24)
		)
		var current: int = width
		for color: int in [16225309, 16634902, 0xfff799]:
			image.fill_rect(
				Rect2i(int(actual["x"]) - (current >> 1), int(actual["y"]) - 60, current, 60),
				Color.hex((color << 8) | 255)
			)
			current -= width / 3
		actual = actual.duplicate()
		actual["x"] = 0
		actual["y"] = 0
	elif actual.has("particles"):
		image = Image.create(240, 320, false, Image.FORMAT_RGBA8)
		var sparks: RefCounted = actual["particles"]
		for particle: Array in sparks.particles:
			var at := Vector2i(
				int(actual["x"]) + (int(particle[0]) >> 10),
				int(actual["y"]) + (int(particle[1]) >> 10)
			)
			image.fill_rect(
				Rect2i(at, Vector2i.ONE * int(particle[4])), Color.hex((sparks.color << 8) | 255)
			)
		actual = actual.duplicate()
		actual["x"] = 0
		actual["y"] = 0
	else:
		var source: Variant = actual.get("textureSource")
		if source == null:
			source = content["battleClips"]["textures"][actual["texture"]]["texture"]
		image = (
			source.get_image()
			if source is Texture2D
			else Image.load_from_file(ProjectSettings.globalize_path(source))
		)
	var oracle: Image = Image.load_from_file(ProjectSettings.globalize_path(expected[1]))
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
