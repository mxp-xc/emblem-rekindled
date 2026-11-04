extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Events = preload("res://gameplay/battle_events.gd")
const M11 = preload("res://tests/test_m11_content.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
var draws: Array[int] = []


func _initialize() -> void:
	var opened: Dictionary = _prepare()
	if not _expect(opened["ok"], "Open m15 from actual m11 settlement: " + str(opened)):
		return
	if not _opening_and_outcomes(opened) or not _combat(opened):
		return
	opened = _prepare()
	if not _expect(opened["ok"], "Open fresh m15 for phase events") or not _phases(opened):
		return
	print("PASS actual m15 opening, phase events, boss and conditional clones")
	quit(0)


func _prepare() -> Dictionary:
	var prepared: Dictionary = M11.prepare(M11.CONTEXTS[0], _roll)
	if not prepared["ok"]:
		return prepared
	var prior: Dictionary = Session.new().open(M11.CHAPTER, "m11", prepared["source"], _roll)
	if not prior["ok"]:
		return prior
	var won: Dictionary = prior["battle"].win_with_assistance()
	if not won["ok"]:
		return won
	var settled: Dictionary = prior["battle"].complete_victory(0)
	if not settled["ok"]:
		return settled
	return Session.new().open(M11.CHAPTER, "m15", {"progress": settled["progress"]}, _roll)


func _opening_and_outcomes(opened: Dictionary) -> bool:
	var story: Dictionary = opened["content"]["story"]
	var battle: RefCounted = opened["battle"]
	if not _expect(
		(
			(
				_dialogues(story, "opening")
				== [[619, 9], [621, 59], [622, 91], [623, 59], [624, 91], [620, 0]]
			)
			and battle.unit(59)["x"] == 10
			and battle.unit(59)["y"] == 17
			and (
				Vector2i(
					int(story["initialBattlePresentation"]["unitPositionOverrides"]["59"][0]),
					int(story["initialBattlePresentation"]["unitPositionOverrides"]["59"][1])
				)
				== Vector2i(10, 18)
			)
			and (
				story["initialBattlePresentation"]["hiddenUnitIds"].map(
					func(id: Variant) -> int: return int(id)
				)
				== [45, 46, 47, 48, 49, 50, 51, 52]
			)
			and not battle.unit(89)["visible"]
			and battle.unit(83)["visible"]
		),
		(
			"Opening mismatch: dialogues=%s reporter=%s presentation=%s boss83=%s boss89=%s"
			% [
				str(_dialogues(story, "opening")),
				str(battle.unit(59)),
				str(story["initialBattlePresentation"]),
				str(battle.unit(83)),
				str(battle.unit(89))
			]
		)
	):
		return false
	for identity: int in range(45, 53):
		if not _expect(
			battle.unit(identity)["visible"], "Opening reveal commits unit%d" % identity
		):
			return false
	var units: Array = battle.snapshot()["units"]
	var rules := Events.new(opened["content"])
	if not _expect(rules.outcome(units).is_empty(), "Hidden89 alone does not win"):
		return false
	for actor: Dictionary in units:
		if actor["id"] == 83:
			actor["hp"] = 0
			actor["visible"] = false
	if not _expect(rules.outcome(units).get("kind") == "victory", "83 retired while89 hidden wins"):
		return false
	for actor: Dictionary in units:
		if actor["id"] == 0:
			actor["hp"] = 0
			actor["visible"] = false
	return _expect(rules.outcome(units).get("kind") == "defeat", "Alm defeat takes priority")


func _combat(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var state: Dictionary = battle.snapshot()
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
	if not _expect(first.x >= 0, "Find vacant cells for controlled attack"):
		return false
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = first.x
			actor["y"] = first.y
			actor["inventory"] = [{"id": "m15:test:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m15:test:sword"
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		if actor["id"] == 83:
			actor["x"] = first.x + 1
			actor["y"] = first.y
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore controlled legal attack"):
		return false
	var result: Dictionary = battle.attack_unit(0, 83)
	return _expect(
		(
			result["ok"]
			and result["storyBefore"] == ["boss_first_combat"]
			and result["retirements"].size() == 1
			and result["retirements"][0]["beforeRetirement"] == ["boss_before_retirement"]
			and _dialogues(opened["content"]["story"], "boss_first_combat") == [[629, 83]]
			and _dialogues(opened["content"]["story"], "boss_before_retirement") == [[630, 83]]
			and battle.outcome.get("kind") == "victory"
		),
		"Ordinary boss83 combat triggers629/630 and early victory: " + str(result)
	)


func _phases(opened: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var waves: Dictionary = {
		4: [20, 22, 23, 24, 15, 16], 5: [56, 57, 58, 86, 10, 11, 12, 13, 14], 10: [89]
	}
	for round_number: int in range(1, 11):
		draws.clear()
		var result: Dictionary = Rounds.advance(battle)
		if not _expect(result["ok"], "Advance m15 round%d: %s" % [round_number, str(result)]):
			return false
		if not _expect(not draws.has(9), "Visible83 skips clone selection"):
			return false
		if round_number == 3:
			var withdrawals: Array = result["events"].filter(
				func(e: Dictionary) -> bool: return e["kind"] == "withdrawal"
			)
			if not _expect(
				(
					withdrawals.size() == 1
					and withdrawals[0]["unit"]["id"] == 91
					and not battle.unit(91)["visible"]
				),
				"Round3 withdraws91 exactly once"
			):
				return false
		if waves.has(round_number):
			for identity: int in waves[round_number]:
				if not _expect(
					battle.unit(identity)["visible"], "Round%d reveals%d" % [round_number, identity]
				):
					return false
	var state: Dictionary = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 83:
			actor["visible"] = false
			actor["flags"] |= 1
	if not _expect(battle.restore_snapshot(state)["ok"], "Restore hidden living83 after89 arrives"):
		return false
	draws.clear()
	var advanced: Dictionary = Rounds.advance(battle)
	return _expect(
		(
			advanced["ok"]
			and draws.filter(func(n: int) -> bool: return n == 9) == [9, 9, 9]
			and battle.snapshot()["cloneState"]["bindings"].size() == 3
		),
		"Hidden83 selects three clones"
	)


func _dialogues(story: Dictionary, sequence: String) -> Array:
	var result: Array = []
	for step: Dictionary in story["sequences"][sequence]:
		if step["kind"] == "dialogue":
			result.append([int(step["text"]["sourceTextIndex"]), int(step["text"]["speakerId"])])
	return result


func _roll(limit: int) -> int:
	draws.append(limit)
	return 0


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
