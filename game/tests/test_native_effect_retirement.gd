extends SceneTree


func _initialize() -> void:
	var opened: Dictionary = load("res://app/chapter_session.gd").new().open(
		"res://content/chapter_1/chapter.json",
		"",
		{"new": true},
		func(_limit: int) -> int: return 0
	)
	if not opened["ok"]:
		fail("Cannot open the original chapter fixture")
		return
	var battle: RefCounted = opened["battle"]
	var strikes: Array = []
	for index: int in range(8):
		strikes.append(
			{"attacker": 0, "defender": 54, "hit": true, "critical": false, "damage": 0, "heal": 0}
		)
	var prepared: Dictionary = (
		load("res://app/battle_clip_library.gd")
		. new(opened["content"])
		. prepare(
			{
				"participants": [battle.unit(0), battle.unit(54)],
				"resolvedWeapons": {"0": 9, "54": 40},
				"strikes": strikes
			}
		)
	)
	if not prepared["ok"]:
		fail("Cannot prepare the repeated original action: " + str(prepared))
		return
	prepared["visualSeed"] = 0
	var animation: RefCounted = load("res://features/battle/battle_animation.gd").new(prepared)
	var frames: int = 0
	while not animation.finished and frames < 2000:
		animation.advance()
		frames += 1
		for previous: Dictionary in animation._carry:
			var timeline: Dictionary = prepared["timelines"][previous["index"]]
			if timeline.has("nativeEffects") and not timeline["nativeEffects"].has_live_effects():
				fail("Completed actions without remaining effects must not keep advancing")
				return
	if not animation.finished or animation.current_index != 7:
		fail("The repeated action sequence must finish")
		return
	print("PASS: completed effects retire during repeated native actions")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
