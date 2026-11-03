extends SceneTree

var _scene: Control


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.title_screen.hide()
	_scene.map.show()
	var before: Dictionary = {}
	for actor: Dictionary in _scene.battle.snapshot()["units"]:
		if actor["faction"] == 2 and actor["visible"] and actor["hp"] > 0:
			before = actor.duplicate(true)
			break
	if not _expect(not before.is_empty(), "A visible enemy is available for the event"):
		return
	var state: Dictionary = _scene.battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == before["id"]:
			actor["visible"] = false
			actor["flags"] |= 1
	if not _expect(_scene.battle.restore_snapshot(state)["ok"], "Restore committed withdrawal"):
		return
	var committed: Dictionary = _scene.battle.snapshot()
	# An earlier event may already have projected the committed state before this one.
	_scene.map.set_units(committed["units"])
	var dialogue_steps: Array = []
	for step: Dictionary in _scene.content["story"]["sequences"]["opening"]:
		if step["kind"] == "dialogue":
			dialogue_steps.append(step.duplicate(true))
			if dialogue_steps.size() == 2:
				break
	if not _expect(dialogue_steps.size() == 2, "Two real dialogue steps are available"):
		return
	_scene.content["story"]["sequences"]["test_withdrawal"] = dialogue_steps
	_scene.busy = true
	_scene.map.selection_enabled = false
	_scene._present_phase_events(
		[{"kind": "withdrawal", "unit": before, "sequence": "test_withdrawal"}]
	)
	var shown_dialogues: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 12000
	while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
		if _scene.story_player.dialogue.visible:
			shown_dialogues[_scene.story_player.current_text_index] = true
			if not _expect(_shown(before["id"]), "Withdrawing unit stays visible during dialogue"):
				return
			if not _expect(_scene.busy and not _scene.map.selection_enabled, "Input stays locked"):
				return
			_scene.story_player.advance()
		if not _expect(
			_scene.battle.snapshot() == committed, "Presentation preserves committed state"
		):
			return
		await process_frame
	if not _expect(
		shown_dialogues.size() == 2 and not _scene.story_player.visible,
		"Both withdrawal dialogues finish"
	):
		return
	if not _expect(not _shown(before["id"]), "Unit is hidden after the dialogue"):
		return
	_scene.queue_free()
	await process_frame
	print("PASS withdrawal presentation preserves unit through dialogue and hides afterward")
	quit(0)


func _shown(identity: int) -> bool:
	for actor: Dictionary in _scene.map.visible_units():
		if actor["id"] == identity:
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
