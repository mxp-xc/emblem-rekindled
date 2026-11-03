extends SceneTree

const Matrix = preload("res://tests/test_m9_content.gd")
const Flow = preload("res://tests/test_m9_flow.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
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
	for kind: String in ["withdrawal", "reinforcements"]:
		if not await _case(kind):
			return
	_scene.queue_free()
	await process_frame
	print("PASS phase events preserve future births until their turn")
	quit(0)


# A controlled ordering case exercises a real m9 clone wave. It does not
# claim that the combined event states arise naturally in m15.
func _case(kind: String) -> bool:
	var opened: Dictionary = Flow.prepare_boundary(Matrix.CONTEXTS[1], 2)
	if not _expect(opened["ok"], "Open real m9 clone boundary"):
		return false
	_scene._adopt_content(opened["content"], opened["battle"])
	_scene.resume_battle(opened["battle"])
	var before: Dictionary = _scene.battle.snapshot()
	var advanced: Dictionary = Rounds.advance(_scene.battle)
	if not _expect(advanced["ok"], "Commit real clone wave"):
		return false
	var clone_event: Dictionary = {}
	for event: Dictionary in advanced["events"]:
		if event["kind"] == "clones" and not event["births"].is_empty():
			clone_event = event
	if not _expect(not clone_event.is_empty(), "Actual clone arrivals are present"):
		return false
	var actor: Dictionary = {}
	for value: Dictionary in before["units"]:
		if value["faction"] == 2 and value["visible"] and value["id"] not in [31, 32]:
			actor = value.duplicate(true)
			break
	if not _expect(not actor.is_empty(), "An existing event unit is available"):
		return false
	var future: Dictionary = {}
	for value: Dictionary in before["units"]:
		if value["faction"] == 2 and value["visible"] and value["id"] != actor["id"]:
			future = value.duplicate(true)
			break
	if not _expect(not future.is_empty(), "A later reinforcement unit is available"):
		return false
	var committed: Dictionary = _scene.battle.snapshot()
	if kind == "withdrawal":
		for value: Dictionary in committed["units"]:
			if value["id"] == actor["id"]:
				value["visible"] = false
				value["flags"] |= 1
		if not _expect(_scene.battle.restore_snapshot(committed)["ok"], "Commit withdrawal"):
			return false
		committed = _scene.battle.snapshot()
	var dialogue: Dictionary = {}
	for step: Dictionary in _scene.content["story"]["sequences"]["victory"]:
		if step["kind"] == "dialogue":
			dialogue = step.duplicate(true)
			break
	if not _expect(not dialogue.is_empty(), "A dialogue is available"):
		return false
	_scene.content["story"]["sequences"]["test_phase_order"] = [dialogue]
	_scene.content["_storyFragment"]["sequences"]["test_phase_order"] = [dialogue]
	_scene.map.set_units(before["units"])
	_scene.busy = true
	_scene.map.selection_enabled = false
	var first: Dictionary = {"kind": "withdrawal", "unit": actor, "sequence": "test_phase_order"}
	if kind == "reinforcements":
		first = {"kind": "reinforcements", "arrivals": [], "sequence": "test_phase_order"}
	var cell := Vector2i(future["x"], future["y"])
	var later: Dictionary = {
		"kind": "reinforcements",
		"arrivals": [{"unit": future["id"], "from": cell, "to": cell, "revealed": true}],
		"sequence": ""
	}
	_scene._present_phase_events([first, clone_event, later])
	var deadline: int = Time.get_ticks_msec() + 12000
	var saw_dialogue: bool = false
	while _scene.story_player.visible and Time.get_ticks_msec() < deadline:
		if _scene.story_player.dialogue.visible:
			saw_dialogue = true
			for birth: Dictionary in clone_event["births"]:
				if not _expect(
					not _shown(birth["unit"]), kind + " cannot reveal later clone early"
				):
					return false
			if not _expect(not _shown(future["id"]), "Later reinforcement stays hidden"):
				return false
			if (
				kind == "withdrawal"
				and not _expect(_shown(actor["id"]), "Withdrawal remains visible")
			):
				return false
			if not _expect(
				_scene.busy and not _scene.map.selection_enabled, "Input remains locked"
			):
				return false
			_scene.story_player.advance()
		if not _expect(_scene.battle.snapshot() == committed, "Playback cannot change battle"):
			return false
		await process_frame
	if not _expect(saw_dialogue, kind + " dialogue was shown"):
		return false
	# Clone arrivals can continue after the first dialogue; wait for their playback.
	while Time.get_ticks_msec() < deadline:
		var done: bool = _shown(future["id"])
		for birth: Dictionary in clone_event["births"]:
			if birth["revealed"] and not _shown(birth["unit"]):
				done = false
		if done:
			break
		await process_frame
	for birth: Dictionary in clone_event["births"]:
		if (
			birth["revealed"]
			and not _expect(_shown(birth["unit"]), "Clone appears after its event")
		):
			return false
	if not _expect(_shown(future["id"]), "Later reinforcement appears at its event"):
		return false
	return _expect(kind != "withdrawal" or not _shown(actor["id"]), "Withdrawal ends hidden")


func _shown(identity: int) -> bool:
	for actor: Dictionary in _scene.map.visible_units():
		if actor["id"] == identity:
			return true
	return false


func _expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(1)
	return value
