extends "res://tests/test_m10_feedback.gd"


func run() -> void:
	root.size = Vector2i(1280, 720)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.resume_battle(_scene.battle)
	var actors: Array = _actors()
	var shared: Array = []
	for actor: Dictionary in actors.slice(1, 6):
		shared.append(
			{
				"unit": actor["id"],
				"before": 0,
				"after": 8,
				"amount": 8,
				"level": actor["level"],
				"growth": {}
			}
		)
	var result: Dictionary = {
		"rewards":
		{
			"experience":
			{
				"unit": 0,
				"before": 99,
				"after": 7,
				"amount": 8,
				"level": 10,
				"growth": {"strength": 1},
				"promotion": _promotion(),
				"shared": shared
			}
		}
	}
	var committed: Dictionary = _scene.battle.snapshot()
	var view: Control = _scene.action_feedback
	_scene.busy = true
	view.play(result, actors, true, true)
	view.set_process(false)
	for frame: int in range(8):
		await process_frame
	var summary: Control = view.summary
	var scroll: ScrollContainer = summary.get("_scroll")
	var row: Control = summary.find_child("GrowthUnit_0", true, false)
	var before: float = row.get_global_rect().position.y
	var start: Vector2 = scroll.get_global_rect().get_center()
	await _drag(start, start - Vector2(0, 180))
	if not _expect(
		row.get_global_rect().position.y < before - 100,
		(
			"Real ScreenTouch/ScreenDrag through Main must move summary contents: before=%s after=%s"
			% [before, row.get_global_rect().position.y]
		)
	):
		return
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var bar_point: Vector2 = bar.get_global_rect().get_center()
	before = row.get_global_rect().position.y
	await _drag(bar_point, bar_point - Vector2(0, 200))
	if not _expect(
		row.get_global_rect().position.y > before + 100,
		"Touch scrollbar returns contents toward the top"
	):
		return
	await _drag(bar_point, bar_point + Vector2(0, 200))
	var last: Control = summary.get("_attributes").get_child(7)
	if not _expect(
		scroll.get_global_rect().encloses(last.get_global_rect()),
		"Touch scrollbar reaches the complete last attribute"
	):
		return
	var confirm: Button = summary.get("_confirm")
	await _drag(scroll.get_global_rect().get_center(), confirm.get_global_rect().get_center())
	if not _expect(
		view.playing and summary.selected_index == 0,
		"A content drag ending on confirmation cannot confirm or select"
	):
		return
	var other: Control = summary.get("_buttons")[1]
	await _drag(
		scroll.get_global_rect().position + Vector2(80, 10), other.get_global_rect().get_center()
	)
	if not _expect(
		summary.selected_index == 0 and view.playing,
		"A drag ending on another recipient cannot activate that button"
	):
		return
	await _drag(
		bar.get_global_rect().get_center(), bar.get_global_rect().get_center() - Vector2(0, 240)
	)
	await _touch(other.get_global_rect().get_center(), true)
	await _touch(other.get_global_rect().get_center(), false, true)
	if not _expect(summary.selected_index == 0, "Canceled touch cannot select a recipient"):
		return
	await _touch(other.get_global_rect().get_center(), true)
	await _touch(other.get_global_rect().get_center(), false)
	if not _expect(
		summary.selected_index == 1,
		"A fresh tap still selects a recipient after a canceled gesture"
	):
		return
	await _key(KEY_UP)
	for frame: int in range(8):
		await process_frame
	if not _expect(
		summary.selected_index == 0, "Keyboard selection retains its recipient contract"
	):
		return
	await _wheel(other.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	if not _expect(
		summary.selected_index == 1, "Wheel over recipients changes recipient without activating it"
	):
		return
	await _wheel(row.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
	for frame: int in range(8):
		await process_frame
	before = row.get_global_rect().position.y
	var before_scroll: int = scroll.scroll_vertical
	await _wheel(scroll.get_global_rect().end - Vector2(40, 30), MOUSE_BUTTON_WHEEL_DOWN)
	var deadline: int = Time.get_ticks_msec() + 2000
	while row.get_global_rect().position.y >= before and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(
		summary.selected_index == 0 and row.get_global_rect().position.y < before,
		(
			"Wheel over details must scroll without changing the recipient: "
			+ str(
				{
					"selected": summary.selected_index,
					"before": before,
					"after": row.get_global_rect().position.y,
					"scrollBefore": before_scroll,
					"scrollAfter": scroll.scroll_vertical,
					"max": bar.max_value,
					"page": bar.page
				}
			)
		)
	):
		return
	start = scroll.get_global_rect().get_center()
	await _touch(start, true)
	root.size = Vector2i(720, 1280)
	for frame: int in range(8):
		await process_frame
	await _touch(start, false)
	if not _expect(
		view.playing and summary.selected_index == 0,
		"Rotation cancels the old contact without selecting or confirming"
	):
		return
	root.size = Vector2i(1280, 720)
	for frame: int in range(8):
		await process_frame
	before = row.get_global_rect().position.y
	start = scroll.get_global_rect().get_center()
	await _drag(start, start - Vector2(0, 180))
	if not _expect(
		row.get_global_rect().position.y < before,
		"A new gesture scrolls normally after rotation cancellation"
	):
		return
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	if not _expect(
		not view.playing and _scene.battle.snapshot() == committed,
		"Confirmation dismisses once without replaying gameplay"
	):
		return
	if not _expect(
		summary.selected_index == 0 and _scene.battle.snapshot() == committed,
		"Dragging must neither select a different recipient nor mutate gameplay"
	):
		return
	_scene.queue_free()
	await process_frame
	print(
		"PASS growth input: touch/body/bar, cancel/rotation, wheel targets, selection and one confirm"
	)
	quit(0)


func _drag(start: Vector2, finish: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = start
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	for step: int in range(1, 11):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = start.lerp(finish, step / 10.0)
		drag.relative = (finish - start) / 10
		Input.parse_input_event(drag)
		await process_frame
	touch.position = finish
	touch.pressed = false
	Input.parse_input_event(touch)
	await process_frame


func _touch(point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	await process_frame


func _wheel(point: Vector2, button: MouseButton) -> void:
	await create_timer(0.25).timeout
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
