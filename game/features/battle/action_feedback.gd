extends Control

signal completed

const Rewards = preload("res://features/battle/reward_timeline.gd")
const Healing = preload("res://features/battle/healing_timeline.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
const FONT = preload("res://ui/fonts/NotoSansCJKsc-Regular.woff2")
const GrowthSummary = preload("res://features/battle/growth_summary.gd")
var playing: bool = false
var current_step: Dictionary = {}
var model: RefCounted
var summary: Control
var _content: Dictionary
var _map: Control
var _hud: Control
var _actors: Array
var _queue: Array[Dictionary] = []
var _textures: Dictionary = {}
var _elapsed: float = 0
var _tick_seconds: float
var _combat: bool
var _read_tutorial: bool = false
var _tutorial_lines: PackedStringArray
var _tutorial_row: int = 0
var _tutorial_scroll: int = 0
var _tutorial_clip: Control
var _tutorial_text: Label
var _content_area: Rect2


func setup(content: Dictionary, tactical_map: Control, hud: Control) -> void:
	_content = content
	_map = tactical_map
	_hud = hud
	_tick_seconds = float(content["battleClips"]["tickMillis"]) / 1000
	var directory: String = content["entry"]["resourceDirectory"]
	for key: String in content["interface"]["textures"]:
		_textures[key] = load(directory.path_join(content["interface"]["textures"][key]["texture"]))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tutorial_clip = Control.new()
	_tutorial_clip.clip_contents = true
	_tutorial_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tutorial_clip)
	_tutorial_text = Label.new()
	_tutorial_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_text.add_theme_font_override("font", FONT)
	_tutorial_clip.add_child(_tutorial_text)
	summary = GrowthSummary.new()
	summary.name = "GrowthSummary"
	add_child(summary)
	summary.confirmed.connect(_start_next)
	gui_input.connect(_handle_touch)
	resized.connect(queue_redraw)
	set_process(false)
	hide()


func play(result: Dictionary, actors: Array, tutorial_seen: bool, player_phase: bool) -> bool:
	_actors = actors.duplicate(true)
	_queue = Rewards.sequence(result, actors, _content["interface"], tutorial_seen, player_phase)
	_combat = result.get("kind") == "combat"
	_read_tutorial = false
	if result.get("kind") == "summon_notice":
		_queue.push_front(
			{"kind": "message", "text": "召唤", "durationUnits": 1200, "unit": result["actor"]}
		)
	elif result.get("kind") == "staff_buff":
		_queue.push_front(
			{
				"kind": "message",
				"text": _actor(int(result["target"]))["name"],
				"secondLine": "能力提升",  # Original text83; message second lines are yellow.
				"durationUnits": 1200,
				"unit": result["target"]
			}
		)
	elif result.get("consumed") == false:
		_queue.push_front(
			{
				"kind": "message",
				"text": "没有生命损失，无法使用",
				"durationUnits": 1200,
				"unit": result["actor"]
			}
		)
	elif result.get("kind") == "heal" or result.get("healed", 0) > 0:
		_queue.push_front(
			{
				"kind": "healing",
				"unit": result.get("target", result["actor"]),
				"before": result["hpBefore"],
				"after": result["hpAfter"]
			}
		)
	if _queue.is_empty():
		return false
	playing = true
	_elapsed = 0
	if _combat:
		_hud.hide()
	show()
	_start_next()
	set_process(true)
	await completed
	_hud.show()
	return _read_tutorial


func advance() -> void:
	if not playing:
		return
	if current_step.get("kind") == "summary":
		return
	if current_step.get("kind") == "tutorial":
		_tutorial_scroll = maxi(0, _tutorial_scroll - 7)
		queue_redraw()
		return
	model.advance()
	if current_step["kind"] == "healing":
		_refresh_healed_hp()
	if model.finished:
		_start_next()
	queue_redraw()


func go_back() -> void:
	if current_step.get("kind") == "summary":
		summary.confirm()
		return
	if current_step.get("kind") != "tutorial" or _tutorial_scroll > 0:
		return
	_tutorial_row += 1
	if _tutorial_row >= _tutorial_lines.size() - 1:
		_read_tutorial = true
		_start_next()
	else:
		_tutorial_scroll = 19
	queue_redraw()


func handle_key(event: InputEventKey) -> bool:
	if current_step.get("kind") == "summary":
		return summary.handle_key(event)
	if (
		(event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_down"))
		and not event.is_echo()
	):
		go_back()
		return true
	return false


func handle_wheel(direction: int) -> void:
	if current_step.get("kind") == "summary":
		summary.handle_wheel(direction)


func _process(delta: float) -> void:
	_elapsed += delta
	while _elapsed >= _tick_seconds and playing:
		_elapsed -= _tick_seconds
		advance()
	queue_redraw()


func _start_next() -> void:
	_tutorial_clip.hide()
	summary.hide()
	if _queue.is_empty():
		current_step = {}
		playing = false
		set_process(false)
		hide()
		completed.emit()
		return
	current_step = _queue.pop_front()
	_hud.visible = not (_combat or current_step["kind"] == "tutorial")
	if current_step["kind"] == "summary":
		model = null
		summary.present(current_step["rows"])
		queue_redraw()
		return
	var actor: Dictionary = _actor(int(current_step["unit"]))
	_map.view.focus_cell(Vector2i(actor["x"], actor["y"]))
	_map.queue_redraw()
	match current_step["kind"]:
		"healing":
			model = Healing.new(current_step["before"], current_step["after"])
			_refresh_healed_hp()
		"tutorial":
			_tutorial_row = 0
			_tutorial_scroll = 0
			_tutorial_lines = []
			for tutorial: Dictionary in _content["story"]["tutorials"]:
				if tutorial["id"] == 6:
					_tutorial_lines.append_array(PixelTheme.wrap_text(tutorial["text"], 232.0, 12))
			_tutorial_text.text = "\n".join(_tutorial_lines)
			_tutorial_clip.show()
		_:
			model = Rewards.new(current_step)
	queue_redraw()


func _actor(id: int) -> Dictionary:
	for actor: Dictionary in _actors:
		if actor["id"] == id:
			return actor
	return {}


func _refresh_healed_hp() -> void:
	var actor: Dictionary = _actor(int(current_step["unit"]))
	actor["hp"] = model.hp
	_map.set_units(_actors)
	_hud.present(Vector2i(actor["x"], actor["y"]), actor)


func _handle_touch(event: InputEvent) -> void:
	if current_step.get("kind") == "summary":
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
		go_back()


func set_content_area(area: Rect2) -> void:
	summary.set_content_area(area)
	if _content_area != area:
		_content_area = area
		queue_redraw()


func _draw() -> void:
	if current_step.is_empty() or current_step.get("kind") == "summary":
		return
	var bounds: Rect2 = _content_area if _content_area.has_area() else Rect2(Vector2.ZERO, size)
	var area: Rect2 = PixelTheme.portrait_area(bounds.size)
	area.position += bounds.position
	var factor: float = area.size.x / 240.0
	var height: float = (bounds.size.y if _combat else _map.view.viewport_size.y) / factor
	var kind: String = current_step["kind"]
	if kind == "healing":
		_draw_healing()
		return
	var panel := Rect2(0, 0, 240, 28)
	match kind:
		"message":
			if current_step.has("secondLine") or current_step.has("templateId"):
				panel.size.y = 48
			if current_step.has("warehouseNotice"):
				panel.size.y = 67
		"tutorial":
			panel = Rect2(0, bounds.size.y / factor - 48, 240, 48)
	panel.position.y = (height - panel.size.y) / 2 if kind != "tutorial" else panel.position.y
	var origin: Vector2 = area.position + panel.position * factor
	_draw_window(Rect2(origin, panel.size * factor), factor, kind == "growth", kind == "message")
	match kind:
		"message":
			_draw_message(origin, panel.size, factor)
		"tutorial":
			_tutorial_clip.position = origin + Vector2(0, 5) * factor
			_tutorial_clip.size = Vector2(240, 38) * factor
			_tutorial_text.position = Vector2(4, -_tutorial_row * 19 + _tutorial_scroll) * factor
			var font_size: int = roundi(12 * factor)
			_tutorial_text.add_theme_font_size_override("font_size", font_size)
			_tutorial_text.add_theme_constant_override(
				"line_spacing", roundi(19 * factor - FONT.get_height(font_size))
			)


func _draw_window(rect: Rect2, factor: float, corners: bool, gradient: bool) -> void:
	draw_rect(rect, Color("214882") if gradient else Color("1c345f"))
	if gradient:
		var rows: int = mini(12, floori(rect.size.y / factor / 4))
		for row: int in range(rows):
			draw_rect(
				Rect2(rect.position + Vector2(0, 5 + row) * factor, Vector2(rect.size.x, factor)),
				Color("022355").lerp(Color("214882"), float(row) / rows)
			)
	var frame: Texture2D = _textures["window_frame"]
	for bottom: bool in [false, true]:
		var y: float = rect.end.y - 5 * factor if bottom else rect.position.y
		draw_texture_rect_region(
			frame,
			Rect2(rect.position.x, y, rect.size.x, 5 * factor),
			Rect2(5, 27 if bottom else 0, 22, 5)
		)
	if corners:
		for index: int in range(4):
			var texture: Texture2D = _textures["corner_" + str(index)]
			var x: float = (
				rect.position.x if index % 2 == 0 else rect.end.x - texture.get_width() * factor
			)
			var y: float = (
				rect.position.y - texture.get_height() * factor if index < 2 else rect.end.y
			)
			draw_texture_rect(texture, Rect2(Vector2(x, y), texture.get_size() * factor), false)


func _draw_healing() -> void:
	if model.circle_phase < 0:
		return
	var actor: Dictionary = _actor(int(current_step["unit"]))
	var center: Vector2 = _map.view.screen_at(Vector2(actor["x"] + 0.5, actor["y"] + 0.5))
	var zoom: float = _map.view.zoom
	if model.circle_phase < 2:
		var radius: float = 5 if model.circle_phase == 0 else 10
		draw_circle(center, radius * zoom, Color.CYAN)
		draw_circle(center, (radius - 2) * zoom, Color.WHITE)
	else:
		draw_arc(center, 12 * zoom, 0, TAU, 64, Color.CYAN, zoom)
		draw_arc(center, 11 * zoom, 0, TAU, 64, Color.CYAN, zoom)


func _draw_message(origin: Vector2, dimensions: Vector2, factor: float) -> void:
	var baseline: float = 19
	if current_step.get("noticeIcon") != null:
		var icon: Texture2D = _textures[current_step["noticeIcon"]]
		var text_width: float = (
			FONT.get_string_size(current_step["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		)
		_icon(
			current_step["noticeIcon"],
			(
				origin
				+ (
					Vector2(
						(240 - text_width) / 2 - icon.get_width() - 2, (28 - icon.get_height()) / 2
					)
					* factor
				)
			),
			factor
		)
	_text(
		current_step["text"],
		origin + Vector2(dimensions.x / 2, baseline) * factor,
		factor,
		Color.WHITE,
		true
	)
	if current_step.has("secondLine"):
		_text(
			current_step["secondLine"],
			origin + Vector2(dimensions.x / 2, 38) * factor,
			factor,
			Color.YELLOW,
			true
		)
	elif current_step.has("templateId"):
		var item: Dictionary = _content["interface"]["items"][str(int(current_step["templateId"]))]
		var name_width: float = (
			FONT.get_string_size(item["name"]["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		)
		var x: float = (240 - name_width) / 2
		if item["icon"] != null:
			_icon(item["icon"], origin + Vector2(x - 14, 27) * factor, factor)
		_text(item["name"]["text"], origin + Vector2(x, 38) * factor, factor, Color.YELLOW)
		if current_step.has("warehouseNotice"):
			_text(
				current_step["warehouseNotice"],
				origin + Vector2(120, 57) * factor,
				factor,
				Color.YELLOW,
				true
			)


func _icon(key: String, position: Vector2, factor: float) -> void:
	var texture: Texture2D = _textures[key]
	draw_texture_rect(texture, Rect2(position, texture.get_size() * factor), false)


func _text(
	value: String, position: Vector2, factor: float, color: Color, centered: bool = false
) -> void:
	var font_size: int = roundi(12 * factor)
	if centered:
		position.x -= FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2
	draw_string(FONT, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
