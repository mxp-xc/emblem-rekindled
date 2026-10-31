extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	scene._show_unit_menu(Vector2i(8, 11))
	var menu: Control = scene.unit_panel
	for scenario: Array in [
		[["attack", "heal", "trade", "inventory", "wait"], "Attack"],
		[["heal", "trade", "inventory", "wait"], "Heal"],
		[["trade", "inventory", "wait"], "Trade"],
		[["inventory", "wait"], "Inventory"],
		[[], "Information"]
	]:
		menu.hide()
		menu.present(scenario[0])
		menu.show()
		if root.gui_get_focus_owner().name != scenario[1]:
			fail("Action menu must prefer the best available interaction")
			return
	scene._show_unit_menu(Vector2i(8, 11))
	scene._unit_intent("inventory", {})
	scene.item_actions.find_child("Discard", true, false).pressed.emit()
	var before: Dictionary = scene.battle.snapshot()
	var center: Vector2 = scene.map.view.center
	if root.gui_get_focus_owner().name != "Item_9":
		fail("Fixture must start at the first held item")
		return
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	if root.gui_get_focus_owner().name != "Item_60" or scene.item_actions.page != "items":
		fail("Wheel down must select the next item without activating or discarding it")
		return
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	if root.gui_get_focus_owner().name != "Item_9":
		fail("Wheel up must return to the previous item")
		return
	if scene.battle.snapshot() != before or scene.map.view.center != center:
		fail("Item-list wheel must not change inventory, actions or the underlying camera")
		return
	scene.item_actions.hide()
	scene.unit_panel.hide()
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	var first: Control = root.gui_get_focus_owner()
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	if root.gui_get_focus_owner() == first or scene.map.view.center != center:
		fail("Settings wheel must select a different enabled command without panning the map")
		return
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	if root.gui_get_focus_owner().text != "辅助功能":
		fail("Settings wheel must leave nested map controls and reach assistance")
		return
	scene.menu_layer.show_page("assistance")
	scene.menu_layer.go_back()
	if root.gui_get_focus_owner() == first:
		fail("Returning to settings must preserve its prior selected command")
		return
	var slider: Control = scene.menu_layer.find_child("MapZoom", true, false)
	slider.grab_focus()
	scene.menu_layer.show_page("assistance")
	scene.menu_layer.go_back()
	if root.gui_get_focus_owner() != slider:
		fail("Returning to settings must also restore slider focus")
		return
	scene.menu_layer.hide()
	var slots: Array[Dictionary] = [
		{"status": "empty"}, {"status": "empty"}, {"status": "empty"}, {"status": "empty"}
	]
	scene.save_slots.present("load", slots)
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	if scene.save_slots.slot != 1 or scene.map.view.center != center:
		fail("Slot selector wheel must change slots without loading, saving or panning")
		return
	scene.queue_free()
	await process_frame
	print("PASS menu wheel: item selection, context priority, settings focus and slot selection")
	quit(0)


func wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = Vector2(360, 500)
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
