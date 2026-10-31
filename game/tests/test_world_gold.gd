extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var directory: String = "user://test_world_gold_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(directory)
	var path: String = directory.path_join("continue.json")
	var store_script: Script = load("res://persistence/battle_store.gd")
	var store: RefCounted = store_script.new(scene.content, path)
	scene.battle_store = store
	var content: Dictionary = scene.content.duplicate(true)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	store.write_slot(0, progress)
	await scene._show_completed_progress(progress)
	var world: Control = scene.story_player
	world.advance()
	var button: Button = world.choices.get_node_or_null("World_gold")
	if button == null:
		fail("The original coin entry must be an immediately available local testing benefit")
		return
	button.pressed.emit()
	if scene.world_progress["gold"] != 7000 or store.read()["progress"]["gold"] != 7000:
		fail(
			"One benefit click must grant and persist 1000 coins directly, without recharge/confirmation"
		)
		return
	if (
		scene.world_progress["party"] != progress["party"]
		or store.read_slot(0)["progress"]["gold"] != 6000
	):
		fail(
			"The benefit changes only current funds, preserving held items and explicit named records"
		)
		return
	button.pressed.emit()
	if scene.world_progress["gold"] != 7000:
		fail("A hidden menu button must not grant again while its feedback owns input")
		return
	await close_notice(world)
	world.choices.get_node("World_gold").pressed.emit()
	if scene.world_progress["gold"] != 8000:
		fail("The testing benefit must remain repeatable after its feedback closes")
		return
	await close_notice(world)
	# Controlled upper-bound fixture; the actual button and persistence still perform the grant.
	scene.world_progress["gold"] = 9999500
	world.choices.get_node("World_gold").pressed.emit()
	if scene.world_progress["gold"] != 9999999 or store.read()["progress"]["gold"] != 9999999:
		fail("A benefit near the source funds limit must cap without overflow")
		return
	await close_notice(world)
	world.choices.get_node("World_gold").pressed.emit()
	if scene.world_progress["gold"] != 9999999 or not world.dialogue.full_text.contains("上限"):
		fail("At the limit, the benefit must retain funds and explain that the cap was reached")
		return
	await close_notice(world)
	var blocked_path: String = directory.path_join("blocked.json")
	DirAccess.make_dir_absolute(blocked_path)
	var sentinel: String = blocked_path.path_join("owned.txt")
	var file := FileAccess.open(sentinel, FileAccess.WRITE)
	file.store_string("preserve")
	file.close()
	scene.battle_store = store_script.new(scene.content, blocked_path)
	scene.world_progress["gold"] = 6000
	world.choices.get_node("World_gold").pressed.emit()
	if scene.world_progress["gold"] != 6000 or not world.dialogue.full_text.contains("未完成"):
		fail("A failed persistence step must not claim or commit an unsaved benefit")
		return
	if store.read()["progress"]["gold"] != 9999999 or not FileAccess.file_exists(sentinel):
		fail("A failed benefit must preserve other stored progress and the existing target")
		return
	await close_notice(world)
	for owned: String in [path, directory.path_join("continue_slot_1.json"), sentinel]:
		DirAccess.remove_absolute(owned)
	DirAccess.remove_absolute(blocked_path)
	DirAccess.remove_absolute(directory)
	scene.queue_free()
	await process_frame
	print(
		"PASS world benefit: direct/repeat grant, persistence, protected records/items, cap, failure"
	)
	quit(0)


func close_notice(world: Control) -> void:
	for update: int in range(30):
		if not world.dialogue.visible:
			return
		world.advance()
		for tick: int in range(3):
			world.tick()
		await process_frame
	fail("Benefit feedback must return to the same usable world menu")


func fail(message: String) -> void:
	push_error(message)
	quit(1)
