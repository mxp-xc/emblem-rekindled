extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var world: Control = scene.story_player
	world.set("_tick_seconds", 0.001)
	await world.show_world({"worldNode": 16, "worldStep": 10, "route": 2})
	var reached: Array[int] = []
	world.world_node_reached.connect(func(node: int) -> void: reached.append(node))
	await world.travel_to(8, false)
	if reached != [12, 8] or world.get("_world_current_node") != 8 or not world.world_ready:
		push_error("Actual world travel must reach node 12 before node 8: " + str(reached))
		quit(1)
		return
	reached.clear()
	await world.travel_to(16, false)
	if reached != [12, 16] or world.get("_world_current_node") != 16:
		push_error("Actual world travel must traverse the same route in reverse: " + str(reached))
		quit(1)
		return
	reached.clear()
	var interrupted: Dictionary = await world.travel_to(8, true, 12)
	if (
		reached != [12]
		or interrupted != {"ok": true, "node": 12, "interrupted": true}
		or not world.world_ready
		or world.dialogue.visible
	):
		push_error("Encounter waypoint must stop travel before the selected destination")
		quit(1)
		return
	scene.queue_free()
	await process_frame
	print("PASS actual world travel follows intervening nodes in both directions")
	quit(0)
