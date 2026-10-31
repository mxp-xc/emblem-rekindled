extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.resume_battle(scene.battle)
	await process_frame
	var hud: Control = scene.map_hud
	if hud.get_global_rect().end.y != 1280 or hud.actor["id"] != 0:
		fail("The original map status strip must sit at the bottom and show the initial hero")
		return
	if (
		not scene.menu_button.text.is_empty()
		or scene.menu_button.icon == null
		or scene.menu_button.position.x > 10
	):
		fail("The menu entry must use the original softkey icon at bottom left")
		return
	scene._show_cell(Vector2i(8, 11))
	scene._show_cell(Vector2i(8, 15))
	await create_timer(0.6).timeout
	if hud.actor.get("id") != 0 or hud.actor["hp"] != scene.battle.unit(0)["hp"]:
		fail("Movement and the resulting action menu must retain the selected unit HUD")
		return
	scene._cancel_selection()
	scene._cancel_selection()
	var empty: Vector2i = Vector2i(-1, -1)
	for y: int in range(25):
		for x: int in range(20):
			if (
				scene.content["map"]["terrain"][y][x] == 3
				and scene._unit_at_cell(Vector2i(x, y)) < 0
			):
				empty = Vector2i(x, y)
				break
		if empty.x >= 0:
			break
	if empty.x < 0:
		fail("A real unoccupied defensive terrain cell must be available")
		return
	scene._show_cell(empty)
	if not hud.actor.is_empty() or hud.terrain_values != {"defense": 1, "avoid": 20}:
		fail("An empty terrain cell must show the original defense/evasion bonuses")
		return
	scene._set_menu_visible(true)
	if hud.terrain_values != {"defense": 1, "avoid": 20}:
		fail("Opening the system menu must preserve the current map status")
		return
	scene._set_menu_visible(false)
	scene.map.view.focus_cell(Vector2i(8, 24))
	scene.map.view.pan_by(Vector2(0, -10000))
	var south: Vector2 = scene.map.view.screen_at(Vector2(8.5, 24.5))
	if south.y >= hud.position.y:
		fail("The southern escape row must remain above the HUD at the camera limit")
		return
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = south
		touch.pressed = pressed
		Input.parse_input_event(touch)
	await process_frame
	if scene.map.selected != Vector2i(8, 24):
		fail("The southern escape row must remain selectable through actual touch input")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS map HUD: original bottom layout, icon, unit HP/level, terrain bonuses, menu preservation"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
