extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	# Read source profiles independently of Main's portrait resolver and interface aliases.
	var chapter: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(scene.content["entry"]["chapterPath"])
	)
	var definition: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(chapter["battles"][scene.content["entry"]["battleId"]])
	)
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chapter["library"]))
	scene.resume_battle(scene.battle)
	for commander: int in [9, 0]:
		if not scene.battle.configure_commander(commander, true, true)["ok"]:
			fail(
				"Both original commanders must actually be selected for independent portrait checks"
			)
			return
		var before: Dictionary = scene.battle.snapshot()
		if before["units"].size() != 32:
			fail("The portrait regression must inspect all 32 actual first-map identities")
			return
		for actor: Dictionary in before["units"]:
			scene.selected_unit = int(actor["id"])
			scene._show_information()
			var picture: TextureRect = scene.unit_information.get_node_or_null("Portrait")
			if picture == null or picture.texture == null:
				fail(
					"Unit information must expose its actual identity image in the portrait header"
				)
				return
			var recipe: String = (
				"%s_%d_job_%d_faction_%d"
				% [
					"slot" if actor.get("temporary", false) else "source",
					actor["sourceId"],
					actor["classId"],
					actor["faction"]
				]
			)
			var profile: Dictionary = library["profiles"][definition["profiles"][recipe]]
			var dedicated: bool = profile["portrait"]["texture"] != null
			var source: Texture2D
			if dedicated:
				source = load(profile["portrait"]["texture"]["texture"])
			else:
				source = load(profile["unit"]["sprite"])
			var expected: Image = source.get_image()
			if not dedicated:
				expected = expected.get_region(expected.get_used_rect())
			var shown: Image = picture.texture.get_image()
			if shown.get_size() != expected.get_size() or shown.get_data() != expected.get_data():
				fail(
					(
						"Information must show the inspected unit's own image, independent of commander: "
						+ str(actor["id"])
					)
				)
				return
		if scene.battle.snapshot() != before:
			fail("Changing display portraits must not change commander bonuses or battle authority")
			return
	scene.queue_free()
	await process_frame
	print(
		"PASS portraits: 32 identities under both commanders, own portraits and cropped unit sprites"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
