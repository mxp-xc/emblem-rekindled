extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.get("action_feedback") == null:
		fail("Healing and committed rewards must play through the original map feedback layer")
		return
	scene.resume_battle(scene.battle)
	var herb: Dictionary = scene.battle.unit(0)["inventory"][1]
	var result: Dictionary = scene.battle.use_item(0, herb["id"])
	var settled: Dictionary = scene.battle.snapshot()
	scene._present_player_action(result)
	await process_frame
	var view: Control = scene.action_feedback
	view.set_process(false)
	if not scene.busy or view.current_step.get("text") != "没有生命损失，无法使用":
		fail("Full HP failure must show the source timed strip while map input is locked")
		return
	for code: int in [KEY_ENTER, KEY_DOWN]:
		await key(code)
		if not scene.busy or view.current_step.get("text") != "没有生命损失，无法使用":
			fail("Confirmation keys cannot accelerate an automatically timed reward step")
			return
	for tick: int in range(25):
		view.advance()
	await process_frame
	if scene.busy or scene.battle.snapshot() != settled or view.visible:
		fail("Failure must expire automatically without charge loss or a second settlement")
		return
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		scene.content, func(_limit: int) -> int: return 0
	)
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["hp"] = 20
		elif actor["id"] == 9:
			actor["experience"] = 95
	battle.restore_snapshot(state)
	scene.resume_battle(battle)
	result = battle.heal_unit(9, 0, battle.unit(9)["inventory"][0]["id"])
	settled = battle.snapshot()
	scene._present_player_action(result)
	await process_frame
	view.set_process(false)
	if view.current_step.get("kind") != "healing" or scene.map_hud.actor["hp"] != 20:
		fail("Committed healing must first display the injured target and source map circle")
		return
	view.advance()
	view.advance()
	if scene.map_hud.actor["hp"] != 22 or battle.snapshot() != settled:
		fail("Visible HP may advance by two, authoritative final HP must remain untouched")
		return
	var kinds: Array[String] = ["healing"]
	var checked_scroll_lock: bool = false
	for tick: int in range(500):
		if view.current_step.get("kind") == "summary":
			await key(KEY_ENTER)
		elif view.current_step.get("kind") == "tutorial":
			if scene.map_hud.visible:
				fail("The first XP tutorial must replace the bottom HUD, including staff rewards")
				return
			if not checked_scroll_lock:
				for viewport: Vector2i in [
					Vector2i(1280, 720), Vector2i(720, 1280), Vector2i(480, 720)
				]:
					root.size = viewport
					for frame: int in range(8):
						await process_frame
					var clip: Control = view.get("_tutorial_clip")
					if not view.get("_content_area").encloses(clip.get_global_rect()):
						fail("Tutorial two-line viewport stays inside map bounds after rotation")
						return
					var text: Label = view.get("_tutorial_text")
					var font: Font = text.get_theme_font("font")
					var font_size: int = text.get_theme_font_size("font_size")
					var factor: float = clip.size.x / 240.0
					for line: String in view.get("_tutorial_lines"):
						var line_width: float = (
							font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
						)
						if line_width + 4 * factor > clip.size.x:
							fail("Each paged tutorial line fits without hiding characters")
							return
					if (
						font.get_height(font_size) * 2 + text.get_theme_constant("line_spacing")
						> clip.size.y
					):
						fail("Both tutorial rows include the full font ascent and descent")
						return
				var row_before: int = view.get("_tutorial_row")
				for pressed: bool in [true, false]:
					var touch := InputEventScreenTouch.new()
					touch.position = view.get_global_rect().get_center()
					touch.pressed = pressed
					touch.canceled = not pressed
					Input.parse_input_event(touch)
					await process_frame
				if view.get("_tutorial_row") != row_before:
					fail("A canceled touch cannot advance the first-experience tutorial")
					return
				await key(KEY_ENTER)
				if view.get("_tutorial_row") != row_before + 1:
					fail("The active feedback owner must accept tutorial confirmation exactly once")
					return
				for press: int in range(20):
					view.go_back()
				if view.current_step.get("kind") != "tutorial":
					fail(
						"Rapid Back must not skip the source tutorial during its three-tick scroll"
					)
					return
				checked_scroll_lock = true
			await key([KEY_ESCAPE, KEY_DOWN, KEY_ENTER][tick % 3])
			view.set_process(false)
			view.advance()
		else:
			view.advance()
		var kind: String = view.current_step.get("kind", "")
		if not kind.is_empty() and kind != kinds[-1]:
			kinds.append(kind)
		if not view.playing:
			break
	await process_frame
	if kinds != ["healing", "summary", "tutorial"]:
		fail("Staff level-up must show healing, combined summary and one tutorial: " + str(kinds))
		return
	settled["events"]["level_tutorial"] = true
	if scene.busy or battle.snapshot() != settled or not battle.event_completed("level_tutorial"):
		fail("Finishing presentation must only mark tutorial read, never award HP/XP/growth again")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS action feedback: source timed failure, healing HP, reward order, Esc tutorial, no replay"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func key(code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	Input.parse_input_event(event)
	await process_frame
