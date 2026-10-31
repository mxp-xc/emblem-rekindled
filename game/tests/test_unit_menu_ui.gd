extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	var before_hover: Dictionary = scene.battle.snapshot()
	var map_hover := InputEventMouseMotion.new()
	map_hover.position = scene.map.view.screen_at(Vector2(7.5, 11.5))
	Input.parse_input_event(map_hover)
	await process_frame
	if scene.map.hovered != Vector2i(7, 11) or scene.battle.snapshot() != before_hover:
		fail("Map hover must track its tile without selecting a unit or mutating the battle")
		return
	_tap(scene.map.view.screen_at(Vector2(8.5, 11.5)))
	await process_frame
	if scene.unit_panel.visible or not scene.choosing_destination:
		fail("Single tap must only select movement")
		return
	_tap(scene.map.view.screen_at(Vector2(8.5, 11.5)))
	await process_frame
	await process_frame
	if (
		not scene.unit_panel.visible
		or not scene.unit_panel.get_global_rect().intersects(Rect2(0, 0, 720, 1280))
	):
		fail("Double tap must open an on-screen contextual menu")
		return
	var actor_rect := Rect2(
		scene.map.view.screen_at(Vector2(8, 11)), Vector2.ONE * 24 * scene.map.view.zoom
	)
	if scene.unit_panel.get_global_rect().intersects(actor_rect):
		fail(
			"The contextual action menu must sit beside its unit rather than cover it at screen center"
		)
		return
	if not scene.map.content_rect().grow(0.1).encloses(scene.unit_panel.get_global_rect()):
		fail("The nearby action menu must remain inside the visible map")
		return
	var information: Button = scene.get_node("UnitStatus/Status/Actions/Information")
	var trade: Button = scene.get_node("UnitStatus/Status/Actions/Trade")
	if not trade.has_focus():
		fail("A ready unit menu must prefer an available interaction over status")
		return
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = trade.get_global_rect().get_center()
	var center: Vector2 = scene.map.view.center
	Input.parse_input_event(wheel)
	await process_frame
	var backpack: Button = scene.get_node("UnitStatus/Status/Actions/Inventory")
	if not backpack.has_focus() or backpack.icon == null or trade.icon != null:
		fail("Wheel must move the menu selection and finger down one available row")
		return
	if scene.map.view.center != center or scene.battle.snapshot() != before_hover:
		fail("Menu wheel must not pan or change battle state")
		return
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(20, 20)
	Input.parse_input_event(hover)
	await process_frame
	hover.position = trade.get_global_rect().get_center()
	Input.parse_input_event(hover)
	await process_frame
	if not trade.has_focus() or trade.icon == null or information.icon != null:
		fail("The white finger must follow the hovered row, with exactly one current selection")
		return
	_tap(backpack.get_global_rect().get_center())
	await process_frame
	await process_frame
	if not scene.item_actions.visible or scene.item_actions.page != "operations":
		fail("The action inventory must enter the original operation selection")
		return
	scene._handle_back()
	_tap(information.get_global_rect().get_center())
	await process_frame
	scene.unit_information.show_page(2)
	await process_frame
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	Input.parse_input_event(wheel)
	await process_frame
	if scene.unit_information.page != 1 or scene.map.view.center != center:
		fail("Wheel up in character information must select the previous attribute page only")
		return
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	Input.parse_input_event(wheel)
	await process_frame
	if scene.unit_information.page != 2:
		fail("Wheel down in character information must select the next attribute page")
		return
	# The rebuilt equipment rows finish their deferred container layout after the page event.
	await process_frame
	var snapshot: Dictionary = scene.battle.snapshot()
	var herb: Button = scene.unit_information.body.get_node("Item_60")
	if herb.disabled:
		fail("Every held item must remain inspectable")
		return
	_tap(herb.get_global_rect().get_center())
	await process_frame
	if (
		not scene.unit_information.detail_visible
		or (
			scene.unit_information.detail.get_node("Description").get_meta("source_description")
			!= "回复10点体力"
		)
	):
		fail("Clicking an item must show its original description without equipping it")
		return
	scene._handle_back()
	scene._handle_back()
	_tap(Vector2(30, 1000))
	await process_frame
	if scene.unit_panel.visible or scene.battle.snapshot() != snapshot:
		fail("An outside tap must close the popup without committing an action")
		return
	scene.queue_free()
	await process_frame
	print("PASS unit menu: single/double tap, backpack, item restriction, outside dismissal")
	quit(0)


func _tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = pressed
		Input.parse_input_event(event)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
