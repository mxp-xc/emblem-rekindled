extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._set_menu_visible(true)
	var menu: Control = scene.menu_layer
	if menu.page != "settings" or "查看全图" in _buttons(menu, true):
		fail("Title settings must not expose battlefield overview controls")
		return
	if "字体许可" in _buttons(menu, false):
		fail("Settings must remove the font-license entry while preserving bundled license files")
		return
	scene._set_menu_visible(false)
	scene.resume_battle(scene.battle)
	scene._set_menu_visible(true)
	menu.show_page("settings")
	await process_frame
	await process_frame
	if "查看全图" not in _buttons(menu, true):
		fail("Battle settings must retain their map overview command")
		return
	var zoom: HSlider = menu.find_child("MapZoom", true, false)
	if zoom == null or not zoom.is_visible_in_tree():
		fail("Battle settings must offer a controlled map zoom slider")
		return
	var before: Dictionary = scene.battle.snapshot()
	var area: Rect2 = zoom.get_global_rect()
	var start: Vector2 = area.position + Vector2(area.size.x * 0.25, area.size.y / 2)
	_touch(0, start, true)
	await process_frame
	var initial: float = scene.map.view.zoom
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = start + Vector2(area.size.x * 0.4, 0)
	Input.parse_input_event(drag)
	await process_frame
	_touch(0, drag.position, false)
	await process_frame
	if (
		not is_equal_approx(scene.map.view.zoom, zoom.value)
		or scene.map.view.zoom <= initial
		or scene.battle.snapshot() != before
	):
		fail("Actual touch dragging must adjust settings zoom without changing battle authority")
		return
	var settings_path: String = "user://test_settings_touch_%d.json" % Time.get_ticks_usec()
	scene.store = load("res://persistence/settings_store.gd").new(settings_path)
	var volume: HSlider = menu.find_child("Volume", true, false)
	volume.value = 0.2
	var old_volume: float = volume.value
	area = volume.get_global_rect()
	_touch(0, area.position + Vector2(area.size.x * 0.9, area.size.y / 2), true)
	_touch(0, area.position + Vector2(area.size.x * 0.9, area.size.y / 2), false)
	await process_frame
	if volume.value <= old_volume:
		fail("The audio slider must support the same phone touch input")
		return
	var path: String = "user://test_game_settings_%d.json" % Time.get_ticks_usec()
	scene.battle_store = load("res://persistence/battle_store.gd").new(scene.content, path)
	menu.show_page("main")
	if not scene._save_battle() or not _saved_notice(menu):
		fail("Saving from the battle menu must briefly confirm success")
		return
	menu.show_page("settings")
	if _saved_notice(menu):
		fail("Save success must not follow navigation into settings")
		return
	menu.show_page("main")
	scene._save_battle()
	await create_timer(2.2).timeout
	if _saved_notice(menu):
		fail("Save success must automatically expire while staying on the same menu")
		return
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(settings_path)
	scene.queue_free()
	await process_frame
	print(
		"PASS settings: title context, no license entry, battle overview, short-lived save success"
	)
	quit(0)


func _touch(index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)


func _buttons(menu: Control, visible_only: bool) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in menu.find_children("*", "Button", true, false):
		if not visible_only or child.is_visible_in_tree():
			labels.append(child.text)
	return labels


func _saved_notice(menu: Control) -> bool:
	for child: Node in menu.find_children("*", "Label", true, false):
		if child.text == "进度已保存。" and child.is_visible_in_tree():
			return true
	return false


func fail(message: String) -> void:
	push_error(message)
	quit(1)
