extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	var script: Script = load("res://persistence/battle_store.gd")
	var path: String = "user://test_slots_%d.json" % Time.get_ticks_usec()
	var store: RefCounted = script.new(content, path)
	if not store.has_method("has_slot"):
		fail("Four named world records must coexist with the original temporary continue record")
		return
	if not store.write(battle)["ok"]:
		fail("An existing temporary battle record must remain writable")
		return
	var original: String = FileAccess.get_file_as_string(path)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	for slot: int in range(4):
		if store.has_slot(slot) or not store.read_slot(slot).get("missing", false):
			fail("Each named slot begins empty independently of the temporary record")
			return
		var record: Dictionary = progress.duplicate(true)
		record["gold"] += slot * 100
		if not store.write_slot(slot, record)["ok"]:
			fail("Each selected named world slot must be writable")
			return
	for slot: int in range(4):
		var loaded: Dictionary = store.read_slot(slot)
		if not loaded["ok"] or loaded["progress"]["gold"] != 6000 + slot * 100:
			fail("Named records must retain separate party/funds and survive repository reopening")
			return
		var reopened: RefCounted = script.new(content, path)
		if reopened.read_slot(slot) != loaded:
			fail("The four records must survive a new repository instance")
			return
	if FileAccess.get_file_as_string(path) != original or not store.read().has("battle"):
		fail(
			"Writing named world records must preserve the original temporary battle byte-for-byte"
		)
		return
	for invalid_slot: int in [-2, -1, 4, 100]:
		if (
			store.has_slot(invalid_slot)
			or store.read_slot(invalid_slot)["ok"]
			or store.write_slot(invalid_slot, progress)["ok"]
		):
			fail("Invalid named slot indexes must reject rather than alias another record")
			return
	var invalid: Dictionary = progress.duplicate(true)
	invalid["party"][0]["hp"] = -1
	if store.write_slot(1, invalid)["ok"] or store.read_slot(1)["progress"]["gold"] != 6100:
		fail("Invalid progress must preserve the selected previous record")
		return
	var damaged_path: String = path.get_basename() + "_slot_2.json"
	for damaged: String in ["{broken", original]:
		var damaged_file := FileAccess.open(damaged_path, FileAccess.WRITE)
		damaged_file.store_string(damaged)
		damaged_file.close()
		if (
			not store.has_slot(1)
			or store.read_slot(1)["ok"]
			or store.read_slot(0)["progress"]["gold"] != 6000
			or FileAccess.get_file_as_string(damaged_path) != damaged
		):
			fail(
				"Corruption or a tactical record in a world slot must reject without altering files"
			)
			return
	if not store.write_slot(1, progress)["ok"]:
		fail("An explicit valid overwrite must repair only the selected damaged slot")
		return
	# Use the owned test directory to force an atomic replacement failure for one slot.
	var owned_directory: String = "user://test_slots_blocked_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(owned_directory)
	var blocked: RefCounted = script.new(content, owned_directory.path_join("save.json"))
	var candidate: Dictionary = progress.duplicate(true)
	candidate["gold"] = 7777
	if not blocked.write_slot(0, candidate)["ok"]:
		fail("The failure fixture needs one valid independent named record")
		return
	var slot_directory: String = owned_directory.path_join("save_slot_2.json")
	DirAccess.make_dir_absolute(slot_directory)
	var sentinel: String = slot_directory.path_join("owned.txt")
	var file := FileAccess.open(sentinel, FileAccess.WRITE)
	file.store_string("owned test fixture")
	file.close()
	if blocked.write_slot(1, progress)["ok"] or blocked.read_slot(0)["progress"]["gold"] != 7777:
		fail("A failed replacement must preserve other named records")
		return
	if not FileAccess.file_exists(sentinel):
		fail("A failed write must preserve the preexisting target")
		return
	DirAccess.remove_absolute(sentinel)
	DirAccess.remove_absolute(slot_directory)
	DirAccess.remove_absolute(owned_directory.path_join("save_slot_1.json"))
	DirAccess.remove_absolute(owned_directory)
	for slot: int in range(4):
		DirAccess.remove_absolute(path.get_basename() + "_slot_%d.json" % (slot + 1))
	DirAccess.remove_absolute(path)
	print(
		"PASS named slots: four isolated world records, separate continue, reopen, invalid/write failure"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
