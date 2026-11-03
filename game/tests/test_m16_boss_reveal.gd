extends "res://tests/test_m15_events.gd"

const Battle = preload("res://gameplay/battle_state.gd")
const Contract = preload("res://app/chapter_story_contract.gd")


func _initialize() -> void:
	var opened: Dictionary = _prepare()
	if not _expect(opened.get("ok", false), "Open controlled source battle"):
		return
	var content: Dictionary = opened["content"].duplicate(true)
	content["story"]["combatEvents"] = [
		{"id": "boss_reveal", "trigger": "unitDeath", "unitId": 83, "revealUnitIds": [89]}
	]
	content["story"]["outcomeRules"]["checks"] = [
		{"kind": "defeat", "condition": "requiredUnitFallen", "unitIds": [0]},
		{"kind": "victory", "condition": "allUnitsRetired", "unitIds": [83, 89]}
	]
	var ids: Dictionary = {}
	for actor: Dictionary in content["units"]:
		ids[int(actor["id"])] = actor
	if not _expect(_valid_story(content, ids), "Reveal declaration and presentation agree"):
		return
	for mutation: String in ["empty", "duplicate", "unknown", "self", "first_combat"]:
		var invalid: Dictionary = content.duplicate(true)
		var event: Dictionary = invalid["story"]["combatEvents"][0]
		match mutation:
			"empty":
				event["revealUnitIds"] = []
			"duplicate":
				event["revealUnitIds"] = [89, 89]
			"unknown":
				event["revealUnitIds"] = [999]
			"self":
				event["revealUnitIds"] = [83]
			"first_combat":
				event["trigger"] = "firstCombat"
		if not _expect(not _valid_story(invalid, ids), "Reject invalid reveal: " + mutation):
			return
	var battle: RefCounted = Battle.new(content, _roll)
	var state: Dictionary = opened["battle"].snapshot()
	var occupied: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [0, 83] and actor["visible"]:
			occupied[Vector2i(actor["x"], actor["y"])] = true
	var first := Vector2i(-1, -1)
	for y: int in range(25):
		for x: int in range(24):
			if not occupied.has(Vector2i(x, y)) and not occupied.has(Vector2i(x + 1, y)):
				first = Vector2i(x, y)
				break
		if first.x >= 0:
			break
	var blocked := Vector2i(-1, -1)
	for cell: Vector2i in occupied:
		if (
			cell.x > 0
			and not occupied.has(cell + Vector2i.LEFT)
			and cell + Vector2i.LEFT not in [first, first + Vector2i.RIGHT]
		):
			blocked = cell
			break
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = first.x
			actor["y"] = first.y
			actor["inventory"] = [{"id": "test:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "test:sword"
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		elif actor["id"] == 83:
			actor["x"] = first.x + 1
			actor["y"] = first.y
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
		elif actor["id"] == 89:
			actor["x"] = blocked.x
			actor["y"] = blocked.y
	if not _expect(
		first.x >= 0 and blocked.x > 0 and battle.restore_snapshot(state)["ok"],
		"Restore controlled combat"
	):
		return
	var result: Dictionary = battle.attack_unit(0, 83)
	if not _expect(
		(
			result["ok"]
			and battle.unit(89)["visible"]
			and battle.outcome.is_empty()
			and battle.event_completed("boss_reveal")
			and result["retirements"][0].get("arrivalQueue", []).size() == 1
			and result["retirements"][0]["arrivalQueue"][0]["unit"] == 89
			and result["retirements"][0]["arrivalQueue"][0]["revealed"]
			and result["retirements"][0]["arrivalQueue"][0]["from"] == blocked
			and Vector2i(battle.unit(89)["x"], battle.unit(89)["y"]) == blocked + Vector2i.LEFT
		),
		(
			"Boss defeat reveals target before victory check and supplies presentation handoff: "
			+ str(result)
		)
	):
		return
	var fresh: RefCounted = Battle.new(content, _roll)
	if not _expect(
		(
			fresh.restore_snapshot(battle.snapshot())["ok"]
			and fresh.unit(89)["visible"]
			and fresh.event_completed("boss_reveal")
		),
		"Cold restore retains reveal"
	):
		return
	print("PASS boss death reveal before outcome and cold restore")
	quit(0)


func _valid_story(content: Dictionary, ids: Dictionary) -> bool:
	return Contract.validate(
		content["story"],
		content["entry"]["resourceDirectory"],
		ids,
		int(content["map"]["width"]),
		int(content["map"]["height"]),
		content["_deployments"]
	)
