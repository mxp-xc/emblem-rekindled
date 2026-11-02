extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const StoryContract = preload("res://app/chapter_story_contract.gd")
const Story = preload("res://features/dialogue/story_player.gd")
const TacticalMap = preload("res://features/tactical_map/tactical_map.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _draws: int = 0
var _failed: bool = false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var opened: Dictionary = Session.new().open(CHAPTER, "", {"new": true}, _roll)
	if not _check(opened["ok"], "Reveal tests require the existing m0 entry"):
		quit(1)
		return
	var content: Dictionary = opened["content"]
	_contract(content)
	await _presentation(content, opened["battle"])
	if not _failed:
		print(
			"PASS reveal units: strict JSON contract, synchronous groups, position and battle isolation"
		)
	quit(1 if _failed else 0)


func _contract(content: Dictionary) -> void:
	var story: Dictionary = content["story"].duplicate(true)
	var ids: Dictionary = {}
	for unit: Dictionary in content["units"]:
		ids[int(unit["id"])] = unit
	for id: int in content.get("referenceIds", []):
		if not ids.has(id):
			ids[id] = {}
	# Declared deployments need no extra map, profile or image fixture to validate their references.
	for id: int in [63, 64, 65, 66]:
		ids[id] = {}
	var reveal: Dictionary = {"kind": "revealUnits", "unitIds": [63, 64, 65, 66]}
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(reveal))
	_check(parsed["unitIds"][0] is float, "JSON integer IDs arrive as integral floats")
	var cases: Array = [[true, reveal], [true, parsed]]
	cases.append([true, {"unitIds": [63.0], "kind": "revealUnits"}])
	for invalid: Variant in [
		null,
		[],
		{},
		"63",
		63,
		[63, 63],
		[63, 63.0],
		[999],
		[63.5],
		["63"],
		[true],
		[null],
		[INF],
		[-INF],
		[NAN]
	]:
		cases.append([false, {"kind": "revealUnits", "unitIds": invalid}])
	cases.append([false, {"kind": "revealUnits"}])
	for extra: String in [
		"focus",
		"offset",
		"from",
		"to",
		"instant",
		"sourceWaitTicks",
		"sourceWaitTicksAfter",
		"sourceHoldTicksAfter",
		"holdTicksAfter",
		"other"
	]:
		var unsupported: Dictionary = reveal.duplicate(true)
		unsupported[extra] = 0
		cases.append([false, unsupported])
	for sample: Array in cases:
		story["sequences"]["reveal_fixture"] = [{"kind": "focus", "cell": [8, 11]}, sample[1]]
		_check(
			(
				StoryContract.validate(
					story,
					content["entry"]["resourceDirectory"],
					ids,
					int(content["map"]["width"]),
					int(content["map"]["height"])
				)
				== sample[0]
			),
			(
				"Reveal accepts only nonempty unique declared integer IDs and kind/unitIds: "
				+ str(sample[1])
			)
		)


func _presentation(content: Dictionary, battle: RefCounted) -> void:
	var map: Control = TacticalMap.new()
	root.add_child(map)
	map.setup(content)
	map.set_units(battle.snapshot()["units"])
	map.prepare_opening(
		{
			"hiddenUnitIds": [48, 49, 51, 57],
			"hiddenFactions": [2],
			"unitPositionOverrides": {"48": [4, 7], "51": [5, 8]}
		}
	)
	var player: Control = Story.new()
	player.theme = PixelTheme.new().create(
		content["interface"], content["entry"]["resourceDirectory"]
	)
	root.add_child(player)
	player.setup(content, map)
	var original_units: Array = map.content["units"].duplicate(true)
	var original_positions: Dictionary = map.presentation_positions.duplicate(true)
	var original_state: Dictionary = battle.snapshot()
	var original_draws: int = _draws
	var original_visible: Array = _visible_ids(map)
	var original_center: Vector2 = map.view.center
	for id: int in [48, 49, 51, 57]:
		_check(not original_visible.has(id), "Each reinforcement group starts presentation-hidden")
	var complete: Array[bool] = [false]
	var play: Callable = func() -> void:
		await player.play(
			[JSON.parse_string(JSON.stringify({"kind": "revealUnits", "unitIds": [48, 49]}))]
		)
		complete[0] = true
	var frame: int = Engine.get_process_frames()
	play.call()
	_check(
		complete[0] and not player.visible and Engine.get_process_frames() == frame,
		"Real StoryPlayer.play must finish a reveal synchronously without yielding a frame"
	)
	var expected_visible: Array = original_visible.duplicate()
	expected_visible.append_array([48, 49])
	expected_visible.sort()
	_check(
		_visible_ids(map) == expected_visible,
		"The requested group appears together while other groups and the hidden faction stay hidden"
	)
	_check(
		map.presentation_hidden_ids == [51, 57] and map.presentation_hidden_factions == [2],
		"A grouped reveal releases only its IDs without revealing their whole faction"
	)
	_check(
		map.presentation_revealed_ids == [48, 49],
		"Both group members override faction hiding in the real map visibility contract"
	)
	complete[0] = false
	play = func() -> void:
		await player.play(
			[{"kind": "revealUnits", "unitIds": [49, 48]}, {"kind": "revealUnits", "unitIds": [51]}]
		)
		complete[0] = true
	play.call()
	_check(
		complete[0] and not player.visible and Engine.get_process_frames() == frame,
		"Repeated and subsequent group operations also finish without yielding a frame"
	)
	expected_visible.append(51)
	expected_visible.sort()
	_check(
		(
			_visible_ids(map) == expected_visible
			and map.presentation_revealed_ids == [48, 49, 51]
			and map.presentation_hidden_ids == [57]
		),
		"Repeating a reveal cannot duplicate IDs or prematurely release the remaining group"
	)
	_check(
		(
			map.content["units"] == original_units
			and map.presentation_positions == original_positions
			and map.view.center == original_center
			and battle.snapshot() == original_state
			and _draws == original_draws
		),
		"Reveal preserves actual coordinates, presentation positions, camera, battle state, HP and RNG"
	)
	player.queue_free()
	map.queue_free()
	await process_frame


func _visible_ids(map: Control) -> Array:
	var ids: Array = []
	for unit: Dictionary in map.visible_units():
		ids.append(int(unit["id"]))
	ids.sort()
	return ids


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error(message)
	return condition
