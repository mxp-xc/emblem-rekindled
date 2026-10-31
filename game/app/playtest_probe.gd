extends Node

var _scene: Control
var _directory: String
var _timer: Timer
var _previous_speed: float = 1


func setup(scene: Control, configuration: String = "user://playtest.json") -> Dictionary:
	if (
		not OS.is_debug_build()
		or OS.has_feature("web")
		or not FileAccess.file_exists(configuration)
	):
		return {"ok": true, "enabled": false}
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(configuration))
	if (
		not config is Dictionary
		or config.keys() != ["speed"]
		or not (config["speed"] is float or config["speed"] is int)
		or not is_finite(float(config["speed"]))
		or float(config["speed"]) < 1
		or float(config["speed"]) > 32
	):
		return {"ok": false, "error": "INVALID_PLAYTEST_CONFIG"}
	if _timer != null:
		return {"ok": false, "error": "PLAYTEST_ALREADY_RUNNING"}
	_scene = scene
	_directory = configuration.get_base_dir()
	_previous_speed = Engine.time_scale
	Engine.time_scale = config["speed"]
	_timer = Timer.new()
	_timer.wait_time = 0.05
	_timer.ignore_time_scale = true
	_timer.timeout.connect(_read_request)
	add_child(_timer)
	_timer.start()
	return {"ok": true, "enabled": true}


func _exit_tree() -> void:
	if _timer != null:
		Engine.time_scale = _previous_speed


func _read_request() -> void:
	var request_path: String = _directory.path_join("playtest_request.json")
	if not FileAccess.file_exists(request_path):
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(request_path))
	DirAccess.remove_absolute(request_path)
	var response: Dictionary
	if (
		not request is Dictionary
		or request.keys() != ["requestId"]
		or not request["requestId"] is String
		or request["requestId"].is_empty()
	):
		response = {"ok": false, "error": "INVALID_PLAYTEST_REQUEST"}
	else:
		response = _snapshot()
	if request is Dictionary and request.get("requestId") is String:
		response["requestId"] = request["requestId"]
	var path: String = _directory.path_join("playtest_state.json")
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("Playtest response open failed: " + error_string(FileAccess.get_open_error()))
		_timer.stop()
		return
	file.store_string(JSON.stringify(response))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		push_error("Playtest response write failed: " + error_string(error))
		_timer.stop()


func _snapshot() -> Dictionary:
	var controls: Array = []
	for control: Node in _scene.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or not (control is Button or control is HSlider):
			continue
		var rect: Rect2 = control.get_global_rect()
		var row: Dictionary = {
			"name": "Menu" if control == _scene.menu_button else str(control.name),
			"path": str(_scene.get_path_to(control)),
			"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		}
		if control is Button:
			row["text"] = control.text
			row["enabled"] = not control.disabled
		else:
			row["value"] = control.value
		controls.append(row)
	var viewport: Vector2 = _scene.get_viewport_rect().size
	var window: Vector2i = DisplayServer.window_get_size()
	var view: RefCounted = _scene.map.view
	return {
		"ok": true,
		"speed": Engine.time_scale,
		"busy": _scene.busy,
		"ready": not _scene.busy and _scene.map.visible and _scene.battle.can_save(),
		"snapshot":
		{
			"version": 1,
			"chapterId": _scene.content["entry"]["id"],
			"battleId": _scene.content["entry"]["firstBattle"],
			"state": _scene.battle.snapshot()
		},
		"world": _scene.world_progress.duplicate(true),
		"itemOptions":
		_scene.battle.item_options(_scene.selected_unit) if _scene.selected_unit >= 0 else {},
		"ui":
		{
			"title": _scene.title_screen.visible,
			"prologue": _scene.title_screen.prologue.visible,
			"titleOptions": _scene.title_screen.options.visible,
			"story": _scene.story_player.visible,
			"dialogue": _scene.story_player.dialogue.visible,
			"commander": _scene.story_player.commander.is_visible_in_tree(),
			"feedback":
			(
				_scene.action_feedback.current_step.get("kind", "")
				if _scene.action_feedback.visible
				else ""
			),
			"worldReady":
			(
				_scene.story_player.visible
				and _scene.story_player.world_active
				and _scene.story_player.world_ready
			),
			"menu": _scene.menu_layer.visible,
			"menuPage": _scene.menu_layer.page,
			"unitMenu": _scene.unit_panel.visible,
			"selectedUnit": _scene.selected_unit,
			"choices": _scene.story_player.choices.visible,
			"battle": _scene.battle_view.playing
		},
		"map":
		{
			"zoom": view.zoom,
			"center": [view.center.x, view.center.y],
			"origin": [view.viewport_origin.x, view.viewport_origin.y],
			"size": [view.viewport_size.x, view.viewport_size.y]
		},
		"viewport": [viewport.x, viewport.y],
		"window": [window.x, window.y],
		"controls": controls
	}
