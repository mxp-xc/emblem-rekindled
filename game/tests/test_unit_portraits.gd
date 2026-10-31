extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	for commander: int in [9, 0]:
		scene.battle.configure_commander(commander, true, true)
		var before: Dictionary = scene.battle.snapshot()
		for actor: Dictionary in before["units"]:
			scene.selected_unit = int(actor["id"])
			scene._show_information()
			var picture: TextureRect = scene.unit_information.get_node_or_null("Portrait")
			if picture == null or picture.texture == null:
				fail(
					"Unit information must expose its actual identity image in the portrait header"
				)
				return
			var source: Texture2D
			if actor["id"] in [0, 9]:
				var key: String = "portrait_" + str(int(actor["id"]))
				source = load(
					scene.content["entry"]["interface"].get_base_dir().path_join(
						scene.content["interface"]["textures"][key]["texture"]
					)
				)
			else:
				source = load(scene.content["entry"]["spriteDirectory"].path_join(actor["sprite"]))
			var expected: Image = source.get_image()
			if actor["id"] not in [0, 9]:
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
