extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	var directory: String = "user://test_world_inventory_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	var path: String = directory.path_join("continue.json")
	scene.battle_store.path = path
	scene.battle_store.write_progress(progress)
	scene.battle_store.write_slot(0, progress)
	var initial_bytes: String = FileAccess.get_file_as_string(path)
	var named_bytes: String = FileAccess.get_file_as_string(
		directory.path_join("continue_slot_1.json")
	)
	await scene._show_completed_progress(progress)
	scene.story_player.advance()
	await process_frame
	var entry: Button = scene.story_player.find_child("World_inventory", true, false)
	if entry == null:
		fail("The resident world menu must open actual item organization")
		return
	entry.pressed.emit()
	await process_frame
	var view: Control = scene.get("world_inventory_screen")
	if view == null or not view.visible or view.page != "overview":
		fail("World items must show the party overview, without opening tactical actions")
		return
	if scene.story_player.choices.visible:
		fail("The item screen replaces the world menu rather than overlaying two actionable lists")
		return
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	var warehouse: Button = view.find_child("Warehouse", true, false)
	if warehouse == null or view.page != "operations":
		fail("Confirming the world character must expose Shop, Warehouse and Trade operations")
		return
	warehouse.pressed.emit()
	await process_frame
	if view.page != "warehouse":
		fail("The world warehouse must open its two inventory tabs")
		return
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	if (
		view.stage != "confirm"
		or scene.world_progress != progress
		or FileAccess.get_file_as_string(path) != initial_bytes
	):
		fail("Preparing a deposit confirmation must not change or save either inventory")
		return
	await key(KEY_ESCAPE)
	if view.stage != "items" or scene.world_progress != progress:
		fail("Back from confirmation cancels only that prompt, retaining the selected item")
		return
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	if scene.world_progress["warehouse"].size() != 1 or not scene.battle_store.read()["ok"]:
		fail("Confirming a world deposit must commit a valid current continue record")
		return
	if FileAccess.get_file_as_string(directory.path_join("continue_slot_1.json")) != named_bytes:
		fail("World item changes must never automatically overwrite a named world slot")
		return
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	if view.page != "operations" or root.gui_get_focus_owner() != warehouse:
		fail("Leaving warehouse tabs must return to the same character operation")
		return
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	if view.visible or not scene.story_player.world_active or scene.story_player.choices.visible:
		fail("Back through operations/overview must return directly to the resident world map")
		return
	scene.story_player.advance()
	scene.story_player.find_child("World_inventory", true, false).pressed.emit()
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	view.find_child("Shop", true, false).pressed.emit()
	await process_frame
	if view.page != "shop" or view.stage != "tabs":
		fail("The default local shop opens buying/selling tabs without activation or recharge")
		return
	var shop_before: Dictionary = scene.world_progress.duplicate(true)
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	if view.stage != "confirm" or scene.world_progress != shop_before:
		fail("A purchase preview must retain funds until the explicit confirmation")
		return
	await key(KEY_ESCAPE)
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	if (
		scene.world_progress["gold"] != 5000
		or scene.battle_store.read()["progress"]["gold"] != 5000
	):
		fail("The shop confirmation must charge and persist the original purchase price once")
		return
	var committed: Dictionary = scene.world_progress.duplicate(true)
	var blocked: String = directory.path_join("blocked.json")
	DirAccess.make_dir_absolute(blocked)
	var sentinel_path: String = blocked.path_join("owned.txt")
	var sentinel := FileAccess.open(sentinel_path, FileAccess.WRITE)
	sentinel.store_string("preserve")
	sentinel.close()
	scene.battle_store.path = blocked
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	if (
		view.stage != "notice"
		or scene.world_progress != committed
		or not FileAccess.file_exists(sentinel_path)
	):
		fail("A failed purchase write must preserve current items/funds and the previous target")
		return
	scene.battle_store.path = path
	await key(KEY_ESCAPE)
	await key(KEY_ENTER)
	await key(KEY_ENTER)
	if (
		scene.world_progress["gold"] != 4000
		or scene.battle_store.read()["progress"]["gold"] != 4000
	):
		fail("Retrying after a failed write must purchase once without duplicate charge or items")
		return
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	if view.page != "operations":
		fail("Shop Back must traverse items and tabs before returning to character operations")
		return
	view.find_child("Trade", true, false).pressed.emit()
	await process_frame
	if view.page != "partner":
		fail("World exchange must select another formal character without tactical adjacency")
		return
	await key(KEY_ENTER)
	var exchange: Control = view.find_child("WorldExchange", true, false)
	if view.page != "exchange" or exchange == null or not exchange.visible:
		fail("Confirming a world partner opens the reused two-inventory exchange component")
		return
	var hero_before: Dictionary = scene.world_inventory.actor(scene.world_progress, 0)
	var iron: Dictionary = hero_before["inventory"][0].duplicate(true)
	exchange.find_child("Owner0_Item1", true, false).pressed.emit()
	exchange.find_child("Owner1_Item53", true, false).pressed.emit()
	await process_frame
	var celica: Dictionary = scene.world_inventory.actor(scene.world_progress, 9)
	if not celica["inventory"].has(iron) or scene.world_progress["gold"] != 4000:
		fail("World exchange moves the owned instance and its uses, without charging funds")
		return
	exchange.find_child("Owner1_Item1", true, false).pressed.emit()
	exchange.find_child("Owner0_Item53", true, false).pressed.emit()
	await process_frame
	if not scene.world_inventory.actor(scene.world_progress, 0)["inventory"].has(iron):
		fail("Selecting the lower inventory as source must reverse the actual transfer direction")
		return
	for expected: String in ["partner", "operations", "overview", "world"]:
		await key(KEY_ESCAPE)
		if (
			(expected == "world" and view.visible)
			or (expected != "world" and view.page != expected)
		):
			fail(
				(
					"World exchange Back must cancel source/pair/operation one layer at a time: "
					+ expected
				)
			)
			return
	var restored: Dictionary = scene.battle_store.read()
	if (
		not restored["ok"]
		or restored["progress"]["gold"] != 4000
		or restored["progress"]["warehouse"].size() != 1
	):
		fail("Reopening the current continue record must restore committed items and funds")
		return
	if FileAccess.get_file_as_string(directory.path_join("continue_slot_1.json")) != named_bytes:
		fail("Purchases and exchanges leave the explicit named archive byte-for-byte intact")
		return
	DirAccess.remove_absolute(sentinel_path)
	DirAccess.remove_absolute(blocked)
	for file: String in [path, directory.path_join("continue_slot_1.json")]:
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print("PASS world inventory UI: resident menu, party overview, exclusive input")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func key(code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	Input.parse_input_event(event)
	await process_frame
