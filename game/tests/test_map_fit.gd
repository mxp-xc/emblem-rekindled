extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._set_menu_visible(true)
	if find_fit(scene.menu_layer) != null:
		fail("Title settings must not expose map fitting")
		return
	scene.resume_battle(scene.battle)
	scene._show_cell(Vector2i(8, 11))
	var before: Dictionary = scene.battle.snapshot()
	var selected: int = scene.selected_unit
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	var button: Button = find_fit(scene.menu_layer)
	if button == null:
		fail("Battle map settings must offer adaptive fitting beside map zoom")
		return
	button.pressed.emit()
	if scene.menu_layer.visible:
		fail("Fitting must return to the battlefield to show its result")
		return
	for viewport: Vector2i in [
		Vector2i(720, 1280),
		Vector2i(1280, 720),
		Vector2i(720, 800),
		Vector2i(800, 720),
		Vector2i(720, 1280)
	]:
		root.size = viewport
		await process_frame
		var view: RefCounted = scene.map.view
		var axis: int = 0 if viewport.x < viewport.y else 1
		var rendered: float = view.grid_size[axis] * 24.0 * view.zoom
		if not is_equal_approx(rendered, view.viewport_size[axis]):
			fail(
				"Adaptive fitting must fill portrait width / landscape available height after rotation"
			)
			return
		if not is_equal_approx(view.screen_at(Vector2.ZERO)[axis], view.viewport_origin[axis]):
			fail("Fitted map must have no black borders along its fitted axis")
			return
		view.pan_by(Vector2(100000, 100000))
		var first: Vector2 = view.center
		view.pan_by(Vector2(-200000, -200000))
		var map_size: Vector2 = Vector2(view.grid_size) * 24.0 * view.zoom
		if (
			(map_size.x > view.viewport_size.x + 1 or map_size.y > view.viewport_size.y + 1)
			and view.center == first
		):
			fail("The overflowing map direction must remain pannable")
			return
	if scene.selected_unit != selected or scene.battle.snapshot() != before:
		fail("Fitting and rotation must not change selected units or authoritative battle state")
		return
	scene.map.set_zoom(4)
	root.size = Vector2i(1280, 720)
	await process_frame
	if not is_equal_approx(scene.map.view.zoom, 4):
		fail("Manual zoom must leave adaptive mode and remain independently adjustable")
		return
	scene.map.show_overview()
	if not is_equal_approx(scene.map.view.zoom, scene.map.view.minimum_zoom()):
		fail("Overview must retain its existing full-map behavior")
		return
	scene.queue_free()
	await process_frame
	print("PASS adaptive map: real menu, portrait/landscape fit, rotation, pan and manual override")
	quit(0)


func find_fit(menu: Control) -> Button:
	for button: Node in menu.find_children("*", "Button", true, false):
		if button.text == "自适应缩放" and button.is_visible_in_tree():
			return button
	return null


func fail(message: String) -> void:
	push_error(message)
	quit(1)
