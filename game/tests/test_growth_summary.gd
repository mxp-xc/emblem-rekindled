extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(scene.content)
	scene.resume_battle(battle)
	battle.share_experience = true
	battle.full_growth = true
	battle.complete_event("level_tutorial")
	var state: Dictionary = battle.snapshot()
	for unit: Dictionary in state["units"]:
		if unit["id"] in [0, 9]:
			unit["experience"] = 99
	if not battle.restore_snapshot(state)["ok"]:
		fail("Prepare actual two-member level-up")
		return
	var result: Dictionary = battle.heal_unit(9, 0, battle.unit(9)["inventory"][0]["id"])
	var settled: Dictionary = battle.snapshot()
	scene._present_player_action(result)
	await process_frame
	var feedback: Control = scene.action_feedback
	feedback.set_process(false)
	for tick: int in range(100):
		if feedback.current_step.get("kind") == "summary":
			break
		feedback.advance()
	var summary: Control = feedback.summary
	if feedback.current_step.get("kind") != "summary" or summary.get("_rows").size() != 2:
		fail("All earned XP and upgrades must share one summary")
		return
	var center: Vector2 = scene.map.view.center
	await process_frame
	if summary.get("_scroll").size.y < 96:
		fail("A short result list must show every recipient without scrolling")
		return
	for tick: int in range(200):
		feedback.advance()
	if not scene.busy or not summary.visible or battle.snapshot() != settled:
		fail("Summary must wait for one confirmation without replaying rewards")
		return
	summary.find_child("GrowthUnit_0", true, false).pressed.emit()
	if (
		summary.selected_index != 1
		or not summary.get("_details").text.contains(battle.unit(0)["name"])
	):
		fail("Selecting another row must show that person's complete growth details")
		return
	if summary.get("_attributes").get_child_count() != 8 or scene.map.view.center != center:
		fail("Eight attributes display together; selecting recipients must not move the camera")
		return
	for label: Label in summary.get("_attributes").get_children():
		if not label.text.contains("→"):
			fail("Every attribute must display its before and after value immediately")
			return
	for viewport: Vector2i in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		root.size = viewport
		await process_frame
		var area: Rect2 = feedback.get("_content_area")
		if not area.encloses(summary.panel.get_global_rect()):
			fail("Summary must remain within the actual map area after rotation")
			return
	var confirm: Button = summary.find_child("GrowthConfirm", true, false)
	confirm.pressed.emit()
	confirm.pressed.emit()
	await process_frame
	if scene.busy or feedback.visible or battle.snapshot() != settled:
		fail("One confirmation must dismiss the entire result and preserve committed state")
		return
	var rows: Array = []
	var sample: Dictionary = result["rewards"]["experience"]
	var queue: Array = load("res://features/battle/reward_timeline.gd").sequence(
		result, settled["units"], scene.content["interface"], true
	)
	for index: int in range(14):
		var row: Dictionary = queue[0]["rows"][0].duplicate(true)
		row["unit"] = index
		row["levelBefore"] = 19
		row["levelAfter"] = 20
		rows.append(row)
	root.size = Vector2i(1280, 720)
	await process_frame
	scene.map.show_overview()
	feedback.show()
	summary.present(rows)
	await process_frame
	await process_frame
	var line: Control = summary.find_child("GrowthUnit_0", true, false).get_child(0)
	for index: int in [1, 2, 3]:
		var label: Label = line.get_child(index)
		var width: float = (
			label
			. get_theme_font("font")
			. get_string_size(
				label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")
			)
			. x
		)
		if width > label.size.x:
			fail("Landscape overview must show complete level, XP and growth values: " + label.text)
			return
	for index: int in range(13):
		summary.handle_wheel(1)
	await process_frame
	await process_frame
	if summary.selected_index != 13 or summary.get("_scroll").scroll_vertical <= 0:
		fail("Long result lists must follow the selected person and keep confirmation reachable")
		return
	if sample["amount"] != 12:
		fail("Summary construction must not alter source awards")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS growth summary: combined results, immediate details, rotation, scrolling, once-only confirm"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
