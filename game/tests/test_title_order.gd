extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var title: Control = scene.title_screen
	var continuations: Array = []
	title.continue_game.connect(func() -> void: continuations.append(true))
	title.prologue.hide()
	title.refresh_continue(false)
	_key(title, KEY_ENTER)
	if _label(title) != "开始游戏":
		fail("A title without temporary progress must default to New Game")
		return
	var order: Array[String] = ["开始游戏", "读取进度", "读取存档", "游戏设置", "游戏帮助"]
	for expected: String in order:
		if _label(title) != expected:
			fail("Title entries must follow the requested clockwise cycle: " + expected)
			return
		if expected == "读取进度":
			_key(title, KEY_ENTER)
			if not continuations.is_empty() or _label(title) != expected:
				fail(
					"An unavailable temporary-progress entry cannot activate or leave the selector"
				)
				return
		_key(title, KEY_RIGHT)
	if _label(title) != "开始游戏":
		fail("The title cycle must wrap from Help to New Game")
		return
	_key(title, KEY_LEFT)
	if _label(title) != "游戏帮助":
		fail("The reverse title cycle must wrap from New Game to Help")
		return
	title.refresh_continue(true)
	_key(title, KEY_ENTER)
	if _label(title) != "读取进度":
		fail("A title with temporary progress must default to Continue")
		return
	_key(title, KEY_RIGHT)
	if _label(title) != "读取存档":
		fail("Named saves must follow temporary continuation")
		return
	scene.queue_free()
	await process_frame
	print("PASS title cycle: new/continue/named/settings/help, reverse wrap and contextual default")
	quit(0)


func _label(title: Control) -> String:
	for child: Node in title.options.get_children():
		if child is Button and child.visible and not child.text.is_empty():
			return child.text
	return ""


func _key(title: Control, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	title.handle_key(event)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
