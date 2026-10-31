extends SceneTree

var accepted: Array[int] = []
var backs: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var path: String = "res://features/menus/save_slot_screen.gd"
	if not FileAccess.file_exists(path):
		fail("Original saves need a horizontal four-record selector and one detail panel")
		return
	root.size = Vector2i(240, 320)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var screen: Control = load(path).new()
	scene.add_child(screen)
	screen.setup(scene.content)
	screen.accepted.connect(func(slot: int) -> void: accepted.append(slot))
	screen.back_requested.connect(func() -> void: backs += 1)
	var records: Array[Dictionary] = [
		{"status": "empty"},
		{"status": "empty"},
		{"status": "invalid"},
		{"status": "world", "description": "第1战\n皇都荒野\n2:07"}
	]
	screen.present("load", records)
	var factor: float = screen.size.x / 240.0
	if screen.selector_rect != Rect2(0, 130 * factor, screen.size.x, 19 * factor):
		fail("The original selector is a centered 19px horizontal row")
		return
	if screen.detail_rect != Rect2(0, 149 * factor, screen.size.x, 69 * factor):
		fail("The source details retain their 69px frame even for an empty record")
		return
	await _key(screen, KEY_ENTER)
	if not accepted.is_empty() or not screen.visible:
		fail("Reading an empty record must stay on the same source slot page")
		return
	await _key(screen, KEY_LEFT)
	await _key(screen, KEY_DOWN)
	if screen.slot != 3 or screen.get("_details").text != "第1战\n皇都荒野\n2:07":
		fail("Left wraps slot0 to slot3; vertical keys do not change the selected record")
		return
	await _key(screen, KEY_ENTER)
	if accepted != [3]:
		fail("Reading a populated slot emits directly without a second confirmation")
		return
	screen.present("save", records)
	await _key(screen, KEY_ENTER)
	if accepted != [3, 0] or screen.page != "slots":
		fail("Writing an empty selected slot needs no overwrite confirmation")
		return
	await _key(screen, KEY_LEFT)
	await _key(screen, KEY_ENTER)
	if screen.page != "overwrite" or accepted != [3, 0]:
		fail("A populated slot must wait on the original confirmation strip before overwrite")
		return
	screen.go_back()
	if screen.page != "slots" or screen.slot != 3 or backs != 0:
		fail("Back cancels overwrite and retains the source slot rather than skipping its layer")
		return
	await _key(screen, KEY_ENTER)
	await _key(screen, KEY_ENTER)
	if accepted != [3, 0, 3]:
		fail("The overwrite confirmation must commit only the explicitly selected slot")
		return
	screen.show_error("存档无法读取，原记录已保留。")
	if screen.page != "slots" or screen.slot != 3 or not screen.visible:
		fail("A storage failure must return to the same slot with a visible notice")
		return
	screen.go_back()
	if screen.visible or backs != 1:
		fail("Back from the slots requests only the caller's immediate parent layer")
		return
	scene.queue_free()
	await process_frame
	print(
		"PASS save slot UI: native geometry, horizontal wrap, empty read, overwrite and layered Back"
	)
	quit(0)


func _key(screen: Control, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	screen.handle_key(event)
	await process_frame


func fail(message: String) -> void:
	push_error(message)
	quit(1)
