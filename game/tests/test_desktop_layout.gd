extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.resume_battle(scene.battle)
	scene._show_cell(Vector2i(8, 11))
	scene._show_information()
	await process_frame
	await process_frame
	var info: Control = scene.unit_information
	if info.body.get_child_count() != 7:
		fail("Desktop information must retain all seven original attributes")
		return
	for row: Control in info.body.get_children():
		if not info.get_global_rect().encloses(row.get_global_rect()):
			fail("Every attribute and its value must remain on screen in a desktop window")
			return
	info.show_page(2)
	info.show_item(scene.battle.unit(0)["inventory"][0])
	await process_frame
	await process_frame
	if not info.get_global_rect().encloses(info.detail.get_global_rect()):
		fail("Desktop item details must fit within the bottom of the portrait content area")
		return
	info.hide()
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("commander")
	await process_frame
	var commander: Control = scene.menu_layer._commander
	for value: Button in commander._values:
		if not commander.get_global_rect().encloses(value.get_global_rect()):
			fail("All three commander selectors must fit in a desktop window")
			return
	if scene.map_hud.size.y > scene.size.y * 0.15:
		fail("The map HUD must not grow with the desktop window width")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS desktop layout: visible attributes, item details, commander selectors, bounded map HUD"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
