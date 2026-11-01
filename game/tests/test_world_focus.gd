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
	await scene._show_completed_progress(progress)
	var world: Control = scene.story_player
	var view: RefCounted = world.get("_world_view")
	var anchor: Vector2 = view.viewport_origin + view.viewport_size / 2
	var before: Vector2 = view.center
	var zoom: float = view.zoom
	var selected: int = world.selected_world_node
	await mouse_button(anchor, true)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	if view.center != before or view.zoom != zoom or world.selected_world_node != selected:
		fail("Canceling a world gesture must preserve the camera, zoom and selected place")
		return
	# Deliberately omit release to exercise the application boundary, not an OS event-loss claim.
	await mouse_motion(anchor + Vector2(80, 0), 0)
	var hover_dragged: bool = not view.center.is_equal_approx(before)
	var node: Array = content["story"]["world"]["nodes"][selected]["position"]
	var node_point: Vector2 = view.screen_at(Vector2(node[0] + 0.5, node[1] + 0.5))
	await mouse_button(node_point, true)
	await mouse_button(node_point, false)
	if hover_dragged or not world.choices.visible:
		fail(
			(
				"After focus loss, hover dragged=%s and the next click was ignored=%s"
				% [hover_dragged, not world.choices.visible]
			)
		)
		return
	world.go_back()
	before = view.center
	await mouse_button(anchor, true)
	await mouse_motion(anchor + Vector2(80, 0), MOUSE_BUTTON_MASK_LEFT)
	await mouse_button(anchor + Vector2(80, 0), false)
	if view.center.is_equal_approx(before) or world.choices.visible:
		fail("A fresh mouse drag must pan the world without selecting or opening its menu")
		return
	before = view.center
	await touch(anchor, 3, true)
	root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
	root.propagate_notification(NOTIFICATION_APPLICATION_RESUMED)
	if view.center != before or view.zoom != zoom or world.selected_world_node != selected:
		fail("Pausing a world touch must preserve its camera and place")
		return
	# A new contact has a different identity; the lost contact must not make it multi-touch.
	await touch(anchor, 5, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 5
	drag.position = anchor - Vector2(80, 0)
	Input.parse_input_event(drag)
	await process_frame
	await touch(drag.position, 5, false)
	if view.center.is_equal_approx(before) or world.choices.visible:
		fail("A fresh touch after resume must drag normally rather than retain the lost contact")
		return
	node_point = view.screen_at(Vector2(node[0] + 0.5, node[1] + 0.5))
	await touch(node_point, 6, true)
	await touch(node_point, 6, false)
	if not world.choices.visible:
		fail("A fresh world touch must still select and confirm the current place")
		return
	if (
		scene.world_progress != progress
		or world.selected_world_node != selected
		or view.zoom != zoom
	):
		fail("Gesture cancellation and fresh input must not change world progress, place or zoom")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS world focus: omitted release, inert hover, fresh mouse/touch and unchanged progress"
	)
	quit(0)


func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func mouse_motion(point: Vector2, buttons: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = buttons
	Input.parse_input_event(event)
	await process_frame


func touch(point: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
