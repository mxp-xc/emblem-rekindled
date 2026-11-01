extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var directory: String = "user://test_playtest_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_absolute(directory) != OK:
		fail("The probe test must own a newly created record directory")
		return
	scene.store.path = directory.path_join("settings.json")
	var configuration: String = directory.path_join("playtest.json")
	var probe_script: Script = load("res://app/playtest_probe.gd")
	if probe_script == null:
		fail("Tests need a read-only runtime state interface instead of saving progress")
		return
	var probe: Node = probe_script.new()
	root.add_child(probe)
	_write(configuration, {"speed": 32})
	var result: Dictionary = probe.setup(scene, directory)
	if not result["ok"] or not result["enabled"] or Engine.time_scale != 1:
		fail("Debug reads must start at normal speed even with a leftover legacy speed file")
		return
	var save_path: String = directory.path_join("battle_save.json")
	scene.battle_store = load("res://persistence/battle_store.gd").new(scene.content, save_path)
	scene.resume_battle(scene.battle)
	var before: Dictionary = scene.battle.snapshot()
	var expected: Dictionary = JSON.parse_string(JSON.stringify(before))
	# RNG purity is part of this diagnostic interface's contract.
	var random_state: int = scene.battle._rng.state
	var response_path: String = directory.path_join("playtest_state.json")
	var request_path: String = directory.path_join("playtest_request.json")
	await create_timer(0.08, true, false, true).timeout
	if FileAccess.file_exists(response_path):
		fail("The debug service must stay silent until an explicit state request")
		return
	scene._set_menu_visible(true)
	scene.menu_layer.show_page("settings")
	scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	scene._set_menu_visible(false)
	_write(request_path + ".tmp", {"requestId": "unpublished"})
	await create_timer(0.1, true, false, true).timeout
	if FileAccess.file_exists(response_path):
		fail("An unpublished request must not be consumed before its atomic rename")
		return
	DirAccess.remove_absolute(request_path + ".tmp")
	for request: String in ["first", "second"]:
		_write(directory.path_join("playtest_request.json"), {"requestId": request})
		var deadline: int = Time.get_ticks_msec() + 3000
		var response: Dictionary = {}
		while Time.get_ticks_msec() < deadline:
			if FileAccess.file_exists(response_path):
				response = JSON.parse_string(FileAccess.get_file_as_string(response_path))
				if response.get("requestId") == request:
					break
			await process_frame
		if (
			response.get("requestId") != request
			or response.get("snapshot", {}).get("state") != expected
		):
			fail("On-demand reads must return the correlated live snapshot without opening a menu")
			return
		if not response["ready"] or response["controls"].is_empty() or response["speed"] != 32:
			fail("Runtime reads must expose real readiness, visible controls and test speed")
			return
		if not FileAccess.file_exists(request_path):
			fail(
				"A consumed request must remain readable while filesystem synchronization is pending"
			)
			return
	probe._timer.stop()
	var sentinel: Dictionary = {"duplicateResponseSentinel": true}
	_write(response_path, sentinel)
	for repetition: int in range(20):
		probe._read_request()
	if JSON.parse_string(FileAccess.get_file_as_string(response_path)) != sentinel:
		fail("An unchanged request must not rewrite its response on subsequent polls")
		return
	_write_text(request_path, '{ "requestId" : "second" }')
	probe._read_request()
	if JSON.parse_string(FileAccess.get_file_as_string(response_path)) != sentinel:
		fail("A repeated request ID must not run again when its JSON formatting changes")
		return
	for invalid: String in ["", "{", "[]", '{"requestId":""}', '{"requestId":42}']:
		_write_text(request_path, invalid)
		probe._read_request()
		var rejected: Variant = JSON.parse_string(FileAccess.get_file_as_string(response_path))
		if not rejected is Dictionary or rejected.get("error") != "INVALID_PLAYTEST_REQUEST":
			fail("Invalid request payloads must produce a bounded protocol error")
			return
		_write(response_path, sentinel)
		for repetition: int in range(20):
			probe._read_request()
		if (
			FileAccess.get_file_as_string(request_path) != invalid
			or JSON.parse_string(FileAccess.get_file_as_string(response_path)) != sentinel
		):
			fail("Invalid requests must remain on disk without regenerating errors on every poll")
			return
	_write(request_path, {"requestId": "after-invalid"})
	probe._read_request()
	var recovered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(response_path))
	if (
		recovered.get("requestId") != "after-invalid"
		or recovered.get("snapshot", {}).get("state") != expected
		or not FileAccess.file_exists(request_path)
	):
		fail("Overwriting an invalid request with a new unique ID must return the live snapshot")
		return
	if (
		scene.battle.snapshot() != before
		or scene.battle._rng.state != random_state
		or FileAccess.file_exists(save_path)
		or scene.menu_layer.visible
	):
		fail("Diagnostic reads must not mutate battle/RNG, create progress or open menus")
		return
	probe.queue_free()
	await process_frame
	if Engine.time_scale != 32:
		fail("Removing a read-only observer must not change the user's selected session rate")
		return
	for filename: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	Engine.time_scale = 1
	print(
		"PASS playtest API: retained requests, deduplication, invalid recovery, no save/RNG mutation"
	)
	quit(0)


func _write(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value))


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func fail(message: String) -> void:
	push_error(message)
	quit(1)
