extends SceneTree

var _scene: Control
var _draws: int = 0
var _before: Dictionary


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.title_screen.prologue.hide()
	_scene._set_menu_visible(true)
	_scene.menu_layer.show_page("settings")
	_scene.menu_layer.find_child("GameSpeed", true, false).pressed.emit()
	_scene.menu_layer.find_child("Speed_32", true, false).pressed.emit()
	_scene._set_menu_visible(false)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(_scene.content, _roll)
	battle.complete_event("level_tutorial")
	_before = battle.snapshot()
	for actor: Dictionary in _before["units"]:
		if actor["id"] == 9:
			actor["inventory"] = [
				{"id": "advanced-staff:repair", "templateId": 57, "durability": 4},
				{"id": "advanced-staff:teleport", "templateId": 58, "durability": 15}
			]
			actor["equippedInstanceId"] = ""
			actor["experience"] = 0
		elif actor["id"] == 0:
			actor["action"] = 2
			actor["inventory"].append(
				{"id": "advanced-staff:full-shield", "templateId": 65, "durability": 4}
			)
	if not await _repair(battle) or not await _teleport(battle):
		return
	_scene.queue_free()
	await process_frame
	print("PASS repair/teleport Main selection, cancellation, rotation and single commit")
	quit(0)


func _prepare(battle: RefCounted) -> bool:
	if not _expect(
		battle.restore_snapshot(_before)["ok"], "Controlled actual m0 staff state validates"
	):
		return false
	_scene.resume_battle(battle)
	_scene.selected_unit = 9
	_draws = 0
	_scene._unit_intent("heal", {})
	return true


func _repair(battle: RefCounted) -> bool:
	if not _prepare(battle):
		return false
	var view: Control = _scene.target_selection
	view.find_child("Staff_0", true, false).pressed.emit()
	view.select_target(0)
	if not _expect(
		view.page == "repair_items" and battle.snapshot() == _before and _draws == 0,
		"Choosing full-HP acted ally for repair opens inventory without committing"
	):
		return false
	var shield_index: int = -1
	for index: int in range(battle.unit(0)["inventory"].size()):
		if battle.unit(0)["inventory"][index]["id"] == "advanced-staff:full-shield":
			shield_index = index
	if not _expect(shield_index >= 0, "Full passive shield remains in complete repair list"):
		return false
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(540, 960)]:
		root.size = dimensions
		for frame: int in range(8):
			await process_frame
		if not _expect(
			view.page == "repair_items" and battle.snapshot() == _before,
			"Rotation preserves repair selection and uncommitted inventory"
		):
			return false
	await _key(KEY_ESCAPE)
	if not _expect(
		view.page == "targets" and view.target_id == 0 and battle.snapshot() == _before,
		"Repair second Back restores selected ally without any charge or XP"
	):
		return false
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	if not _expect(not view.visible and _scene.unit_panel.visible, "Staff Back returns to actions"):
		return false
	_scene._unit_intent("heal", {})
	view.find_child("Staff_0", true, false).pressed.emit()
	view.select_target(0)
	var button: Button = view.find_child("RepairItem_%d" % shield_index, true, false)
	button.pressed.emit()
	button.pressed.emit()
	var committed: Dictionary = battle.snapshot()
	if not _expect(
		(
			_scene.busy
			and not _scene._save_battle()
			and battle.unit(9)["action"] == 2
			and battle.unit(9)["experience"] == 12
			and battle.unit(9)["inventory"][0]["durability"] == 3
			and battle.unit(0)["action"] == 2
			and battle.unit(0)["inventory"][shield_index]["durability"] == 4
			and _draws == 0
		),
		"Repairing a full shield commits once, keeps target action, and locks saving"
	):
		return false
	return await _finish(committed)


func _teleport(battle: RefCounted) -> bool:
	if not _prepare(battle):
		return false
	var view: Control = _scene.target_selection
	view.find_child("Staff_1", true, false).pressed.emit()
	view.select_target(0)
	if not _expect(
		view.page == "destination" and battle.snapshot() == _before,
		"Teleport selects an acted ally before choosing the destination"
	):
		return false
	var original: Vector2i = Vector2i(battle.unit(0)["x"], battle.unit(0)["y"])
	var inventory_before: Array = battle.unit(0)["inventory"].duplicate(true)
	var caster: Vector2i = Vector2i(battle.unit(9)["x"], battle.unit(9)["y"])
	_scene._show_cell(caster)
	view.find_child("Confirm", true, false).pressed.emit()
	if not _expect(
		view.page == "destination" and battle.snapshot() == _before,
		"Occupied teleport destination refuses without cost"
	):
		return false
	await _key(KEY_ESCAPE)
	if not _expect(
		view.page == "targets" and _scene.map.selected == original and battle.snapshot() == _before,
		"Destination Back restores the target and its original map cell"
	):
		return false
	view.select_target(0)
	var far: Vector2i = original
	for cell: Vector2i in battle.teleport_field(9, 0, "advanced-staff:teleport"):
		if absi(cell.x - original.x) + absi(cell.y - original.y) > 10:
			far = cell
			break
	if not _expect(far != original, "Actual map has a distant legal teleport destination"):
		return false
	_scene._show_cell(far)
	root.size = Vector2i(720, 1280)
	for frame: int in range(8):
		await process_frame
	if not _expect(
		view.page == "destination" and _scene.map.selected == far and battle.snapshot() == _before,
		"Rotation preserves a distant uncommitted teleport destination"
	):
		return false
	view.find_child("Confirm", true, false).pressed.emit()
	view.find_child("Confirm", true, false).pressed.emit()
	var committed: Dictionary = battle.snapshot()
	_scene._show_cell(caster)
	await _key(KEY_ESCAPE)
	if not _expect(
		(
			_scene.busy
			and not _scene._save_battle()
			and battle.snapshot() == committed
			and Vector2i(battle.unit(0)["x"], battle.unit(0)["y"]) == far
			and battle.unit(0)["action"] == 2
			and battle.unit(0)["inventory"] == inventory_before
			and battle.unit(9)["action"] == 2
			and battle.unit(9)["experience"] == 12
			and battle.unit(9)["inventory"][1]["durability"] == 14
			and _draws == 0
		),
		"Teleport commits once and preserves the target's completed action and inventory"
	):
		return false
	return await _finish(committed)


func _finish(committed: Dictionary) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while _scene.busy and Time.get_ticks_msec() < deadline:
		if _scene.action_feedback.current_step.get("kind") == "summary":
			_scene.action_feedback.go_back()
		await process_frame
	if _scene.busy or _scene.battle.snapshot() != committed:
		print(
			"ADVANCED_STAFF_COMPLETION ",
			{
				"busy": _scene.busy,
				"step": _scene.action_feedback.current_step,
				"eventsBefore": committed["events"],
				"eventsAfter": _scene.battle.snapshot()["events"]
			}
		)
	return _expect(
		not _scene.busy and _scene.battle.snapshot() == committed,
		"Full staff effect and reward feedback unlock without replaying any business result"
	)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(1)
	return value
