extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
var _record_directory: String = ""
var _draws: int = 0
var _confirmations: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var directory: String = "user://test_map_forecast_visibility_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_absolute(directory) != OK:
		fail("The visibility test must own a newly created record directory")
		return
	_record_directory = directory
	scene.store.path = directory.path_join("settings.json")
	scene.battle_store.path = directory.path_join("battle_save.json")
	scene.title_screen.prologue.hide()
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	var session := Session.new()
	var opened: Dictionary = session.open(
		"res://content/chapter_1/chapter.json", "", {"new": true}, _roll
	)
	for next_battle: String in ["m1", "m2"]:
		if not opened["ok"]:
			fail("The visibility fixture must follow the actual chapter route")
			return
		opened["battle"].win_with_assistance()
		var victory: Dictionary = opened["battle"].complete_victory(0)
		if not victory["ok"]:
			fail("The visibility fixture must complete each legal chapter frontier")
			return
		opened = session.open(
			"res://content/chapter_1/chapter.json",
			next_battle,
			{"progress": victory["progress"]},
			_roll
		)
	if not opened["ok"]:
		fail("The real m2 scene must open before checking its forecast")
		return
	scene._adopt_content(opened["content"], opened["battle"])
	var battle: RefCounted = opened["battle"]
	var initial: Dictionary = battle.snapshot()
	initial["round"] = 3
	for actor: Dictionary in initial["units"]:
		if actor["id"] == 7:
			actor["x"] = 17
			actor["y"] = 9
			actor["inventory"] = [
				{"id": "forecast-visibility:wind", "templateId": 50, "durability": 14}
			]
			actor["equippedInstanceId"] = "forecast-visibility:wind"
		elif actor["id"] == 33:
			actor["x"] = 19
			actor["y"] = 9
		elif actor["id"] == 32:
			actor["x"] = 19
			actor["y"] = 10
	if not battle.restore_snapshot(initial)["ok"]:
		fail("The actual-map visibility fixture must restore a validated snapshot")
		return
	scene.resume_battle(battle)
	scene.selected_unit = 7
	_draws = 0
	var before: Dictionary = battle.snapshot()
	scene._unit_intent("attack", {})
	scene.target_selection.find_child("Weapon_50", true, false).pressed.emit()
	scene._show_cell(Vector2i(19, 9))
	var selection: Control = scene.target_selection
	if selection.page != "map_forecast" or selection.target_id != 33:
		fail("Actual Main must open the wind-magic forecast with its selected primary target")
		return
	var affected: Dictionary = scene.map.affected_cells.duplicate(true)
	if affected.is_empty():
		fail("Actual Main must retain the real affected-cell overlay")
		return
	for dimensions: Vector2i in [Vector2i(720, 1280), Vector2i(540, 960), Vector2i(1280, 720)]:
		root.size = dimensions
		# Container sorting and wrapped Label minimum sizes settle across deferred frames.
		for frame: int in range(8):
			await process_frame
		if not _check_visible_layout(selection):
			return
		if selection.target_id != 33 or scene.map.affected_cells != affected:
			fail("Forecast resizing must retain its primary target and affected cells")
			return
		if battle.snapshot() != before or _draws != 0:
			fail("Forecast layout must not mutate battle state or draw combat randomness")
			return
	selection.go_back()
	if selection.page != "targets" or selection.target_id != 33 or battle.snapshot() != before:
		fail("Back must retain the primary target without changing battle state")
		return
	scene._show_cell(Vector2i(19, 9))
	selection.intent.connect(
		func(kind: String, _details: Dictionary) -> void:
			if kind == "map_attack_confirmed":
				_confirmations += 1
	)
	var confirm: Button = selection.find_child("Confirm", true, false)
	confirm.pressed.emit()
	confirm.pressed.emit()
	var deadline: int = Time.get_ticks_msec() + 5000
	while scene.busy and Time.get_ticks_msec() < deadline:
		if scene.action_feedback.current_step.get("kind") == "tutorial":
			scene.action_feedback.go_back()
		await process_frame
	if (
		scene.busy
		or _confirmations != 1
		or battle.unit(7)["inventory"][0]["durability"] != 13
		or battle.unit(7)["action"] != 2
	):
		fail("Forecast confirmation must retain the existing one-cast behavior")
		return
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	if not _cleanup_records():
		quit(1)
		return
	print(
		"PASS actual Main map forecast visibility: original icons, hint, scroll, Back and one cast"
	)
	quit(0)


func _check_visible_layout(selection: Control) -> bool:
	var forecast: Control = selection.find_child("MapAttackForecast", true, false)
	var panel: PanelContainer = forecast.find_child("MapForecastPanel", true, false)
	var scroll: ScrollContainer = forecast.find_child("MapForecastTargets", true, false)
	var hint: Label = forecast._hint
	var bounds: Rect2 = selection.get_viewport_rect().grow(0.1)
	print(
		(
			"Forecast layout: bounds=%s panel=%s minimum=%s body=%s scroll=%s hint=%s"
			% [
				bounds,
				panel.get_global_rect(),
				panel.get_combined_minimum_size(),
				forecast._body.get_global_rect(),
				scroll.get_global_rect(),
				hint.get_global_rect()
			]
		)
	)
	var panel_visible: bool = (
		bounds.encloses(panel.get_global_rect())
		and bounds.encloses(hint.get_global_rect())
		and panel.get_global_rect().grow(0.1).encloses(hint.get_global_rect())
		and scroll.get_global_rect().end.y <= hint.get_global_rect().position.y + 0.1
	)
	var icons_visible: bool = true
	var factor: float = PixelTheme.portrait_area(selection.size).size.x / 240.0
	for name: String in ["Confirm", "Back"]:
		var button: Button = selection.find_child(name, true, false)
		var image: Image = button.icon.get_image()
		if image.get_size() != Vector2i(10, 8) or not image.get_used_rect().has_area():
			fail("Forecast controls must retain the complete original PNG icon resources")
			return false
		var states: Array[String] = [
			"normal", "hover", "pressed", "hover_pressed", "disabled", "focus"
		]
		var largest_margins := Vector4.ZERO
		for state: String in states:
			var style: StyleBox = button.get_theme_stylebox(state)
			largest_margins.x = maxf(largest_margins.x, style.get_margin(SIDE_LEFT))
			largest_margins.y = maxf(largest_margins.y, style.get_margin(SIDE_TOP))
			largest_margins.z = maxf(largest_margins.z, style.get_margin(SIDE_RIGHT))
			largest_margins.w = maxf(largest_margins.w, style.get_margin(SIDE_BOTTOM))
		for state: String in states:
			var style: StyleBox = button.get_theme_stylebox(state)
			var margins := Vector4(
				style.get_margin(SIDE_LEFT),
				style.get_margin(SIDE_TOP),
				style.get_margin(SIDE_RIGHT),
				style.get_margin(SIDE_BOTTOM)
			)
			if button.get_theme_constant("align_to_largest_stylebox") != 0:
				margins = largest_margins
			var content := Rect2(
				button.global_position + Vector2(margins.x, margins.y),
				button.size - Vector2(margins.x + margins.z, margins.y + margins.w)
			)
			# Button expands proportionally inside its stylebox content, then applies icon_max_width.
			var icon_scale: float = minf(content.size.x / 10.0, content.size.y / 8.0)
			icon_scale = minf(icon_scale, button.get_theme_constant("icon_max_width") / 10.0)
			var drawn_size: Vector2 = (Vector2(10, 8) * icon_scale).round()
			var offset := Vector2(0, (content.size.y - drawn_size.y) / 2.0)
			if button.icon_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
				offset.x = content.size.x - drawn_size.x
			var drawn := Rect2((content.position + offset).floor(), drawn_size)
			var used: Rect2i = image.get_used_rect()
			var visible_pixels := Rect2(
				drawn.position + Vector2(used.position) * drawn_size / Vector2(10, 8),
				Vector2(used.size) * drawn_size / Vector2(10, 8)
			)
			print(
				(
					"Forecast icon: %s %s button=%s content=%s used=%s"
					% [name, state, button.get_global_rect(), content, visible_pixels]
				)
			)
			if (
				not button.is_visible_in_tree()
				or drawn_size.x < floorf(10 * factor)
				or drawn_size.y < floorf(8 * factor)
				or not bounds.encloses(visible_pixels)
				or not content.grow(1).encloses(visible_pixels)
				or panel.get_global_rect().intersects(visible_pixels)
			):
				icons_visible = false
	if not panel_visible or not icons_visible:
		fail(
			"The stable Main forecast must show its hint and complete icons outside the scroll panel"
		)
		return false
	return true


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func fail(message: String) -> void:
	push_error(message)
	Engine.time_scale = 1
	_cleanup_records()
	quit(1)


func _cleanup_records() -> bool:
	if _record_directory.is_empty():
		return true
	for name: String in DirAccess.get_files_at(_record_directory):
		if DirAccess.remove_absolute(_record_directory.path_join(name)) != OK:
			push_error("Cannot remove an owned forecast visibility test record: " + name)
			return false
	if DirAccess.remove_absolute(_record_directory) != OK:
		push_error("Cannot remove the owned forecast visibility test record directory")
		return false
	_record_directory = ""
	return true
