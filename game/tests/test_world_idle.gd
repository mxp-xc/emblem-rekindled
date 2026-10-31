extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
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
	var world: Control = scene.story_player
	world.show_world(progress)
	world.set_process(false)
	if world.get("world_actor_frame") == null:
		fail("The resident world actor needs an advancing idle presentation")
		return
	for tick: int in range(5):
		world.tick()
	if world.world_actor_frame != 0:
		fail("The source idle frame holds for six 65ms updates")
		return
	world.tick()
	if world.world_actor_frame != 1:
		fail("The resident character must switch to its second idle frame after 390ms")
		return
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	world.handle_key(enter)
	if not world.choices.visible:
		fail("The idle test must open the real resident world menu")
		return
	for tick: int in range(18):
		world.tick()
	if world.world_actor_frame != 1:
		fail("The world menu must freeze the underlying original idle clock")
		return
	world.go_back()
	for tick: int in range(6):
		world.tick()
	if world.world_actor_frame != 0:
		fail("Closing the menu must resume the two-frame idle loop")
		return
	scene.queue_free()
	await process_frame
	print("PASS world idle: 390ms two-frame loop, menu freeze and resume")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
