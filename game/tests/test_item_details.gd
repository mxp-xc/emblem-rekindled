extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var details: Control = load("res://features/tactical_map/item_details.gd").new()
	details.theme = load("res://ui/pixel_theme.gd").new().create(
		content["interface"], content["entry"]["interface"].get_base_dir()
	)
	root.add_child(details)
	details.setup(content)
	details.size = Vector2(720, 135)
	details.present({"id": "herb", "templateId": 60, "durability": 2})
	if details.get_node("Description").text != "耐久3\n回复10点体力":
		fail(
			"The source detail strip shows default durability; remaining charges belong to the list"
		)
		return
	details.cycle()
	if not details.description_mode:
		fail(
			"A consumable must retain its original durability/description without invented attack stats"
		)
		return
	details.present({"id": "staff", "templateId": 53, "durability": 1})
	var first: String = details.get_node("Description").text
	details.cycle()
	if (
		not first.begins_with("耐久23\n")
		or details.get_node("Description").text == first
		or not details.description_mode
	):
		fail(
			(
				"A long staff description must page inside the source footer: %s -> %s, size %s"
				% [first, details.get_node("Description").text, details.size]
			)
		)
		return
	if details.get_node("Description").get_meta("source_description") != "给予邻接的同伴自身魔力+10的体力回复":
		fail("Paging must preserve the complete source description")
		return
	# All 22 empty descriptions were observed through the original detail UI.
	for template: int in [
		1, 2, 4, 13, 15, 17, 21, 22, 23, 29, 30, 31, 32, 33, 34, 40, 41, 42, 43, 44, 45, 52
	]:
		details.present({"id": "weapon", "templateId": template, "durability": 1}, {}, true)
		if details.description_mode:
			fail("A weapon without source description must open its numeric page: " + str(template))
			return
		details.cycle()
		if details.description_mode:
			fail("Empty descriptions must not create a blank second page: " + str(template))
			return
	details.queue_free()
	await process_frame
	print("PASS item details: default durability, original description, consumable fields")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
