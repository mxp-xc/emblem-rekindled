extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://features/tactical_map/map_view.gd")
	if script == null:
		quit(1)
		return
	var view: RefCounted = script.new()
	view.configure(Vector2i(20, 25), Vector2(720, 720))
	view.focus_cell(Vector2i(8, 11))
	if view.cell_at(Vector2(360, 360)) != Vector2i(8, 11):
		push_error("Non-origin focus must select the original cell")
		quit(1)
		return
	view.begin_pointer(Vector2(360, 360), 0)
	view.drag_pointer(Vector2(510, 360), 0)
	if view.end_pointer(Vector2(510, 360), 0) != Vector2i(-1, -1):
		push_error("Drag release must not select a cell")
		quit(1)
		return
	var before: Vector2 = view.world_at(Vector2(200, 200))
	view.zoom_at(4.0, Vector2(200, 200))
	if not view.world_at(Vector2(200, 200)).is_equal_approx(before):
		push_error("Zoom must preserve its anchor")
		quit(1)
		return
	view.begin_pointer(Vector2(300, 300), 4)
	if view.end_pointer(Vector2(300, 300), 5) != Vector2i(-1, -1):
		push_error("Another finger must not end the active gesture")
		quit(1)
		return
	view.cancel_pointer()
	if view.end_pointer(Vector2(300, 300), 4) != Vector2i(-1, -1):
		push_error("Canceled gesture must not select")
		quit(1)
		return
	print("PASS map input: non-origin selection, drag, zoom, touch identity, cancel")
	quit(0)
