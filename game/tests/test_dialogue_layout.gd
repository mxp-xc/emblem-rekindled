extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var speech: Dictionary
	for candidate: Dictionary in scene.content["story"]["sequences"]["opening"]:
		if candidate.get("text", {}).get("sourceTextIndex") == 481:
			speech = candidate
	scene.story_player.play([speech])
	for overview: bool in [false, true]:
		for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(2048, 1152), Vector2i(540, 960)]:
			root.size = dimensions
			await process_frame
			await process_frame
			if overview:
				scene.map.show_overview()
				await process_frame
			var view: RefCounted = scene.map.view
			var rendered := Rect2(
				view.screen_at(Vector2.ZERO), Vector2(view.grid_size) * 24 * view.zoom
			)
			rendered = rendered.intersection(Rect2(view.viewport_origin, view.viewport_size))
			var frame := Rect2(rendered.position.x, 0, rendered.size.x, scene.size.y)
			var dialogue: Control = scene.story_player.dialogue
			if (
				not is_equal_approx(dialogue.panel_rect.position.x, frame.position.x)
				or not is_equal_approx(dialogue.panel_rect.size.x, frame.size.x)
				or not is_equal_approx(dialogue.panel_rect.end.y, frame.end.y)
			):
				fail("Dialogue must fit the rendered map width, preserving permitted side gutters")
				return
			if not frame.encloses(dialogue.portrait.get_global_rect()):
				fail("The speaker portrait must stay inside the map rather than the side gutter")
				return
			if not is_equal_approx(
				scene.story_player.get_node("Confirm").position.x, frame.position.x
			):
				fail("Dialogue confirmation must use the same map edge")
				return
			for overlay: Control in [
				scene.unit_information,
				scene.item_actions,
				scene.exchange_screen,
				scene.target_selection,
				scene.battle_view
			]:
				if not frame.grow(0.1).encloses(overlay.get_global_rect()):
					fail("Every tactical overlay must remain inside the rendered map frame")
					return
			scene._show_cell(Vector2i(8, 11))
			scene._show_information()
			await process_frame
			for row: Control in scene.unit_information.body.get_children():
				if not frame.grow(0.1).encloses(row.get_global_rect()):
					fail("Unit information values must remain inside the map frame")
					return
			scene.unit_information.hide()
			scene._set_menu_visible(true)
			if not frame.grow(0.1).encloses(scene.menu_layer.panel.get_global_rect()):
				fail("The system menu must remain inside the map frame")
				return
			scene.menu_layer.show_page("commander")
			var commander: Control = scene.menu_layer._commander
			for value: Button in commander._values:
				if not frame.grow(0.1).encloses(value.get_global_rect()):
					fail("Commander controls must remain inside the map frame")
					return
			scene.menu_layer.hide()
	var inset := Rect2(40, 30, 240, 500)
	scene.story_player.set_battle_area(inset)
	await process_frame
	if not inset.encloses(scene.story_player.get_node("Confirm").get_global_rect()):
		fail("Dialogue confirmation must respect the bottom system safe inset as well as map width")
		return
	scene.story_player.advance()
	await create_timer(1.4).timeout
	scene.story_player.play([{"kind": "focus", "cell": [9, 22]}])
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 5000
	while scene.story_player.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	if scene.story_player.visible:
		fail("A resized story camera must settle and release the sequence")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS dialogue layout: map-contained dialogue/portraits/menus, gutters, overview and resize"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
