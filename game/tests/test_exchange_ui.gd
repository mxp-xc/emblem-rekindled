extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.find_child("ExchangeScreen", true, false) == null:
		fail("Trade must use the original map chooser and full-screen stacked inventories")
		return
	scene.resume_battle(scene.battle)
	scene._show_unit_menu(Vector2i(8, 11))
	scene._unit_intent("trade", {})
	if not scene.exchange_screen.visible or scene.exchange_screen.page != "targets":
		fail("Trade must first choose an adjacent unit on the map")
		return
	if scene.map.movement.size() != 4 or not scene.map.movement.has(Vector2i(8, 10)):
		fail("Trade must visibly mark all four adjacent exchange squares")
		return
	scene._handle_back()
	if scene.battle.movement_committed(0) or not scene.unit_panel.visible:
		fail("Back from target selection must return to actions without committing a move")
		return
	if not scene.map.movement.is_empty():
		fail("Back from exchange targeting must clear its range")
		return
	scene._unit_intent("trade", {})
	scene._show_cell(Vector2i(9, 11))
	var view: Control = scene.exchange_screen
	if view.page != "inventories" or not scene.battle.movement_committed(0):
		fail("Entering the full-screen two-inventory view must lock move cancellation")
		return
	if view.size != scene.size:
		fail("The exchange view must cover the screen, retaining the original stacked layout")
		return
	view.find_child("Owner0_Item9", true, false).pressed.emit()
	if not view.source_locked:
		fail("The first item confirmation must only lock a source")
		return
	if root.gui_get_focus_owner().name != "TransferHere":
		fail(
			"The original first confirmation must focus the receiving empty slot before held items"
		)
		return
	scene._handle_back()
	if view.source_locked or not view.visible:
		fail("The first Back must cancel the source selection and retain both inventories")
		return
	scene._handle_back()
	if view.visible or not scene.unit_panel.visible or scene.battle.unit(0)["action"] != 0:
		fail("The next Back must return to available actions")
		return
	scene._handle_back()
	if (
		scene.battle.unit(0)["action"] != 2
		or scene.selected_unit != -1
		or not scene.battle.can_save()
	):
		fail("Back after visiting exchange must finish the initiating action")
		return
	var fresh: RefCounted = load("res://gameplay/battle_state.gd").new(
		scene.content, func(_limit: int) -> int: return 0
	)
	scene.resume_battle(fresh)
	scene._show_unit_menu(Vector2i(8, 11))
	scene._unit_intent("trade", {})
	scene._show_cell(Vector2i(9, 11))
	var sword: String = fresh.unit(0)["inventory"][0]["id"]
	var staff: String = fresh.unit(9)["inventory"][0]["id"]
	view.find_child("Owner0_Item9", true, false).pressed.emit()
	view.find_child("Owner1_Item53", true, false).pressed.emit()
	if (
		view.source_locked
		or fresh.unit(0)["inventory"][0]["id"] != staff
		or fresh.unit(9)["inventory"][0]["id"] != sword
		or fresh.unit(0)["action"] != 0
	):
		fail("Second confirmation must swap the held instances and keep the action available")
		return
	scene._handle_back()
	scene._handle_back()
	if fresh.unit(0)["action"] != 2 or not fresh.can_save():
		fail("Leaving a completed swap must finish at the same stable boundary")
		return
	scene.queue_free()
	await process_frame
	print("PASS exchange UI: map target, stacked inventories, source cancel, action return/finish")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
