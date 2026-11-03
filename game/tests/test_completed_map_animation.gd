extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const TacticalMap = preload("res://features/tactical_map/tactical_map.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json",
		"",
		{"new": true},
		func(_limit: int) -> int: return 0
	)
	if not opened["ok"]:
		fail("The chapter fixture must load")
		return
	var content: Dictionary = opened["content"].duplicate(true)
	var source: Dictionary = content["units"][0].duplicate(true)
	var animation: Dictionary = content["mapAnimations"]["units"][str(int(source["id"]))].duplicate(
		true
	)
	animation["idleSequence"] = [0, 0]
	animation["idleStepSeconds"] = 0.1
	content["units"] = []
	for id: int in range(3):
		var actor: Dictionary = source.duplicate(true)
		actor["id"] = id
		actor["action"] = 0 if id == 0 else 2
		actor["visible"] = id != 2
		content["units"].append(actor)
		var definition: Dictionary = animation.duplicate(true)
		if id != 1:
			definition["completedUsesActiveCycle"] = true
		content["mapAnimations"]["units"][str(id)] = definition
	var map: Control = TacticalMap.new()
	root.add_child(map)
	map.setup(content)
	map.set_process(false)
	map._process(0.11)
	if map.frame_indices[0] != 1 or map.frame_indices[1] != 0 or map.frame_indices[2] != 0:
		fail("Only the visible actionable unit advances")
		return
	content["units"][0]["action"] = 2
	map.set_units(content["units"])
	map._process(0.3)
	if map.frame_indices[0] != 1:
		fail("A completed active-cycle unit retains its last frame")
		return
	content["units"][0]["action"] = 0
	map.set_units(content["units"])
	map._process(0.01)
	if map.frame_indices[0] != 0:
		fail("Reactivation advances once when the original frame interval has elapsed")
		return
	var rebound: Dictionary = content.duplicate(true)
	rebound["units"][0]["action"] = 2
	rebound["mapAnimations"]["units"]["0"].erase("completedUsesActiveCycle")
	var ids: Array[int] = [0]
	if not map.rebind_units(rebound, ids)["ok"]:
		fail("The changed unit's animation must rebind")
		return
	map._process(0.11)
	if map.frame_indices[0] != 0:
		fail("A rebound ordinary completed unit stays on its completed frame")
		return
	rebound["units"][0]["action"] = 0
	map.set_units(rebound["units"])
	map._process(0.11)
	if map.frame_indices[0] != 1:
		fail("An ordinary unit resumes its idle cycle when it can act")
		return
	map.queue_free()
	print("PASS completed map animation: retained frame, reactivation, visibility and rebind")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
