extends SceneTree

const ContentProjection = preload("res://app/chapter_projection.gd")
const Contract = preload("res://app/chapter_story_contract.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Story = preload("res://features/dialogue/story_player.gd")
const MapView = preload("res://features/tactical_map/map_view.gd")
# Independent oracle: temp/m9/discovery.md and original-route-*/observations.json.
const PARTIES: Array = [
	[9, 0, 2, 4, 5, 1, 6, 7], [9, 0, 2, 8, 3, 7], [9, 0, 5, 1, 6, 7], [9, 0, 5, 4, 2, 8, 3, 7]
]


class FocusMap:
	extends Control
	var view: RefCounted = MapView.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if not _commander() or not _outcomes() or not _contracts():
		return
	if not await _focus():
		return
	print(
		"PASS m9 story seams: native formal candidates,AND retirement priority,source focus4/default12"
	)
	quit(0)


func _fragment(step: Dictionary) -> Dictionary:
	return {"battleName": {"text": "迷雾森林"}, "sequences": {"opening": [step]}, "turnEvents": []}


func _actor(identity: int) -> Dictionary:
	return {
		"id": identity,
		"sourceId": identity,
		"formal": true,
		"visible": true,
		"faction": 0,
		"x": identity,
		"y": 1,
		"hp": 20
	}


func _commander() -> bool:
	var step: Dictionary = {
		"kind": "commanderSetup",
		"candidateSource": "formalParty",
		"defaultMode": "automatic",
		"defaultStance": "attack"
	}
	for native: Array in PARTIES:
		var actors: Array = []
		for identity: int in native:
			actors.push_front(_actor(identity))
		var before: Dictionary = _fragment(step)
		var unchanged: Dictionary = before.duplicate(true)
		var resolved: Dictionary = ContentProjection.resolve_story(
			before, actors, {}, {"partyOrder": native, "worldStep": 5}
		)
		if not _expect(resolved["ok"], "Resolve each original commander context"):
			return false
		var actual: Dictionary = resolved["story"]["sequences"]["opening"][0]
		if not _expect(
			(
				_ints(actual["candidates"]) == _ints(native)
				and actual["defaultCommanderId"] == 9
				and not actual.has("candidateSource")
				and before == unchanged
			),
			"Formal candidates follow native party order,not deployment array"
		):
			return false
	var actors: Array = [
		_actor(9), _actor(0), _actor(2), _actor(3), _actor(4), _actor(5), _actor(6)
	]
	actors[2]["visible"] = false
	actors[3]["formal"] = false
	actors[4]["faction"] = 1
	actors[5]["sourceId"] = 20
	actors[6]["hp"] = 0  # Visibility, not HP, controls original candidate filtering.
	var resolved: Dictionary = ContentProjection.resolve_story(
		_fragment(step), actors, {}, {"partyOrder": [9, 0, 2, 3, 4, 5, 6, 7]}
	)
	if not _expect(
		(
			resolved["ok"]
			and _ints(resolved["story"]["sequences"]["opening"][0]["candidates"]) == [9, 0, 6]
		),
		"Hidden/temporary/allied/nonformal sources are excluded;missing IDs skip"
	):
		return false
	# Current snapshot visibility overrides the static deployment blueprint.
	var current: Dictionary = _actor(9)
	current["visible"] = false
	resolved = ContentProjection.resolve_story(
		_fragment(step), actors, {}, {"partyOrder": [9, 0], "units": [current]}
	)
	if not _expect(
		resolved["ok"] and _ints(resolved["story"]["sequences"]["opening"][0]["candidates"]) == [0],
		"Candidate projection uses current restored actor state"
	):
		return false
	for defect: String in [
		"unknown", "candidates", "default", "missingOrder", "duplicates", "fractional", "empty"
	]:
		var malformed: Dictionary = step.duplicate(true)
		var context: Dictionary = {"partyOrder": [9, 0]}
		match defect:
			"unknown":
				malformed["candidateSource"] = "allUnits"
			"candidates":
				malformed["candidates"] = [9]
			"default":
				malformed["defaultCommanderId"] = 9
			"missingOrder":
				context.erase("partyOrder")
			"duplicates":
				context["partyOrder"] = [9, 9]
			"fractional":
				context["partyOrder"] = [9.5]
			"empty":
				context["partyOrder"] = [2]
		if not _expect(
			not ContentProjection.resolve_story(_fragment(malformed), actors, {}, context)["ok"],
			"Invalid commander source fails before entry: " + defect
		):
			return false
	var explicit: Dictionary = {
		"kind": "commanderSetup", "candidates": [300, 0], "defaultCommanderId": 300
	}
	resolved = ContentProjection.resolve_story(
		_fragment(explicit), [_actor(300), _actor(0)], {}, {}
	)
	return _expect(
		resolved["ok"] and resolved["story"]["sequences"]["opening"][0] == explicit,
		"Existing explicit high-ID candidates and their order are untouched"
	)


func _outcomes() -> bool:
	var content: Dictionary = {
		"map": {"width": 20, "height": 20, "terrain": []},
		"rules": {"alliances": [0, 0, 1]},
		"story":
		{
			"turnEvents": [],
			"aiChanges": [],
			"outcomeRules":
			{
				"checks":
				[
					{"kind": "defeat", "condition": "requiredUnitFallen", "unitIds": [0]},
					{"kind": "victory", "condition": "allUnitsRetired", "unitIds": [31, 32]}
				]
			}
		}
	}
	var events := Events.new(content)
	for first: String in ["alive", "deadVisible", "hiddenAlive", "missing"]:
		for second: String in ["alive", "deadVisible", "hiddenAlive", "missing"]:
			var units: Array = [_actor(0)]
			for pair: Array in [[31, first], [32, second]]:
				if pair[1] == "missing":
					continue
				var actor: Dictionary = _actor(pair[0])
				actor["faction"] = 2
				actor["hp"] = 0 if pair[1] == "deadVisible" else 20
				actor["visible"] = pair[1] != "hiddenAlive"
				units.append(actor)
			var won: bool = first != "alive" and second != "alive"
			if not _expect(
				(events.outcome(units).get("kind") == "victory") == won,
				"Both targets must be missing,hidden orHP0: %s/%s" % [first, second]
			):
				return false
			units[0]["hp"] = 0
			units[0]["visible"] = false
			if not _expect(
				events.outcome(units).get("kind") == "defeat",
				"Required0 retirement takes priority over both targets"
			):
				return false
	return true


func _contracts() -> bool:
	var ids: Dictionary = {0: _actor(0), 9: _actor(9), 31: _actor(31), 32: _actor(32)}
	var valid: Dictionary = {"kind": "victory", "condition": "allUnitsRetired", "unitIds": [31, 32]}
	if not _expect(
		Contract._outcome_check_valid(valid, ids, 20), "AND contract accepts known targets"
	):
		return false
	for invalid: Variant in [[], [31, 31], [31, 99], [31.5], "31,32"]:
		var check: Dictionary = valid.duplicate(true)
		check["unitIds"] = invalid
		if not _expect(
			not Contract._outcome_check_valid(check, ids, 20), "AND rejects malformed targets"
		):
			return false
	for maximum: Variant in [4, 12]:
		if not _expect(
			Contract._story_step_valid(
				{"kind": "focus", "cell": [9, 1], "sourceMaxFocusPixels": maximum}, ids, 20, 20
			),
			"Focus accepts positive source maximum"
		):
			return false
	for maximum: Variant in [0, -1, 0.5, "4"]:
		if not _expect(
			not Contract._story_step_valid(
				{"kind": "focus", "cell": [9, 1], "sourceMaxFocusPixels": maximum}, ids, 20, 20
			),
			"Focus rejects invalid source maximum"
		):
			return false
	return _expect(
		not Contract._story_step_valid(
			{
				"kind": "commanderSetup",
				"candidateSource": "formalParty",
				"candidates": [9],
				"defaultCommanderId": 9
			},
			ids,
			20,
			20
		),
		"Unresolved source cannot bypass canonical story contract"
	)


func _focus() -> bool:
	var map := FocusMap.new()
	root.add_child(map)
	map.view.configure(Vector2i(20, 20), Vector2(24, 24))
	map.view.zoom = 1
	var story := Story.new()
	# This fixture drives only focus; setup-owned UI must never draw.
	story.hide()
	root.add_child(story)
	story.map = map
	story._tick_seconds = 0.001
	await story._step({"kind": "focus", "cell": [9, 1], "instant": true})
	var initial: Vector2 = map.view.center
	var completed: Dictionary = {"done": false}
	_play_focus(story, {"kind": "focus", "cell": [1, 9], "sourceMaxFocusPixels": 4}, completed)
	var first: Vector2 = (map.view.center - initial) * 24
	if not _expect(
		first.is_equal_approx(Vector2(-4, 4)), "Source4 caps each first focus axis at4px"
	):
		return false
	if not await _focus_finished(map, Vector2(1.5, 9.5), completed):
		return false
	for point: Array in [[9, 18], [19, 9]]:
		await story._step({"kind": "focus", "cell": point, "sourceMaxFocusPixels": 4})
		if not _expect(
			map.view.center.is_equal_approx(Vector2(point[0] + 0.5, point[1] + 0.5)),
			"Each patrol focus finishes before the next point"
		):
			return false
	map.view.focus_cell(Vector2i(9, 1))
	initial = map.view.center
	completed = {"done": false}
	_play_focus(story, {"kind": "focus", "cell": [1, 9]}, completed)
	first = (map.view.center - initial) * 24
	if not _expect(
		first.is_equal_approx(Vector2(-12, 12)), "A later ordinary focus restores default12"
	):
		return false
	if not await _focus_finished(map, Vector2(1.5, 9.5), completed):
		return false
	story.queue_free()
	map.queue_free()
	await process_frame
	return true


func _play_focus(story: Control, step: Dictionary, completed: Dictionary) -> void:
	await story._step(step)
	completed["done"] = true


func _focus_finished(map: Control, target: Vector2, completed: Dictionary) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while not completed["done"] and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	return _expect(
		completed["done"] and map.view.center.is_equal_approx(target),
		"Focus coroutine completes within bounded source time"
	)


func _ints(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
