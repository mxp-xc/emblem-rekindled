extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle_script: Script = load("res://gameplay/battle_state.gd")
	var battle: RefCounted = battle_script.new(content)
	var store: RefCounted = load("res://persistence/battle_store.gd").new(content)
	var original: Dictionary = store.encode(battle)["record"]
	var with_time: Dictionary = original.duplicate(true)
	with_time["elapsedMinutes"] = 126
	var read: Dictionary = store.decode(with_time)
	if not read["ok"] or read.get("elapsedMinutes", -1) != 126:
		fail(
			"A continued battle must restore its saved cumulative minutes separately from combat state"
		)
		return
	if store.decode(original).has("elapsedMinutes"):
		fail(
			"Existing records without timing must retain an unknown duration rather than invent zero"
		)
		return
	for invalid: Variant in [-1, 0.5, "126", null, INF, 2147483648.0]:
		var broken: Dictionary = with_time.duplicate(true)
		broken["elapsedMinutes"] = invalid
		if store.decode(broken)["ok"]:
			fail("Malformed or overflowing elapsed time must reject before restoring gameplay")
			return
	var timed: Dictionary = store.encode(battle, 126)
	if not timed["ok"] or timed["record"]["elapsedMinutes"] != 126:
		fail("Temporary records need a validated cumulative-time write contract")
		return
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	battle = battle_script.new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	progress["elapsedMinutes"] = 127
	var encoded: Dictionary = store.encode_progress(progress)
	if (
		not encoded["ok"]
		or store.decode(encoded["record"])["progress"].get("elapsedMinutes", -1) != 127
	):
		fail("World records must retain timing together with their party and route")
		return
	progress["elapsedMinutes"] = -1
	if store.encode_progress(progress)["ok"]:
		fail("Unknown time is represented by absence; negative world durations are invalid")
		return
	print(
		"PASS save time: preserved duration, unknown old records, malformed input, battle/world clock"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
