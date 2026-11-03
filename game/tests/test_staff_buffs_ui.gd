extends SceneTree

var draws: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(scene.content, _roll)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 9:
			actor["inventory"] = [{"id": "force_staff", "templateId": 55, "durability": 1}]
			actor["equippedInstanceId"] = ""
	if not battle.restore_snapshot(state)["ok"]:
		fail("Prepare a full-HP allied force-staff target")
		return
	battle.complete_event("level_tutorial")
	scene.resume_battle(battle)
	var before: Dictionary = battle.snapshot()
	var before_draws: int = draws
	scene._show_unit_menu(Vector2i(9, 11))
	var staff: Button = scene.get_node("UnitStatus/Status/Actions/Heal")
	if not staff.visible or staff.text != "杖":
		fail("Force staff must use the normal staff action")
		return
	staff.pressed.emit()
	var view: Control = scene.target_selection
	view.find_child("Staff_0", true, false).pressed.emit()
	if view.page != "targets" or scene.map.action_hint != "选择杖目标" or battle.snapshot() != before:
		fail("Selecting a force staff shows staff targets without a partial settlement")
		return
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	if (
		view.visible
		or not scene.unit_panel.visible
		or battle.snapshot() != before
		or draws != before_draws
	):
		fail("Layered Back cancels a force staff without durability/action/XP/RNG changes")
		return
	staff.pressed.emit()
	view.find_child("Staff_0", true, false).pressed.emit()
	scene._show_cell(Vector2i(8, 11))
	await process_frame
	var feedback: Control = scene.action_feedback
	feedback.set_process(false)
	if (
		view.visible
		or not scene.busy
		or feedback.current_step.get("kind") != "message"
		or feedback.current_step.get("text") != battle.unit(0)["name"]
		or feedback.current_step.get("secondLine") != "能力提升"
	):
		fail("Force staff starts with the target-name and yellow ability message, without a circle")
		return
	var committed: Dictionary = battle.snapshot()
	if battle.unit(0)["hp"] != 30 or battle.unit(9)["action"] != 2 or draws != before_draws:
		fail("The map confirmation must commit only the force-staff action")
		return
	var steps: Array[String] = []
	for tick: int in range(150):
		var step: Dictionary = feedback.current_step
		if step.get("kind") == "healing":
			fail("Force staff feedback must never show a healing circle")
			return
		var label: String = str(step.get("text", step.get("kind", "")))
		if steps.is_empty() or steps[-1] != label:
			steps.append(label)
		if step.get("kind") == "summary":
			feedback.go_back()
		else:
			feedback.advance()
		if not feedback.playing:
			break
	await process_frame
	if (
		scene.busy
		or feedback.visible
		or battle.snapshot() != committed
		or steps != [battle.unit(0)["name"], "summary", "力之杖消失"]
	):
		fail(
			(
				"Ability message, XP and expiry must finish in order without a second settlement: "
				+ str(steps)
			)
		)
		return
	scene.queue_free()
	await process_frame
	print("PASS staff buffs UI: entry, Back, direct target, ability/XP/expiry, no circle/replay")
	quit(0)


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _roll(_limit: int) -> int:
	draws += 1
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
