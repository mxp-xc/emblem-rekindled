extends SceneTree

const Events = preload("res://gameplay/battle_events.gd")
const Contract = preload("res://app/chapter_story_contract.gd")


func _initialize() -> void:
	var defeat: Dictionary = {"kind": "defeat", "condition": "noVisibleFaction", "faction": 0}
	var victory: Dictionary = {"kind": "victory", "condition": "noVisibleFaction", "faction": 2}
	if not _check(
		(
			Contract._outcome_check_valid(defeat, {}, 20)
			and Contract._outcome_check_valid(victory, {}, 20)
		),
		"Encounter faction checks validate"
	):
		return
	for faction: Variant in [-1, 3, 1.5, "0"]:
		var invalid: Dictionary = defeat.duplicate()
		invalid["faction"] = faction
		if not _check(
			not Contract._outcome_check_valid(invalid, {}, 20), "Reject invalid encounter faction"
		):
			return
	var rules: RefCounted = Events.new(
		{
			"story":
			{"outcomeRules": {"checks": [defeat, victory]}, "turnEvents": [], "aiChanges": []},
			"map": {"width": 2, "height": 2},
			"rules": {"alliances": [0, 0, 1]}
		}
	)
	var units: Array = [
		{"id": 0, "faction": 0, "hp": 1, "visible": true},
		{"id": 1, "faction": 0, "hp": 1, "visible": false},
		{"id": 80, "faction": 2, "hp": 1, "visible": true}
	]
	if not _check(rules.outcome(units).is_empty(), "Both factions present continue"):
		return
	units[0]["hp"] = 0
	if not _check(rules.outcome(units).is_empty(), "Visible actor is counted before retirement"):
		return
	units[0]["visible"] = false
	if not _check(
		rules.outcome(units).get("kind") == "defeat", "Hidden surviving allies do not count"
	):
		return
	units[2]["visible"] = false
	if not _check(
		rules.outcome(units).get("kind") == "defeat",
		"Defeat has priority when both factions disappear"
	):
		return
	units[0]["visible"] = true
	units[0]["hp"] = 1
	if not _check(
		rules.outcome(units).get("kind") == "victory",
		"No visible enemies wins while a player remains"
	):
		return
	print("PASS encounter outcomes: visible factions and defeat priority")
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
