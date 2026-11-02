# gdlint: disable=max-file-lines
# Fixed clone queue shares battle focus/entrance timing; world UI extraction is unrelated.
extends Control

signal choice_selected(value: int)
signal music_requested(kind: String)
signal world_entrance_completed
signal world_focus_completed
signal world_action_requested(kind: String)
signal world_node_requested(node_id: int)
signal arrival_queue_completed

const MessagePanel = preload("res://ui/message_panel.gd")
const CommanderScreen = preload("res://features/menus/commander_screen.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
const MapHud = preload("res://features/tactical_map/map_hud.gd")
const MapView = preload("res://features/tactical_map/map_view.gd")
var commander: Control
var dialogue: Control
var current_text_index: int = -1
var choices: VBoxContainer
var background: Texture2D
var world_update: int = -1
var world_revealed: bool = false
var world_circle_phase: int = -1
var world_active: bool = false
var world_ready: bool = false
var world_actor_frame: int = 0
var visible_world_nodes: Array[int] = []
var selected_world_node: int = 0
var data: Dictionary
var map: Control
var selected_commander: int = 9
var selected_policy: int = 0
var selected_route: int = -1
var _directory: String
var _commander_configuration: Dictionary = {}
var _elapsed: float = 0
var _tick_seconds: float
var _confirm: Button
var _route_panel: PanelContainer
var _finger: Texture2D
var _choice_index: int = 0
var _world_actor_frames: Array[Texture2D] = []
var _world_idle_updates: int = 0
var _world_idle_interval: int
var _world_actor_offset: Vector2
var _world_circle: Control
var _world_hud: Control
var _world_layer: Control
var _world_back: Button
var _world_markers: Array[Texture2D] = []
var _world_view: RefCounted = MapView.new()
var _world_rect: Rect2
var _world_focus_target: Vector2
var _world_focus_pending: bool = false
var _world_current_node: int = 0
var _world_next_node: int = -1
var _world_effect_node: int = 0
var _world_wait_updates: int = 21
var _battle_area: Rect2
var _safe_area: Rect2
var _world_touches: Dictionary = {}
var _travel_confirmation: bool = false
var _world_travel_position := Vector2(-1, -1)
var _arrival_queue_updates_remaining: int = 0


func setup(content: Dictionary, tactical_map: Control) -> void:
	data = content
	map = tactical_map
	_directory = data["entry"]["resourceDirectory"]
	_tick_seconds = float(data["battleClips"]["tickMillis"]) / 1000
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world_layer = Control.new()
	_world_layer.name = "WorldMap"
	_world_layer.clip_contents = true
	_world_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_layer.draw.connect(_draw_world)
	add_child(_world_layer)
	_world_layer.hide()
	_world_circle = Control.new()
	_world_circle.name = "WorldCircle"
	_world_circle.size = Vector2(24, 24)
	_world_circle.clip_contents = true
	_world_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_circle.draw.connect(_draw_world_circle)
	_world_layer.add_child(_world_circle)
	_world_circle.hide()
	_world_hud = MapHud.new()
	_world_hud.name = "WorldHud"
	add_child(_world_hud)
	_world_hud.setup(content, data["story"]["world"]["nodes"][0]["name"])
	_world_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices = VBoxContainer.new()
	choices.add_theme_constant_override("separation", 0)
	choices.hide()
	_route_panel = PanelContainer.new()
	_route_panel.add_child(choices)
	add_child(_route_panel)
	_route_panel.hide()
	_finger = load(
		content["entry"]["resourceDirectory"].path_join(
			content["interface"]["textures"]["finger"]["texture"]
		)
	)
	var actor: Dictionary = data["mapAnimations"]["units"]["0"]
	for index: Variant in actor["idleSequence"]:
		_world_actor_frames.append(
			load(
				data["entry"]["resourceDirectory"].path_join(actor["frames"][int(index)]["texture"])
			)
		)
	_world_idle_interval = maxi(1, roundi(float(actor["idleStepSeconds"]) / _tick_seconds))
	_world_actor_offset = Vector2(actor["spriteOffsetX"], actor["spriteOffsetY"])
	for key: String in ["b0", "b1"]:
		_world_markers.append(load(_directory.path_join(data["story"]["images"][key]["texture"])))
	dialogue = MessagePanel.new()
	add_child(dialogue)
	dialogue.setup(content)
	_confirm = Button.new()
	_confirm.name = "Confirm"
	_confirm.icon = load(
		content["entry"]["resourceDirectory"].path_join(
			content["interface"]["textures"]["button_0"]["texture"]
		)
	)
	_confirm.expand_icon = true
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_confirm.pressed.connect(advance)
	add_child(_confirm)
	_confirm.hide()
	_world_back = Button.new()
	_world_back.icon = load(
		content["entry"]["resourceDirectory"].path_join(
			content["interface"]["textures"]["button_1"]["texture"]
		)
	)
	_world_back.expand_icon = true
	_world_back.focus_mode = Control.FOCUS_NONE
	_world_back.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_world_back.pressed.connect(go_back)
	add_child(_world_back)
	_world_back.hide()
	commander = CommanderScreen.new()
	add_child(commander)
	commander.setup(content)
	commander.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	gui_input.connect(_handle_touch)
	resized.connect(_layout)
	_layout()
	hide()


func play(sequence: Array, commander_configuration: Dictionary = {}) -> void:
	_commander_configuration = commander_configuration
	world_active = false
	world_ready = false
	_world_wait_updates = 21
	_world_effect_node = 0
	_world_current_node = 0
	selected_world_node = 0
	visible_world_nodes.clear()
	_world_back.hide()
	choices.hide()
	_route_panel.hide()
	show()
	dialogue.hide()
	for step: Dictionary in sequence:
		await _step(step)
		if step.get("sourceWaitTicksAfter", 0) > 0:
			await get_tree().create_timer(step["sourceWaitTicksAfter"] * _tick_seconds).timeout
	current_text_index = -1
	background = null
	hide()
	queue_redraw()


func choose_commander(configuration: Dictionary) -> Dictionary:
	if not configuration.get("candidates") is Array or configuration["candidates"].is_empty():
		return {"ok": false, "error": "NO_ELIGIBLE_COMMANDER"}
	var was_visible: bool = visible
	show()
	commander.present(configuration)
	var selected: Dictionary = await commander.confirmed
	selected_commander = int(selected["commander"])
	selected_policy = int(selected["policy"])
	commander.hide()
	if not was_visible:
		hide()
	return {"ok": true, "commander": selected_commander, "policy": selected_policy}


# Arrivals are committed domain results, not authored animation instructions.
func play_unit_arrivals(arrivals: Array) -> void:
	if arrivals.is_empty():
		return
	current_text_index = -1
	show()
	dialogue.hide()
	choices.hide()
	_route_panel.hide()
	_confirm.hide()
	for arrival: Dictionary in arrivals:
		var id: int = int(arrival["unit"])
		var origin: Vector2i = arrival["from"]
		var destination: Vector2i = arrival["to"]
		await _focus_battle(origin)
		# Original kind32 sets az=2 at focus arrival, then dequeues at az=15.
		# Its movement proceeds independently for two source updates per cell.
		_elapsed = 0
		_arrival_queue_updates_remaining = 13
		if arrival["revealed"]:
			if origin == destination:
				await _step({"kind": "revealUnits", "unitIds": [id]})
			else:
				await _entrance(
					{
						"unitId": id,
						"from": [origin.x, origin.y],
						"to": [destination.x, destination.y]
					}
				)
		if _arrival_queue_updates_remaining > 0:
			await arrival_queue_completed
	current_text_index = -1
	hide()


func _step(step: Dictionary) -> void:
	match step["kind"]:
		"worldNarration":
			_world_hud.present_place(data["story"]["world"]["nodes"][0]["name"])
			world_update = -1
			world_revealed = false
			world_circle_phase = -1
			background = load(_directory.path_join(data["story"]["world"]["texture"]))
			_configure_world_view()
			music_requested.emit("worldMusic")
			queue_redraw()
			await _speak(step["text"], "", "ally", true)
		"worldMarker":
			_world_wait_updates = 21
			world_update = 0
			_elapsed = 0
			await world_entrance_completed
		"enterBattle":
			background = null
			music_requested.emit("music")
			queue_redraw()
		"focus":
			var position: Variant = (
				_unit_position(int(step["unitId"]))
				if step.has("unitId")
				else Vector2(step["cell"][0], step["cell"][1])
			)
			if position == null:
				return
			var cell := Vector2i(position)
			if step.get("instant", false):
				map.view.focus_cell(cell)
				map.queue_redraw()
			else:
				await _focus_battle(cell)
			var hold: int = int(step.get("sourceWaitTicks", 0)) + int(step.get("holdTicksAfter", 0))
			if hold > 0:
				await get_tree().create_timer(hold * _tick_seconds).timeout
		"dialogue":
			await _speak(step["text"])
		"instruction":
			await _speak(step["text"], "", "narration")
		"objective":
			await _notice(step["text"], data["story"]["battleName"]["text"])
		"battleTitle":
			await _notice(step["text"], "", int(step["sourceDurationUnits"]))
		"missionComplete":
			music_requested.emit("victoryMusic")
			await _notice(step["text"], "", 3000)
		"gameOver":
			music_requested.emit("defeatMusic")
			await _notice(step["text"], "", 2000)
		"unitEntrance":
			await _entrance(step)
		"parallelEntrances":
			await _focus_battle(Vector2i(step["focus"][0], step["focus"][1]))
			if step["units"].is_empty():
				return
			var tween := create_tween().set_parallel(true)
			var arrivals: int = 0
			for entrance: Dictionary in step["units"]:
				var id: int = int(entrance["unitId"])
				var points: Dictionary = _entrance_points(entrance)
				if points.is_empty():
					continue
				arrivals += 1
				map.presentation_revealed_ids.append(id)
				map.presentation_hidden_ids.erase(id)
				var from: Vector2 = points["from"]
				var to: Vector2 = points["to"]
				map.presentation_positions[id] = from
				tween.tween_method(
					func(position: Vector2) -> void:
						map.presentation_positions[id] = position
						map.queue_redraw(),
					from,
					to,
					maxf(_tick_seconds, from.distance_to(to) * 2 * _tick_seconds)
				)
			if arrivals > 0:
				await tween.finished
			else:
				tween.kill()
			if step.get("sourceHoldTicksAfter", 0) > 0:
				await get_tree().create_timer(step["sourceHoldTicksAfter"] * _tick_seconds).timeout
		"revealUnits":
			for value: Variant in step["unitIds"]:
				var id: int = int(value)
				map.presentation_hidden_ids.erase(id)
				if id not in map.presentation_revealed_ids:
					map.presentation_revealed_ids.append(id)
			map.queue_redraw()
		"revealFaction":
			map.presentation_hidden_factions.erase(int(step["faction"]))
			map.queue_redraw()
			await get_tree().create_timer(step.get("sourceWaitTicks", 0) * _tick_seconds).timeout
		"commanderSetup":
			var configuration: Dictionary = await choose_commander(_commander_configuration)
			if not configuration["ok"]:
				selected_commander = -1
				selected_policy = 0
		"tutorial":
			for text: String in data["controls"]["opening"]:
				await _speak({"text": text, "sourceTextIndex": -1}, "操作指引", "narration")
		"routeChoice":
			var options: Array = []
			for route: Dictionary in step["options"]:
				options.append({"id": int(route["routeIndex"]), "label": route["label"]})
			selected_route = await _choose(options)


func _entrance(step: Dictionary) -> void:
	var id: int = int(step["unitId"])
	var points: Dictionary = _entrance_points(step)
	if points.is_empty():
		return
	var from: Vector2 = points["from"]
	var to: Vector2 = points["to"]
	await _focus_battle(Vector2i(from))
	map.presentation_positions[id] = from
	map.presentation_revealed_ids.append(id)
	map.presentation_hidden_ids.erase(id)
	var tween := create_tween()
	tween.tween_method(
		func(position: Vector2) -> void:
			map.presentation_positions[id] = position
			map.queue_redraw(),
		from,
		to,
		maxf(_tick_seconds, from.distance_to(to) * 2 * _tick_seconds)
	)
	await tween.finished


func _entrance_points(step: Dictionary) -> Dictionary:
	var position: Variant = _unit_position(int(step["unitId"]))
	if position == null:
		return {}
	if step.has("offset"):
		var offset := Vector2(step["offset"][0], step["offset"][1])
		return {"from": position + offset, "to": position}
	return {
		"from": Vector2(step["from"][0], step["from"][1]),
		"to": Vector2(step["to"][0], step["to"][1])
	}


func _unit_position(id: int) -> Variant:
	for actor: Dictionary in map.content["units"]:
		if int(actor["id"]) == id:
			return map.presentation_positions.get(id, Vector2(actor["x"], actor["y"]))
	return null


func _focus_battle(cell: Vector2i) -> void:
	while true:
		var current: Vector2 = map.view.center * 24.0
		map.view.focus_cell(cell)
		var target: Vector2 = map.view.center * 24.0
		map.view.center = current / 24.0
		if current.is_equal_approx(target):
			return
		for axis: int in [0, 1]:
			var delta: float = target[axis] - current[axis]
			if not is_zero_approx(delta):
				var distance: float = clampf(floorf(absf(delta) / 2.0), 1.0, 12.0)
				current[axis] = move_toward(current[axis], target[axis], distance)
		map.view.center = current / 24.0
		map.queue_redraw()
		await get_tree().create_timer(_tick_seconds).timeout


func _speak(
	line: Dictionary, heading: String = "", tone: String = "ally", portrait_right: bool = false
) -> void:
	var speaker_id: Variant = line.get("speakerId")
	if background == null and speaker_id != null:
		var position: Variant = _unit_position(int(speaker_id))
		if position != null:
			await _focus_battle(Vector2i(position))
	current_text_index = int(line["sourceTextIndex"])
	var speaker: Dictionary = (
		data["story"]["speakers"].get(str(int(speaker_id)), {}) if speaker_id != null else {}
	)
	var portrait_id: Variant = speaker.get("portraitId", line.get("portraitId"))
	var face: Texture2D
	if portrait_id != null:
		face = load(
			_directory.path_join(
				data["story"]["images"]["portraits_%02d" % int(portrait_id)]["texture"]
			)
		)
	_elapsed = 0
	_layout()
	dialogue.present(
		line["text"],
		face,
		speaker.get("name", heading),
		"enemy" if speaker.get("faction") == 2 else tone,
		portrait_right
	)
	await dialogue.completed
	dialogue.hide()


func _notice(line: Dictionary, heading: String = "", duration_units: int = -1) -> void:
	current_text_index = int(line["sourceTextIndex"])
	_elapsed = 0
	dialogue.present_notice(line["text"], heading, duration_units)
	_confirm.visible = duration_units < 0
	_layout()
	await dialogue.completed
	_confirm.hide()
	dialogue.hide()


func advance() -> void:
	if dialogue.visible:
		dialogue.advance()
	elif choices.visible:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is Button and focused.get_parent() == choices:
			focused.pressed.emit()
	elif world_active and world_ready:
		_activate_world_node()


func go_back() -> void:
	_cancel_world_gesture()
	if commander.visible:
		commander.commit()
	elif dialogue.visible and not dialogue.notice_mode:
		dialogue.advance()
	elif _travel_confirmation:
		choice_selected.emit(0)
	elif world_active and choices.visible:
		choices.hide()
		_route_panel.hide()
		_world_back.hide()


func handle_key(event: InputEventKey) -> bool:
	if commander.visible:
		return commander.handle_key(event)
	if choices.visible and event.pressed and not event.echo and event.keycode in [KEY_UP, KEY_DOWN]:
		handle_wheel(-1 if event.keycode == KEY_UP else 1)
		return true
	if world_active and not dialogue.visible and not choices.visible:
		if not event.pressed or event.echo:
			return false
		if not world_ready:
			return true
		if event.keycode in [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]:
			var direction: int = -1 if event.keycode in [KEY_LEFT, KEY_UP] else 1
			var index: int = visible_world_nodes.find(selected_world_node)
			_focus_world_node(
				visible_world_nodes[posmod(index + direction, visible_world_nodes.size())]
			)
			return true
	if (
		event.pressed
		and not event.echo
		and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_DOWN]
	):
		if choices.visible and event.keycode == KEY_DOWN:
			return false
		if dialogue.visible and dialogue.notice_mode and event.keycode == KEY_DOWN:
			return true
		advance()
		return true
	return false


func handle_wheel(direction: int) -> void:
	if commander.visible:
		commander.handle_wheel(direction)
	elif choices.visible and choices.get_child_count() > 0:
		_choice_index = posmod(_choice_index + direction, choices.get_child_count())
		choices.get_child(_choice_index).grab_focus()


func _handle_touch(event: InputEvent) -> void:
	if world_active and not dialogue.visible:
		_handle_world_pointer(event)
		return
	if (
		(event is InputEventScreenTouch and not event.pressed and not event.canceled)
		or (
			event is InputEventMouseButton
			and not event.pressed
			and not event.canceled
			and event.button_index == MOUSE_BUTTON_LEFT
		)
	):
		if dialogue.visible:
			dialogue.advance()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_cancel_world_gesture()


func _cancel_world_gesture() -> void:
	_world_view.cancel_pointer()
	_world_touches.clear()


func _process(delta: float) -> void:
	if (
		not visible
		or dialogue == null
		or (
			not dialogue.visible
			and not world_active
			and not (world_update >= 0 and world_update < _world_wait_updates)
			and _arrival_queue_updates_remaining == 0
		)
	):
		_elapsed = 0
		return
	_elapsed += delta
	while _elapsed >= _tick_seconds:
		_elapsed -= _tick_seconds
		tick()


func tick() -> void:
	if _arrival_queue_updates_remaining > 0:
		_arrival_queue_updates_remaining -= 1
		if _arrival_queue_updates_remaining == 0:
			arrival_queue_completed.emit()
	if (
		world_active
		and (world_ready or _world_travel_position.x >= 0)
		and not dialogue.visible
		and not choices.visible
	):
		_world_idle_updates += 1
		if _world_idle_updates >= _world_idle_interval:
			_world_idle_updates = 0
			world_actor_frame = (world_actor_frame + 1) % _world_actor_frames.size()
			_world_layer.queue_redraw()
	if dialogue.visible:
		dialogue.tick()
	elif world_update >= 0 and world_update < _world_wait_updates:
		world_update += 1
		world_revealed = true
		if not world_active:
			visible_world_nodes.assign([0])
		world_circle_phase = floori(float(world_update - 1) / 2) if world_update <= 6 else -1
		_world_circle.queue_redraw()
		queue_redraw()
		if world_update == _world_wait_updates:
			world_entrance_completed.emit()
	elif world_active and _world_focus_pending:
		for axis: int in range(2):
			_world_view.center[axis] = move_toward(
				_world_view.center[axis], _world_focus_target[axis], 0.25
			)
		queue_redraw()
		if _world_view.center.is_equal_approx(_world_focus_target):
			_world_focus_pending = false
			world_focus_completed.emit()


func _choose(options: Array) -> int:
	current_text_index = -1
	_choice_index = 0
	for child: Node in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	for option: Dictionary in options:
		var button := Button.new()
		button.name = "Choice_" + str(option["id"])
		button.text = option["label"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.focus_entered.connect(func() -> void: button.icon = _finger)
		button.focus_exited.connect(func() -> void: button.icon = null)
		var id: int = option["id"]
		button.pressed.connect(func() -> void: choice_selected.emit(id))
		choices.add_child(button)
	choices.show()
	_route_panel.show()
	_confirm.show()
	_layout()
	choices.get_child(0).grab_focus()
	var result: int = await choice_selected
	choices.hide()
	_route_panel.hide()
	_confirm.hide()
	return result


func set_battle_area(area: Rect2, safe_area: Rect2 = Rect2()) -> void:
	if _battle_area == area and _safe_area == safe_area:
		return
	_battle_area = area
	_safe_area = safe_area
	_layout()


func _layout() -> void:
	if _confirm != null:
		var area: Rect2 = _safe_area if _safe_area.has_area() else Rect2(Vector2.ZERO, size)
		var battle_area: Rect2 = (
			_battle_area if _battle_area.has_area() else Rect2(Vector2.ZERO, size)
		)
		var controls: Rect2 = area if background != null else battle_area
		dialogue.set_content_area(controls)
		commander.position = battle_area.position
		commander.size = battle_area.size
		var factor: float = minf(controls.size.x / 240.0, controls.size.y / 320.0)
		_world_hud.position = Vector2(area.position.x, area.end.y - 45 * factor)
		_world_hud.size = Vector2(area.size.x, 45 * factor)
		_world_layer.position = area.position
		_world_layer.size = Vector2(area.size.x, area.size.y - 45 * factor)
		if background != null and _world_rect != Rect2(_world_layer.position, _world_layer.size):
			_configure_world_view()
		_confirm.position = Vector2(controls.position.x, controls.end.y - 22 * factor)
		_confirm.add_theme_constant_override("icon_max_width", roundi(10 * factor))
		_world_back.position = area.end - Vector2(24, 22) * factor
		_world_back.add_theme_constant_override("icon_max_width", roundi(10 * factor))
		var style := StyleBoxEmpty.new()
		style.content_margin_top = 14 * factor
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			_confirm.add_theme_stylebox_override(state, style)
			_world_back.add_theme_stylebox_override(state, style)
		_confirm.size = Vector2(24, 22) * factor
		_world_back.size = Vector2(24, 22) * factor
		var frame: StyleBoxTexture = get_theme_stylebox("panel", "PanelContainer").duplicate()
		frame.content_margin_left = 8 * factor
		frame.content_margin_right = 2 * factor
		frame.content_margin_top = 8 * factor
		frame.content_margin_bottom = 8 * factor
		_route_panel.add_theme_stylebox_override("panel", frame)
		for button: Button in choices.get_children():
			button.custom_minimum_size = Vector2(0, 19 * factor)
			button.add_theme_font_size_override("font_size", roundi(12 * factor))
			button.add_theme_constant_override("icon_max_width", roundi(10 * factor))
		if _travel_confirmation:
			_route_panel.size = Vector2(
				minf(220 * factor, area.size.x), (16 + choices.get_child_count() * 19) * factor
			)
			_route_panel.position = area.get_center() - _route_panel.size / 2
		elif world_active:
			_route_panel.size = Vector2(84, 16 + choices.get_child_count() * 19) * factor
			_route_panel.position = area.position + Vector2(0, 14) * factor
		else:
			_route_panel.size = Vector2(118, 92) * factor
			_route_panel.position = controls.get_center() - _route_panel.size / 2
	queue_redraw()


func _draw() -> void:
	_world_layer.visible = background != null
	_world_hud.visible = background != null
	if background == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("101818"))
	_world_layer.queue_redraw()


func _draw_world() -> void:
	_world_circle.hide()
	if background == null:
		return
	var factor: float = _world_view.zoom
	_world_layer.draw_texture_rect(
		background,
		Rect2(
			_world_view.screen_at(Vector2.ZERO) - _world_layer.position,
			background.get_size() * factor
		),
		false
	)
	if world_revealed:
		if world_active:
			for index: int in range(1, visible_world_nodes.size()):
				_world_layer.draw_line(
					_world_node_origin(visible_world_nodes[index - 1]) + Vector2(12, 12) * factor,
					_world_node_origin(visible_world_nodes[index]) + Vector2(12, 12) * factor,
					Color("ffe68c"),
					factor
				)
		for id: int in visible_world_nodes:
			var node: Dictionary = data["story"]["world"]["nodes"][id]
			var center: Vector2 = _world_node_origin(id) + Vector2(12, 12) * factor
			if int(node["markerId"]) < 0:
				_world_layer.draw_circle(center, 3 * factor, Color.CYAN)
				_world_layer.draw_circle(center, 2 * factor, Color("009bff"))
			else:
				var marker: Texture2D = _world_markers[int(node["markerId"])]
				_world_layer.draw_texture_rect(
					marker,
					Rect2(
						(
							center
							+ Vector2(0, 12) * factor
							- marker.get_size() * Vector2(0.5, 1) * factor
						),
						marker.get_size() * factor
					),
					false
				)
		var origin: Vector2 = _world_node_origin(_world_current_node)
		if _world_travel_position.x >= 0:
			origin = _world_view.screen_at(_world_travel_position) - _world_layer.position
		var actor: Texture2D = _world_actor_frames[world_actor_frame if world_active else 0]
		_world_layer.draw_texture_rect(
			actor, Rect2(origin + _world_actor_offset * factor, actor.get_size() * factor), false
		)
		if world_active and world_ready:
			var center: Vector2 = _world_node_origin(selected_world_node) + Vector2(0, 12) * factor
			_world_layer.draw_texture_rect(
				_finger,
				Rect2(center - _finger.get_size() * factor / 2, _finger.get_size() * factor),
				false
			)
		_world_circle.position = _world_node_origin(_world_effect_node)
		_world_circle.scale = Vector2.ONE * factor
		_world_circle.visible = world_circle_phase >= 0


func _draw_world_circle() -> void:
	var center := Vector2(12, 12)
	if world_circle_phase in [0, 1]:
		var radius: float = 5 if world_circle_phase == 0 else 10
		_world_circle.draw_circle(center, radius, Color.CYAN)
		_world_circle.draw_circle(center, radius - 2, Color.YELLOW)
	elif world_circle_phase == 2:
		_world_circle.draw_arc(center, 12, 0, TAU, 64, Color.CYAN, 1)
		_world_circle.draw_arc(center, 11, 0, TAU, 64, Color.CYAN, 1)


func show_world(progress: Dictionary, guidance: bool = false) -> void:
	show()
	world_active = true
	world_ready = false
	world_actor_frame = 0
	_world_idle_updates = 0
	dialogue.hide()
	choices.hide()
	_route_panel.hide()
	_world_back.hide()
	_confirm.hide()
	_cancel_world_gesture()
	world_update = -1
	world_revealed = true
	world_circle_phase = -1
	_world_current_node = int(progress.get("worldLocation", progress["worldNode"]))
	selected_world_node = _world_current_node
	var path: Array = data["story"]["world"]["routes"][int(progress["route"])]
	var step: int = int(progress.get("worldStep", 1))
	visible_world_nodes.assign(path.slice(0, step))
	background = load(_directory.path_join(data["story"]["world"]["texture"]))
	music_requested.emit("worldMusic")
	_world_next_node = int(path[step]) if step < path.size() else -1
	_world_hud.present_place(data["story"]["world"]["nodes"][_world_current_node]["name"])
	_configure_world_view()
	_layout()
	queue_redraw()
	if guidance and _world_next_node >= 0:
		await _speak(
			{"sourceTextIndex": -1, "portraitId": 10, "text": "进度已保留。菜单可记录、读取存档；已亮起的地点是队伍的下一目标。"},
			"",
			"ally",
			true
		)
		await _focus_world_node(_world_next_node)
		visible_world_nodes.append(_world_next_node)
		_world_effect_node = _world_next_node
		_world_wait_updates = 11
		world_update = 0
		_elapsed = 0
		tick()
		await world_entrance_completed
		await _focus_world_node(_world_current_node)
		await get_tree().create_timer(_tick_seconds * 5).timeout
	elif _world_next_node >= 0:
		visible_world_nodes.append(_world_next_node)
	world_ready = true
	_confirm.show()
	if guidance:
		_show_world_menu()
	queue_redraw()


func show_world_notice(text: String) -> void:
	var restore_menu: bool = choices.visible
	choices.hide()
	_route_panel.hide()
	_confirm.hide()
	_world_back.hide()
	await _speak({"sourceTextIndex": -1, "text": text}, "", "narration")
	_confirm.show()
	if restore_menu:
		_show_world_menu()


func confirm_travel(node_id: int) -> bool:
	_travel_confirmation = true
	_world_back.show()
	var place: String = data["story"]["world"]["nodes"][node_id]["name"]
	var selected: int = await _choose([{"id": 1, "label": "前往" + place}, {"id": 0, "label": "返回"}])
	_travel_confirmation = false
	_world_back.hide()
	_confirm.show()
	return selected == 1


func travel_to(node_id: int, enter_battle: bool = true) -> void:
	world_ready = false
	_confirm.hide()
	_world_back.hide()
	_cancel_world_gesture()
	var nodes: Array = data["story"]["world"]["nodes"]
	var from := Vector2(
		nodes[_world_current_node]["position"][0], nodes[_world_current_node]["position"][1]
	)
	var to := Vector2(nodes[node_id]["position"][0], nodes[node_id]["position"][1])
	_world_travel_position = from
	var tween := create_tween()
	tween.tween_method(
		func(point: Vector2) -> void:
			_world_travel_position = point
			_world_layer.queue_redraw(),
		from,
		to,
		maxf(_tick_seconds, from.distance_to(to) * 2 * _tick_seconds)
	)
	await tween.finished
	_world_current_node = node_id
	_world_travel_position = Vector2(-1, -1)
	_world_hud.present_place(nodes[node_id]["name"])
	if enter_battle:
		await _speak(nodes[node_id]["entryNarration"], "", "ally", true)
	else:
		world_ready = true
		_confirm.show()


func leave_world() -> void:
	world_active = false
	world_ready = false
	world_update = -1
	_travel_confirmation = false
	_world_travel_position = Vector2(-1, -1)
	_world_focus_pending = false
	_cancel_world_gesture()
	choices.hide()
	_route_panel.hide()
	_world_back.hide()
	_confirm.hide()
	dialogue.hide()
	background = null
	hide()


func _configure_world_view() -> void:
	_cancel_world_gesture()
	var area: Rect2 = _safe_area if _safe_area.has_area() else Rect2(Vector2.ZERO, size)
	var factor: float = minf(area.size.x / 240.0, area.size.y / 320.0)
	var height: float = area.size.y - 45 * factor
	_world_view.zoom = maxf(factor, height / 275.0)
	_world_view.configure(
		Vector2i(int(data["story"]["world"]["width"]), int(data["story"]["world"]["height"])),
		Vector2(area.size.x, height),
		area.position
	)
	var cell: Array = data["story"]["world"]["nodes"][selected_world_node]["position"]
	_world_view.focus_cell(Vector2i(int(cell[0]), int(cell[1])))
	_world_focus_target = _world_view.center
	_world_rect = Rect2(area.position, Vector2(area.size.x, height))
	if _world_focus_pending:
		_world_focus_pending = false
		world_focus_completed.emit()


func _world_node_origin(id: int) -> Vector2:
	var cell: Array = data["story"]["world"]["nodes"][id]["position"]
	return _world_view.screen_at(Vector2(cell[0], cell[1])) - _world_layer.position


func _focus_world_node(id: int) -> void:
	selected_world_node = id
	_world_hud.present_place(data["story"]["world"]["nodes"][id]["name"])
	var before: Vector2 = _world_view.center
	var cell: Array = data["story"]["world"]["nodes"][id]["position"]
	_world_view.focus_cell(Vector2i(int(cell[0]), int(cell[1])))
	_world_focus_target = _world_view.center
	_world_view.center = before
	if before.is_equal_approx(_world_focus_target):
		return
	_world_focus_pending = true
	await world_focus_completed


func _activate_world_node() -> void:
	_world_view.cancel_pointer()
	if _world_focus_pending:
		return
	if selected_world_node == _world_current_node:
		_show_world_menu()
	else:
		world_node_requested.emit(selected_world_node)


func _show_world_menu() -> void:
	_world_view.cancel_pointer()
	_choice_index = 0
	for child: Node in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	var actions: Dictionary = {
		"inventory": "物品整理", "save": "记录存档", "load": "读取存档", "gold": "换取金币", "title": "回主菜单"
	}
	for kind: String in actions:
		var button := Button.new()
		button.name = "World_" + kind
		button.text = actions[kind]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		for state: String in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.focus_entered.connect(func() -> void: button.icon = _finger)
		button.focus_exited.connect(func() -> void: button.icon = null)
		button.pressed.connect(world_action_requested.emit.bind(kind))
		choices.add_child(button)
	choices.show()
	_route_panel.show()
	_world_back.show()
	_confirm.show()
	_layout()
	choices.get_child(0).grab_focus()


func _select_world_cell(cell: Vector2i) -> void:
	for id: int in visible_world_nodes:
		var position: Array = data["story"]["world"]["nodes"][id]["position"]
		if cell != Vector2i(int(position[0]), int(position[1])):
			continue
		if selected_world_node == id:
			_activate_world_node()
		else:
			_focus_world_node(id)
		return


func _handle_world_pointer(event: InputEvent) -> void:
	if not world_ready:
		return
	if choices.visible:
		if (
			event is InputEventScreenTouch
			or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
		):
			var pointer: int = event.index if event is InputEventScreenTouch else 1000
			if event.pressed and not event.canceled:
				_world_view.begin_pointer(event.position, pointer)
			elif _world_view.pointer_id == pointer:
				_world_view.cancel_pointer()
				if not event.canceled:
					go_back()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.canceled:
			_world_view.cancel_pointer()
		elif event.pressed:
			if Rect2(_world_view.viewport_origin, _world_view.viewport_size).has_point(
				event.position
			):
				_world_view.begin_pointer(event.position, 1000)
		else:
			_select_world_cell(_world_view.end_pointer(event.position, 1000))
	elif event is InputEventMouseMotion:
		_world_view.drag_pointer(event.position, 1000)
	elif event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if not Rect2(_world_view.viewport_origin, _world_view.viewport_size).has_point(
				event.position
			):
				return
			_world_touches[event.index] = event.position
			if _world_touches.size() == 1:
				_world_view.begin_pointer(event.position, event.index)
			else:
				_world_view.cancel_pointer()
		else:
			_world_touches.erase(event.index)
			if event.canceled:
				_world_view.cancel_pointer()
			else:
				_select_world_cell(_world_view.end_pointer(event.position, event.index))
	elif event is InputEventScreenDrag:
		_world_view.drag_pointer(event.position, event.index)
	queue_redraw()


func show_notice(text: String, button_text: String = "确认") -> void:
	show()
	_confirm.tooltip_text = button_text
	await _notice({"sourceTextIndex": -1, "text": text})
	_confirm.tooltip_text = "确认"
	hide()
