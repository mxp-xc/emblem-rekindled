extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.find_child("ItemActions", true, false) == null:
		fail("The original item operation flow must be connected to the battlefield")
		return
	scene.resume_battle(scene.battle)
	scene._show_unit_menu(Vector2i(8, 11))
	scene.get_node("UnitStatus/Status/Actions/Inventory").pressed.emit()
	var view: Control = scene.item_actions
	if (
		not view.visible
		or view.page != "operations"
		or view.find_child("Equip", true, false) == null
	):
		fail("Items must first present the filtered use/equip/discard operation menu")
		return
	view.find_child("Equip", true, false).pressed.emit()
	var weapon: Button = view.find_child("Item_9", true, false)
	if weapon == null:
		fail("The already-equipped weapon must remain an equipment candidate")
		return
	weapon.pressed.emit()
	weapon.pressed.emit()
	if view.page != "confirm":
		fail("Selecting equipment must show a confirmation before mutation")
		return
	await _escape()
	if view.page != "items":
		fail("Back from confirmation must retain the item list")
		return
	await _escape()
	if view.page != "operations":
		fail("Back from the item list must return to operation selection")
		return
	view.find_child("Use", true, false).pressed.emit()
	view.find_child("Item_60", true, false).pressed.emit()
	view.find_child("Item_60", true, false).pressed.emit()
	var before: Dictionary = scene.battle.snapshot()
	await _escape()
	if scene.battle.snapshot() != before or view.page != "items":
		fail("Cancelling use must not consume HP, durability or action")
		return
	if root.gui_get_focus_owner().name != "Item_60":
		fail("Back from use confirmation must preserve the selected consumable")
		return
	view.find_child("Item_60", true, false).pressed.emit()
	var confirm := InputEventKey.new()
	confirm.keycode = KEY_ENTER
	confirm.pressed = true
	Input.parse_input_event(confirm)
	await process_frame
	while scene.busy:
		await process_frame
	var actor: Dictionary = scene.battle.unit(0)
	if (
		actor["action"] != 2
		or actor["hp"] != actor["maxHp"]
		or actor["inventory"][1]["durability"] != 3
	):
		fail("The original full-HP use failure ends the action without consuming a charge")
		return
	if view.visible or scene.action_feedback.playing:
		fail("Full-HP use must return to the map after the timed source failure notice")
		return
	var fresh: RefCounted = load("res://gameplay/battle_state.gd").new(
		scene.content, func(_limit: int) -> int: return 0
	)
	scene.resume_battle(fresh)
	scene._show_cell(Vector2i(8, 11))
	scene._show_cell(Vector2i(8, 12))
	await create_timer(0.3).timeout
	scene._unit_intent("inventory", {})
	view.find_child("Discard", true, false).pressed.emit()
	view.find_child("Item_9", true, false).pressed.emit()
	view.find_child("Item_9", true, false).pressed.emit()
	Input.parse_input_event(confirm)
	await process_frame
	if (
		view.page != "items"
		or fresh.unit(0)["inventory"].size() != 1
		or fresh.unit(0)["action"] != 0
	):
		fail("Confirmed discard must retain its item list and available action")
		return
	await _escape()
	await _escape()
	await _escape()
	if fresh.unit(0)["y"] != 11 or fresh.unit(0)["inventory"].size() != 1:
		fail("Back after discard must undo the move without restoring the discarded item")
		return
	scene._show_unit_menu(Vector2i(8, 11))
	scene._unit_intent("inventory", {})
	view.find_child("Discard", true, false).pressed.emit()
	view.find_child("Item_60", true, false).pressed.emit()
	view.find_child("Item_60", true, false).pressed.emit()
	Input.parse_input_event(confirm)
	await process_frame
	if (
		view.visible
		or not scene.unit_panel.visible
		or scene.get_node("UnitStatus/Status/Actions/Inventory").visible
	):
		fail("Dropping the last item must return to actions and remove the item operation")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS item UI: operation/list/confirm order, equipped candidate, layered Back, full-HP use"
	)
	quit(0)


func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
