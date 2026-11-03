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
	# m0 has this class but does not normally equip weapon 41; use its native recipe.
	var catalog: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/generated/library/catalog.json")
	)
	var orbit_profile: Dictionary = catalog["profiles"]["source_39_job_12_faction_2"]
	content["battleClips"]["appearances"]["67:41"] = orbit_profile["motion"]["stage_0"]["41"]
	content["battleArt"]["appearances"]["67:41"] = (
		content["battleArt"]["appearances"]["67:40"].duplicate(true)
	)
	var light_profile: Dictionary = catalog["profiles"]["source_67_job_36_faction_2"]
	content["battleClips"]["appearances"]["53:47"] = light_profile["motion"]["stage_0"]["47"]
	content["battleArt"]["appearances"]["53:47"] = (
		content["battleArt"]["appearances"]["53:48"].duplicate(true)
	)
	var library: RefCounted = load("res://app/battle_clip_library.gd").new(content)
	var cases: Array = []
	for config: Dictionary in [
		{"family": "thrown", "weapon": 23, "attacker": 10, "defender": 54, "defender_weapon": 40},
		{"family": "charge", "weapon": 22, "attacker": 10, "defender": 54, "defender_weapon": 40},
		{"family": "leap", "weapon": 9, "attacker": 0, "defender": 54, "defender_weapon": 40},
		{"family": "rush", "weapon": 13, "attacker": 60, "defender": 0, "defender_weapon": 9},
		{"family": "slash", "weapon": 31, "attacker": 62, "defender": 0, "defender_weapon": 9},
		{"family": "wind", "weapon": 30, "attacker": 57, "defender": 0, "defender_weapon": 9},
		{"family": "fire", "weapon": 40, "attacker": 54, "defender": 0, "defender_weapon": 9},
		{
			"family": "fire_seed42",
			"weapon": 40,
			"attacker": 54,
			"defender": 0,
			"defender_weapon": 9
		},
		{"family": "orbit", "weapon": 41, "attacker": 67, "defender": 0, "defender_weapon": 9},
		{
			"family": "light_orbit",
			"weapon": 45,
			"attacker": 53,
			"defender": 0,
			"defender_weapon": 9
		},
		{"family": "light", "weapon": 44, "attacker": 54, "defender": 0, "defender_weapon": 9},
		{
			"family": "light_seed42",
			"weapon": 44,
			"attacker": 54,
			"defender": 0,
			"defender_weapon": 9
		},
		{"family": "special", "weapon": 29, "attacker": 56, "defender": 0, "defender_weapon": 9},
		{
			"family": "special_hit",
			"weapon": 29,
			"attacker": 56,
			"defender": 0,
			"defender_weapon": 9,
			"critical": false
		},
		{
			"family": "wind_small",
			"weapon": 42,
			"attacker": 54,
			"defender": 0,
			"defender_weapon": 9,
			"critical": false
		},
		{
			"family": "wind_large",
			"weapon": 43,
			"attacker": 52,
			"defender": 0,
			"defender_weapon": 9,
			"critical": false
		},
		{"family": "wind6", "weapon": 43, "attacker": 52, "defender": 0, "defender_weapon": 9},
		{"family": "wind5", "weapon": 42, "attacker": 54, "defender": 0, "defender_weapon": 9},
		{
			"family": "death_light",
			"weapon": 47,
			"attacker": 53,
			"defender": 0,
			"defender_weapon": 9,
			"critical": false
		},
		{
			"family": "death_light_critical",
			"weapon": 47,
			"attacker": 53,
			"defender": 0,
			"defender_weapon": 9
		},
		{
			"family": "drain",
			"weapon": 48,
			"attacker": 53,
			"defender": 0,
			"defender_weapon": 9,
			"critical": false,
			"heal": 7
		},
		{
			"family": "drain_critical",
			"weapon": 48,
			"attacker": 53,
			"defender": 0,
			"defender_weapon": 9,
			"heal": 7
		}
	]:
		var oracle: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(
				(
					"res://tests/fixtures/chapter_1_native_critical_%s_hit_death.json"
					% config["family"]
				)
			)
		)
		for sample: Dictionary in oracle["cases"]:
			sample.merge(config)
			cases.append(sample)
	for sample: Dictionary in cases:
		var attacker_id: int = int(sample["attacker"])
		var defender_id: int = int(sample["defender"])
		var attacker: Dictionary = opened["battle"].unit(attacker_id)
		var defender: Dictionary = opened["battle"].unit(defender_id)
		attacker["inventory"] = [
			{"id": "held", "templateId": int(sample["weapon"]), "durability": 3}
		]
		attacker["equippedInstanceId"] = "held"
		attacker["hp"] = 20
		defender["hp"] = 40
		var participants: Array = (
			[attacker, defender] if int(sample["slot"]) == 0 else [defender, attacker]
		)
		var result := {
			"participants": participants,
			"resolvedWeapons":
			{
				str(attacker_id): int(sample["weapon"]),
				str(defender_id): int(sample["defender_weapon"])
			},
			"strikes":
			[
				{
					"attacker": attacker_id,
					"defender": defender_id,
					"hit": true,
					"critical": sample.get("critical", true),
					"damage": int(sample["damage"]),
					"heal": int(sample.get("heal", 0))
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
			if (
				expected.has("attackerHp")
				and animation.hp[attacker_id] != int(expected["attackerHp"])
			):
				fail(
					(
						"Attacker HP mismatch %s slot %d tick %d"
						% [sample["family"], sample["slot"], index]
					)
				)
				return
			var offset: Array = animation.frame["backgroundOffset"]
			if (
				animation.hp[defender_id] != int(expected["hp"])
				or (
					Vector2i(int(offset[0]), int(offset[1]))
					!= Vector2i(int(expected["offset"][0]), int(expected["offset"][1]))
				)
				or animation.frame["flash"] != expected["flash"]
			):
				fail(
					(
						"HP or scene mismatch %s slot %d damage %d tick %d: hp %d/%s offset %s/%s flash %s/%s"
						% [
							sample["family"],
							sample["slot"],
							sample["damage"],
							index,
							animation.hp[defender_id],
							expected["hp"],
							offset,
							expected["offset"],
							animation.frame["flash"],
							expected["flash"]
						]
					)
				)
				return
			var remaining: int = int(animation.frame["nativeSky"]["criticalRemaining"])
			var pattern: Variant = ((12 - remaining) / 2) % 3 if remaining > 0 else null
			if expected.has("skyPattern") and pattern != expected["skyPattern"]:
				fail(
					(
						"Critical sky mismatch slot %d damage %d tick %d"
						% [sample["slot"], sample["damage"], index]
					)
				)
				return
			if (
				expected.has("skyColor")
				and animation.frame["nativeSky"]["color"] != expected["skyColor"]
			):
				fail(
					(
						"Critical sky color mismatch slot %d damage %d tick %d"
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
	print("PASS: native critical hit and death for both source slots")
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
