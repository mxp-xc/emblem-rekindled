extends SceneTree

const Events = preload("res://gameplay/battle_events.gd")
const Story = preload("res://features/dialogue/story_player.gd")
const Content = preload("res://app/chapter_content.gd")
const StoryContract = preload("res://app/chapter_story_contract.gd")
var failed: bool = false


class StoryMap:
	extends Control
	var content: Dictionary = {"units": []}
	var presentation_positions: Dictionary = {}


func _initialize() -> void:
	_outcome_priority()
	_counting_and_survival()
	_arrivals_and_pursuit()
	_combat_dialogues()
	_combat_event_contract()
	_actual_story_positions()
	if not failed:
		print(
			"PASS chapter events: configured priorities, survival, hidden pursuit and actual positions"
		)
	quit(1 if failed else 0)


func _content(checks: Array) -> Dictionary:
	return {
		"story": {"outcomeRules": {"checks": checks}, "turnEvents": [], "aiChanges": []},
		"map": {"width": 3, "height": 3},
		"rules": {"alliances": [0, 0, 1]}
	}


func _actor(id: int, faction: int, point: Vector2i = Vector2i.ZERO) -> Dictionary:
	return {
		"id": id,
		"faction": faction,
		"x": point.x,
		"y": point.y,
		"hp": 20,
		"visible": true,
		"flags": 0,
		"policy": 2,
		"action": 0
	}


func _outcome_priority() -> void:
	var boss: Dictionary = {"kind": "victory", "condition": "unitRetired", "unitId": 82}
	var required: Dictionary = {
		"kind": "defeat", "condition": "requiredUnitFallen", "unitIds": [0, 7]
	}
	var units: Array = [_actor(0, 0), _actor(7, 0), _actor(82, 2)]
	var rules: RefCounted = Events.new(_content([boss, required]))
	_check(rules.outcome(units).is_empty(), "A live hidden arrival must not be a required death")
	units[1]["hp"] = 0
	_check(rules.outcome(units).is_empty(), "Visible HP zero is still the source death transition")
	units[1]["visible"] = false
	_check(rules.outcome(units).get("unit") == 7, "A required death identifies the fallen member")
	units[2]["hp"] = 0
	_check(rules.outcome(units).get("reason") == "boss_defeated", "The first check wins a tie")
	rules = Events.new(_content([required, boss]))
	_check(
		rules.outcome(units).get("kind") == "defeat", "Configuration can prioritize required death"
	)
	rules = Events.new(_content([boss]))
	for boundary: String in ["dead", "hidden", "missing"]:
		units[2]["hp"] = 0 if boundary == "dead" else 20
		units[2]["visible"] = boundary != "hidden"
		var sample: Array = units.slice(0, 2) if boundary == "missing" else units
		_check(rules.outcome(sample).get("kind") == "victory", "Boss retirement: " + boundary)


func _counting_and_survival() -> void:
	var units: Array = [_actor(0, 0), _actor(35, 2)]
	units[1]["hp"] = 0
	var rules: RefCounted = Events.new(
		_content([{"kind": "victory", "condition": "allEnemiesDefeated", "faction": 2}])
	)
	_check(
		rules.outcome(units).get("kind") == "victory", "Initial-map elimination counts live enemies"
	)
	rules = Events.new(
		_content([{"kind": "victory", "condition": "noVisibleEnemies", "faction": 2}])
	)
	_check(
		rules.outcome(units).is_empty(), "A visible death transition still counts when configured"
	)
	units[1]["visible"] = false
	units[1]["hp"] = 20
	_check(
		rules.outcome(units).get("kind") == "victory",
		"Hidden future waves do not block this objective"
	)
	rules = Events.new(_content([{"kind": "victory", "condition": "roundAfter", "round": 10}]))
	_check(rules.outcome(units, 10).is_empty(), "Survival cannot finish at the threshold round")
	_check(
		rules.outcome(units, 11).get("reason") == "survived",
		"Survival finishes after the threshold"
	)
	rules = Events.new(
		_content([{"kind": "victory", "condition": "escaped", "unitId": 0, "row": 2}])
	)
	units[0]["y"] = 2
	_check(rules.outcome(units).is_empty(), "An uncommitted escape move remains cancellable")
	units[0]["action"] = 2
	_check(rules.outcome(units).get("reason") == "escaped", "The completed action triggers escape")


func _arrivals_and_pursuit() -> void:
	var content: Dictionary = _content([])
	content["story"]["turnEvents"] = [
		{"id": "arrival", "afterEnemyPhaseOfRound": 3, "unitIds": [63], "sequence": "arrival"}
	]
	content["story"]["aiChanges"] = [
		{"beforeEnemyPhaseOfRound": 9, "unitIds": [63], "flagsSet": 16, "policyClear": 2}
	]
	var rules: RefCounted = Events.new(content)
	var units: Array = [_actor(0, 0, Vector2i(1, 1)), _actor(63, 2, Vector2i(1, 1))]
	units[1]["visible"] = false
	units[1]["flags"] = 1
	var before: Array = units.duplicate(true)
	_check(rules.turn_events_due(2).is_empty(), "Turn events do not run early")
	_check(
		rules.turn_events_due(3).size() == 1,
		"Turn events select the configured enemy-phase boundary"
	)
	rules.prepare_enemy_phase(8, units)
	_check(units == before, "Pursuit does not run before its configured round")
	rules.prepare_enemy_phase(9, units)
	_check(
		not units[1]["visible"] and units[1]["flags"] == 17 and units[1]["policy"] == 0,
		"Pursuit changes policy without revealing a concealed enemy"
	)
	var changed: Array = units.duplicate(true)
	rules.prepare_enemy_phase(9, units)
	_check(units == changed, "Repeated pursuit application is idempotent")
	var arrivals: Array = rules.reinforce(units, [63, 999])
	_check(
		arrivals.size() == 1 and arrivals[0]["to"] == Vector2i(0, 1),
		"A blocked arrival uses the existing nearest free cell and ignores absent optional units"
	)
	_check(
		units[1]["visible"] and units[1]["flags"] == 16 and units[0] == before[0],
		"An arrival clears only the hidden flag and preserves unrelated actors"
	)
	_check(rules.reinforce(units, [63]).is_empty(), "An already visible arrival is not duplicated")


func _combat_dialogues() -> void:
	var content: Dictionary = _content([])
	content["story"]["combatEvents"] = [
		{"id": "boss_first", "trigger": "firstCombat", "unitId": 82, "sequence": "first"},
		{
			"id": "boss_death",
			"trigger": "unitDeath",
			"unitId": 82,
			"beforeRetirement": "death",
			"afterRetirement": "response"
		}
	]
	var rules: RefCounted = Events.new(content)
	var participants: Array = [_actor(0, 0), _actor(82, 2)]
	var current: Array = participants.duplicate(true)
	var before: Array = participants.duplicate(true)
	var first: Dictionary = rules.combat_events(participants, current, {})
	_check(
		(
			first["before"] == ["first"]
			and first["retirements"].is_empty()
			and first["completed"] == ["boss_first"]
			and first["flags"] == {82: 4}
		),
		"First combat returns its sequence, once marker and source flag"
	)
	_check(
		participants == before and current == before,
		"Event selection cannot mutate the committed battle or captured participants"
	)
	var reversed: Dictionary = rules.combat_events([participants[1], participants[0]], current, {})
	_check(reversed == first, "Enemy-initiated combat uses the same first encounter and B4 flag")
	current[1]["hp"] = 0
	current[1]["visible"] = false
	var retirement: Dictionary = {
		"unitId": 82, "beforeRetirement": ["death"], "afterRetirement": ["response"]
	}
	var death: Dictionary = rules.combat_events(participants, current, {"boss_first": true})
	_check(
		(
			death["before"].is_empty()
			and death["retirements"] == [retirement]
			and death["completed"] == ["boss_death"]
		),
		"Death sequences retain their retirement boundary without repeating first combat"
	)
	var restored: Dictionary = rules.combat_events(
		participants, current, {"boss_first": true, "boss_death": true}
	)
	_check(
		(
			restored["completed"].is_empty()
			and (
				restored["retirements"]
				== [{"unitId": 82, "beforeRetirement": [], "afterRetirement": []}]
			)
		),
		"Saved event markers prevent dialogue replay while retaining ordinary retirement"
	)
	participants[1]["flags"] |= 4
	var old_flags: Dictionary = rules.combat_events(participants, before, {})
	_check(
		(
			old_flags["before"].is_empty()
			and old_flags["completed"].is_empty()
			and old_flags["flags"].is_empty()
		),
		"An older saved B4 prevents first combat without consuming a newly configured event"
	)
	var unrelated: Dictionary = rules.combat_events([_actor(0, 0), _actor(30, 2)], current, {})
	_check(
		unrelated["completed"].is_empty(), "An unrelated battle cannot trigger a hidden boss event"
	)
	participants[1]["flags"] = 0
	var both: Dictionary = rules.combat_events(participants, current, {})
	_check(
		both["before"] == ["first"] and both["retirements"] == [retirement],
		"A first encounter that kills the boss keeps both ordered dialogue boundaries"
	)
	var same_side: Dictionary = rules.combat_events([_actor(30, 2), participants[1]], current, {})
	_check(
		same_side["before"].is_empty() and same_side["flags"] == {30: 4},
		"First combat follows the chosen actor when faction two attacks another faction two unit"
	)
	var ordinary: RefCounted = Events.new(_content([]))
	current[0]["hp"] = 0
	_check(
		(
			ordinary.combat_events(participants, current, {})["retirements"]
			== [
				{"unitId": 0, "beforeRetirement": [], "afterRetirement": []},
				{"unitId": 82, "beforeRetirement": [], "afterRetirement": []}
			]
		),
		"Every actual fallen participant retires in participant order even without dialogue"
	)
	_check(
		ordinary.combat_events([_actor(0, 0), _actor(30, 2)], before, {})["flags"] == {30: 4},
		"Ordinary first combat consumes source B4 even without a configured dialogue"
	)
	participants[0]["hp"] = 0
	_check(
		ordinary.combat_events(participants, current, {})["retirements"].size() == 1,
		"An already fallen input participant is not a new retirement"
	)
	_check(
		ordinary.combat_events(participants, [], {})["retirements"].is_empty(),
		"A missing current unit cannot fabricate a death transition"
	)


func _combat_event_contract() -> void:
	var content: Dictionary = Content.new().load_chapter("res://content/chapter_1/chapter.json")
	_check(content["ok"], "The real chapter must load before checking combat event contracts")
	if not content["ok"]:
		return
	var story: Dictionary = content["story"].duplicate(true)
	story["sequences"]["first"] = [{"kind": "focus", "unitId": 0}]
	story["sequences"]["death"] = [{"kind": "focus", "unitId": 0}]
	story["sequences"]["response"] = [{"kind": "focus", "unitId": 0}]
	story["sequences"]["empty"] = []
	var ids: Dictionary = {}
	for unit: Dictionary in content["units"]:
		ids[int(unit["id"])] = unit
	for id: int in content.get("referenceIds", []):
		if not ids.has(id):
			ids[id] = {}
	var first: Dictionary = {
		"id": "first", "trigger": "firstCombat", "unitId": 0, "sequence": "first"
	}
	var death: Dictionary = {
		"id": "death", "trigger": "unitDeath", "unitId": 0, "beforeRetirement": "death"
	}
	var after: Dictionary = death.duplicate(true)
	after.erase("beforeRetirement")
	after["afterRetirement"] = "response"
	var both: Dictionary = death.duplicate(true)
	both["afterRetirement"] = "response"
	var cases: Array = [[true, first], [true, death], [true, after], [true, both]]
	var old: Dictionary = death.duplicate(true)
	old.erase("beforeRetirement")
	old["sequence"] = "death"
	cases.append([false, old])
	var mixed: Dictionary = death.duplicate(true)
	mixed["sequence"] = "death"
	cases.append([false, mixed])
	var missing: Dictionary = death.duplicate(true)
	missing.erase("beforeRetirement")
	cases.append([false, missing])
	for key: String in ["beforeRetirement", "afterRetirement"]:
		for invalid: Variant in ["", "unknown", "empty", null, 3, INF, NAN, [], {}]:
			var broken: Dictionary = both.duplicate(true)
			broken[key] = invalid
			cases.append([false, broken])
		var wrong_trigger: Dictionary = first.duplicate(true)
		wrong_trigger[key] = "death"
		cases.append([false, wrong_trigger])
	for invalid: Variant in ["", "unknown", "empty", null, 3, INF, NAN, [], {}]:
		var broken: Dictionary = first.duplicate(true)
		broken["sequence"] = invalid
		cases.append([false, broken])
	for invalid: Variant in [INF, NAN, 0.5, "0", 999]:
		var broken: Dictionary = death.duplicate(true)
		broken["unitId"] = invalid
		cases.append([false, broken])
	for sample: Array in cases:
		story["combatEvents"] = [sample[1]]
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
				"Combat events must validate only their trigger's nonempty named sequences: "
				+ str(sample[1])
			)
		)


func _actual_story_positions() -> void:
	var story: Control = Story.new()
	var map := StoryMap.new()
	map.content["units"] = [_actor(82, 2, Vector2i(2, 2))]
	story.map = map
	_check(
		story._unit_position(82) == Vector2(2, 2), "Focus starts from the actual deployed position"
	)
	map.content["units"][0]["x"] = 1
	_check(
		story._unit_position(82) == Vector2(1, 2), "Focus follows normal movement after deployment"
	)
	map.presentation_positions[82] = Vector2(1, 0)
	_check(
		story._unit_position(82) == Vector2(1, 0),
		"An active presentation position wins during animation"
	)
	map.presentation_positions.clear()
	var before: Array = map.content["units"].duplicate(true)
	var points: Dictionary = story._entrance_points({"unitId": 82, "offset": [-3, 0]})
	_check(
		points == {"from": Vector2(-2, 2), "to": Vector2(1, 2)} and map.content["units"] == before,
		"Entrance offsets affect animation and preserve the actual deployment destination"
	)
	_check(
		story._unit_position(999) == null and story._entrance_points({"unitId": 999}).is_empty(),
		"A skipped optional deployment has no fabricated focus or entrance"
	)
	story.free()
	map.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
