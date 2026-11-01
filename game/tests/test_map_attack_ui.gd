extends SceneTree


class Navigation:
	extends Node
	var view: Control

	func _input(event: InputEvent) -> void:
		if not view.visible:
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				view.handle_wheel(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
				get_viewport().set_input_as_handled()
		elif event is InputEventKey:
			if event.pressed and event.keycode == KEY_ESCAPE:
				view.go_back()
				get_viewport().set_input_as_handled()
			elif view.handle_key(event):
				get_viewport().set_input_as_handled()


var _intents: Array[Dictionary] = []
var _map_clicks: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	# UI fixture reads the published interface directly, without domain/content validation.
	var entry: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/chapter.json")
	)
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry["library"]))
	var content: Dictionary = {
		"entry": {"resourceDirectory": "res://"},
		"interface": bank["interface"],
		"rules": JSON.parse_string(FileAccess.get_file_as_string(entry["rules"]))
	}
	for texture: Dictionary in content["interface"]["textures"].values():
		texture["texture"] = str(texture["texture"]).trim_prefix("res://")
	var map_button := Button.new()
	map_button.size = Vector2(720, 1280)
	map_button.pressed.connect(func() -> void: _map_clicks += 1)
	root.add_child(map_button)
	var view: Control = load("res://features/tactical_map/target_selection.gd").new()
	view.theme = load("res://ui/pixel_theme.gd").new().create(
		content["interface"], content["entry"]["resourceDirectory"]
	)
	root.add_child(view)
	view.setup(content)
	var navigation := Navigation.new()
	navigation.view = view
	root.add_child(navigation)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(540, 960)
	view.intent.connect(
		func(kind: String, details: Dictionary) -> void:
			_intents.append({"kind": kind, "details": details})
	)
	view.present([{"item": {"id": "map_item", "templateId": 46, "durability": 5}}])
	view.show_map_forecast(_preview(-1, 24))
	await process_frame
	await process_frame
	if view.page != "map_forecast" or view.target_id != -1:
		fail("A whole-map attack must preview without inventing a primary target")
		return
	var last: Label = view.find_child("MapTarget_24", true, false)
	var last_hp: Label = view.find_child("MapTargetHp_24", true, false)
	if last == null or last.text != "目标24" or not last_hp.text.contains("30 → 23"):
		fail("The preview must retain every affected target, name and current/predicted HP")
		return
	var title: Label = view.find_child("MapForecastTitle", true, false)
	var summary: Label = view.find_child("MapForecastSummary", true, false)
	if (
		title.text != content["interface"]["items"]["46"]["name"]["text"] + " · 范围预览"
		or not summary.text.contains("整次耗1耐久 · 无反击/暴击 · 不收集掉落")
	):
		fail("The preview must name the weapon and explain the whole-cast cost and loot policy")
		return
	var scroll: ScrollContainer = view.find_child("MapForecastTargets", true, false)
	await _wheel()
	if scroll.scroll_vertical <= 0 or view.target_id != -1:
		fail("Wheel input must scroll long forecasts without selecting a primary target")
		return
	for step: int in range(40):
		await _key(KEY_DOWN)
	if not scroll.get_global_rect().intersects(last.get_global_rect()):
		fail("The final target must remain reachable by scrolling, with no truncated target set")
		return
	await _click(Vector2(3, 300))
	if _map_clicks != 0:
		fail("Blank forecast space must consume pointer input instead of clicking the map")
		return
	await _key(KEY_ESCAPE)
	if view.page != "items" or _intents.back()["kind"] != "target_cancelled":
		fail("Back from a whole-map preview must return to the same item list without casting")
		return
	view.present(
		[
			{
				"item": {"id": "blocked", "templateId": 46, "durability": 5},
				"available": false,
				"reason": "ROUND_UNAVAILABLE"
			},
			{"item": {"id": "map_item", "templateId": 49, "durability": 12}}
		]
	)
	_intents.clear()
	await _key(KEY_ENTER)
	if (
		not _intents.is_empty()
		or view.find_child("UnavailableReason", true, false).text != "本回合不可使用"
	):
		fail("An unavailable row must show its reason and refuse confirmation")
		return
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	if _intents.back()["details"].get("item") != "map_item":
		fail("Available rows without availability fields must retain normal item confirmation")
		return
	view.show_targets([{"id": 1}, {"id": 2}, {"id": 3}])
	view.select_target(2)
	var area: Dictionary = _preview(2, 3)
	area["weapon"] = 49
	view.show_map_forecast(area)
	_intents.clear()
	await _key(KEY_RIGHT)
	await _key(KEY_ESCAPE)
	if view.page != "targets" or view.target_id != 2 or _has_intent("target_cancelled"):
		fail("Area forecast Back must retain its primary target without leaving targeting")
		return
	await _key(KEY_ESCAPE)
	if view.page != "items" or root.gui_get_focus_owner().name != "Weapon_49":
		fail("Back from area targets must retain the previously selected held item")
		return
	view.show_map_forecast(area)
	for dimensions: Vector2 in [
		Vector2(540, 960), Vector2(720, 1280), Vector2(960, 540), Vector2(240, 500)
	]:
		view.size = dimensions
		await process_frame
		await process_frame
		var bounds := Rect2(view.global_position, view.size).grow(0.1)
		for control: Control in [
			view.find_child("MapForecastPanel", true, false),
			view.find_child("Confirm", true, false),
			view.find_child("Back", true, false)
		]:
			if not bounds.encloses(control.get_global_rect()):
				fail(
					(
						"Forecast %s must stay inside %s after resize, got %s"
						% [control.name, bounds, control.get_global_rect()]
					)
				)
				return
	view.size = Vector2(540, 960)
	await process_frame
	_intents.clear()
	await _click(view.find_child("Confirm", true, false).get_global_rect().get_center())
	await _key(KEY_ENTER)
	await _key(KEY_SPACE)
	if (
		_intents.size() != 1
		or _intents[0] != {"kind": "map_attack_confirmed", "details": {"target": 2}}
	):
		fail("A real confirm click plus repeated keys must submit exactly one map attack intent")
		return
	view.show_targets([{"id": 1}, {"id": 2}])
	view.select_target(1)
	view.show_forecast(_ordinary_preview())
	if view.find_child("MapAttackForecast", true, false).is_visible_in_tree():
		fail("Returning to an ordinary forecast must hide the complete map forecast")
		return
	_intents.clear()
	await _key(KEY_ENTER)
	if _intents.size() != 1 or _intents[0]["kind"] != "attack_confirmed":
		fail("Ordinary battle forecasting must preserve its original confirmation intent")
		return
	view.present([{"item": {"id": "staff", "templateId": 53, "durability": 1}}], "heal")
	view.show_targets([{"id": 2}])
	_intents.clear()
	await _key(KEY_ENTER)
	if (
		_intents.back()["kind"] != "target_selected"
		or _intents.back()["details"]["action"] != "heal"
	):
		fail("Staff targeting must still confirm directly without retaining map forecast state")
		return
	view.queue_free()
	navigation.queue_free()
	map_button.queue_free()
	await process_frame
	print(
		"PASS map attack UI: full scrollable targets, input ownership, Back, one cast, legacy pages"
	)
	quit(0)


func _preview(primary: int, count: int) -> Dictionary:
	var preview: Dictionary = {
		"ok": true,
		"actionMode": "map_attack",
		"actor": 0,
		"item": "map_item",
		"weapon": 46,
		"primary": primary,
		"participants": [{"id": 0, "name": "施法者", "hp": 30}],
		"targetIds": [],
		"forecasts": {},
		"affectedCells": {},
		"rangeCells": {},
		"mapEffect": "earthquake"
	}
	for id: int in range(1, count + 1):
		preview["targetIds"].append(id)
		preview["participants"].append({"id": id, "name": "目标%d" % id, "hp": 30})
		preview["forecasts"][str(id)] = {"damage": 7, "hit": 65}
	return preview


func _ordinary_preview() -> Dictionary:
	var forecast: Dictionary = {
		"weapon": 9,
		"damage": 7,
		"hit": 65,
		"critical": 3,
		"canAttack": true,
		"advantage": 0,
		"double": false
	}
	return {
		"participants":
		[
			{"id": 0, "name": "施法者", "hp": 30, "maxHp": 30, "faction": 0},
			{"id": 1, "name": "目标", "hp": 30, "maxHp": 30, "faction": 2}
		],
		"forecasts": {"0": forecast, "1": forecast.duplicate()}
	}


func _has_intent(kind: String) -> bool:
	for entry: Dictionary in _intents:
		if entry["kind"] == kind:
			return true
	return false


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _wheel() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = Vector2(200, 300)
	Input.parse_input_event(event)
	await process_frame


func _click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
