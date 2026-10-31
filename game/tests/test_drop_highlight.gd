extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var information: Control = scene.unit_information
	var before: Dictionary = scene.battle.snapshot()
	for actor: Dictionary in before["units"]:
		scene.selected_unit = int(actor["id"])
		scene._show_information()
		information.show_page(2)
		var expected: Array[String] = []
		match int(actor["id"]):
			64:
				expected = ["钢斧"]
			59:
				expected = ["铁剑"]
			58:
				expected = ["铁枪"]
		if not _matches(information, expected):
			fail("Only the three source enemy drop names must be green: " + str(actor["id"]))
			return
	var actor: Dictionary = scene.battle.unit(59)
	actor["equipMask"] = 2
	actor["inventory"] = [
		{"id": "spear", "templateId": 13, "durability": 30},
		{"id": "drop-a", "templateId": 1, "durability": 30},
		{"id": "drop-b", "templateId": 1, "durability": 7},
		{"id": "drop-empty", "templateId": 1, "durability": 0}
	]
	var texture: Texture2D = load(
		scene.content["entry"]["spriteDirectory"].path_join(actor["sprite"])
	)
	information.present(actor, scene.battle.unit_information(59), texture)
	information.show_page(2)
	if not _matches(information, ["铁剑", "铁剑", "铁剑"]):
		fail("All matching held templates are green, including ineligible and zero-durability rows")
		return
	for faction: int in [0, 1]:
		actor["faction"] = faction
		information.present(actor, scene.battle.unit_information(59), texture)
		information.show_page(2)
		if not _matches(information, []):
			fail("Transferred loot must not carry a green identity into player/allied ownership")
			return
	actor["faction"] = 2
	actor["dropTemplateId"] = 0
	information.present(actor, scene.battle.unit_information(59), texture)
	information.show_page(2)
	if not _matches(information, []):
		fail("Clearing the current owner's drop marker must clear the green name")
		return
	actor["dropTemplateId"] = 1
	actor["inventory"] = [actor["inventory"][0]]
	information.present(actor, scene.battle.unit_information(59), texture)
	information.show_page(2)
	if not _matches(information, []) or information.body.get_child_count() != 1:
		fail("A missing held drop must not create a phantom green row")
		return
	if scene.battle.snapshot() != before:
		fail("Drop highlighting must not change battle or inventory state")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS drop names: original three, duplicates, zero durability, owner/marker/removal, no tint"
	)
	quit(0)


func _matches(information: Control, expected: Array[String]) -> bool:
	var green: Array[String] = []
	for row: Node in information.body.get_children():
		var labels: Array[Node] = row.find_children("*", "Label", true, false)
		if labels.is_empty():
			continue
		if labels[0].get_theme_color("font_color") == Color("00dd00"):
			green.append(labels[0].text)
		if labels[1].get_theme_color("font_color") != Color.WHITE:
			return false
		for icon: Node in row.find_children("*", "TextureRect", true, false):
			if icon.modulate != Color.WHITE or icon.self_modulate != Color.WHITE:
				return false
	green.sort()
	expected.sort()
	return green == expected


func fail(message: String) -> void:
	push_error(message)
	quit(1)
