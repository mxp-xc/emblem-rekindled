extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const M12 = preload("res://tests/test_m12_content.gd")
const Clones = preload("res://gameplay/battle_clones.gd")
const Rounds = preload("res://tests/test_m4_events.gd")


func _initialize() -> void:
	var story: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/authored/battles/m16.json")
	)
	var records: Array = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://content/chapter_1/generated/battles/m16/deployments.json"
		)
	)
	var declared: Dictionary = Clones.definition(story["periodicClones"], records)
	if not _check(declared.get("ok", false), "Clone definition: " + str(declared)):
		return
	for index: int in _contexts():
		var context: Dictionary = M12.CONTEXTS[index]
		var prepared: Dictionary = M12.prepare(context, _roll)
		if not _check(prepared.get("ok", false), "Prepare m12: " + str(prepared)):
			return
		var previous: Dictionary = Session.new().open(M12.CHAPTER, "m12", prepared["source"], _roll)
		if not _check(previous.get("ok", false), "Open m12: " + str(previous)):
			return
		var won: Dictionary = previous["battle"].win_with_assistance()
		var settled: Dictionary = (
			previous["battle"].complete_victory(context["route"]) if won.get("ok", false) else won
		)
		if not _check(settled.get("ok", false), "Settle m12: " + str(settled)):
			return
		for member: Dictionary in settled["progress"]["party"]:
			if member["id"] == 0:
				member["experience"] = 17
		var opened: Dictionary = Session.new().open(
			M12.CHAPTER, "m16", {"progress": settled["progress"]}, _roll
		)
		if not _check(
			opened.get("ok", false), "Open m16 route %d: %s" % [context["route"], str(opened)]
		):
			return
		var battle: RefCounted = opened["battle"]
		var inherited: Dictionary = {}
		for member: Dictionary in settled["progress"]["party"]:
			if member["id"] == 0:
				inherited = member
		if not _check(
			(
				battle.snapshot()["units"].size() == 54
				and battle.unit(80)["visible"]
				and not battle.unit(92)["visible"]
				and not battle.unit(93)["visible"]
				and not battle.unit(94)["visible"]
				and battle.outcome.is_empty()
				and opened["content"]["map"]["locations"].size() == 15
				and battle.unit(0)["level"] == inherited["level"]
				and battle.unit(0)["experience"] == 17
				and battle.unit(0)["inventory"] == inherited["inventory"]
				and battle.unit(0)["attributes"] == inherited["attributes"]
			),
			"m16 route %d preserves deployment and location state" % context["route"]
		):
			return
		var cold: Dictionary = Session.new().open(
			M12.CHAPTER, "m16", {"snapshot": battle.snapshot()}, _roll
		)
		if not _check(
			(
				cold.get("ok", false)
				and cold["battle"].unit(0)["inventory"] == inherited["inventory"]
				and cold["battle"].unit(0)["experience"] == 17
				and cold["battle"].unit(0)["attributes"] == inherited["attributes"]
			),
			"m16 route %d restores the fixed inherited actor: %s" % [context["route"], str(cold)]
		):
			return
		if context["route"] == 2 and not _locations(cold["battle"]):
			return
		if not _clone_rounds(cold["battle"], int(context["route"])):
			return
		if context["route"] == 2 and not _boss_battle(battle):
			return
	print("PASS m16 selected routes open from actual m12 settlement")
	quit(0)


func _contexts() -> Array[int]:
	return [0]


func _roll(_limit: int) -> int:
	return 0


func _locations(battle: RefCounted) -> bool:
	var original: Dictionary = battle.snapshot()
	for test: Array in [
		["wait_0", Vector2i(1, 1), "wait", 74],
		["wait_14", Vector2i(29, 4), "wait", 68],
		["chest_1", Vector2i(4, 1), "chest", 10],
		["chest_2", Vector2i(4, 3), "chest", 27],
		["chest_3", Vector2i(4, 5), "chest", 9],
		["visit_4", Vector2i(7, 18), "visit", 3],
		["visit_5", Vector2i(7, 20), "visit", -1],
		["visit_6", Vector2i(8, 18), "visit", -1],
		["visit_7", Vector2i(8, 20), "visit", 62],
		["visit_8", Vector2i(17, 21), "visit", -1],
		["visit_9", Vector2i(19, 21), "visit", -1],
		["visit_10", Vector2i(20, 19), "visit", 53],
		["chest_11", Vector2i(24, 1), "chest", 19],
		["chest_12", Vector2i(24, 3), "chest", 38],
		["chest_13", Vector2i(24, 5), "chest", 27]
	]:
		var state: Dictionary = original.duplicate(true)
		var occupied: Dictionary = {}
		for unit: Dictionary in state["units"]:
			if unit["visible"] and unit["id"] != 0:
				occupied[Vector2i(unit["x"], unit["y"])] = true
		var replacement := Vector2i(-1, -1)
		for y: int in range(30):
			for x: int in range(30):
				var candidate := Vector2i(x, y)
				if not occupied.has(candidate) and candidate != test[1]:
					replacement = candidate
					break
			if replacement.x >= 0:
				break
		for unit: Dictionary in state["units"]:
			if unit["id"] == 0:
				unit["x"] = test[1].x
				unit["y"] = test[1].y
			elif unit["visible"] and Vector2i(unit["x"], unit["y"]) == test[1]:
				unit["x"] = replacement.x
				unit["y"] = replacement.y
		if not _check(
			replacement.x >= 0 and battle.restore_snapshot(state)["ok"],
			"Restore m16 location " + test[0]
		):
			return false
		var result: Dictionary
		match test[2]:
			"wait":
				result = battle.wait_unit(0)
			"visit":
				result = battle.visit_location(0)
			_:
				result = battle.open_chest(0)
		var claim: Dictionary = result.get("location", {}) if test[2] == "wait" else result
		var reward_ok: bool = (
			(
				claim.get("reward", {}) == {"kind": "gold", "amount": 1}
				and battle.gold == int(original["gold"]) + 1
			)
			if test[3] == -1
			else (
				claim.get("rewards", {}).get("loot", []).size() == 1
				and claim["rewards"]["loot"][0]["item"]["templateId"] == test[3]
			)
		)
		if not _check(
			(
				claim.get("claimed", false)
				and reward_ok
				and battle.unit(0)["action"] == 2
				and battle.event_completed("location:" + test[0])
			),
			"m16 location reward " + test[0] + ": " + str(result)
		):
			return false
		if test[0] in ["wait_0", "wait_14", "chest_1", "chest_3", "chest_13", "visit_4", "visit_5"]:
			var restored: Dictionary = Session.new().open(
				M12.CHAPTER, "m16", {"snapshot": battle.snapshot()}, _roll
			)
			if not _check(
				(
					restored.get("ok", false)
					and restored["battle"].event_completed("location:" + test[0])
				),
				"m16 location survives cold restore: " + test[0]
			):
				return false
	return _check(
		battle.restore_snapshot(original)["ok"], "Restore initial state after location tests"
	)


func _clone_rounds(battle: RefCounted, route: int) -> bool:
	for round_number: int in [1, 2]:
		var result: Dictionary = Rounds.advance(battle)
		if not _check(
			result.get("ok", false), "Advance m16 round %d: %s" % [round_number, str(result)]
		):
			return false
		var waves: Array = result["events"].filter(
			func(e: Dictionary) -> bool: return e["kind"] == "clones"
		)
		if not _check(
			waves.size() == (1 if round_number == 2 else 0), "Clones only arrive on even rounds"
		):
			return false
		if round_number == 2:
			var sources: Array[int] = []
			for birth: Dictionary in waves[0]["births"]:
				sources.append(int(battle.unit(birth["unit"])["sourceId"]))
			if not _check(
				sources == [109, 108, 107],
				"Visible gates produce expected clone families: " + str(sources)
			):
				return false
		var restored: Dictionary = Session.new().open(
			M12.CHAPTER, "m16", {"snapshot": battle.snapshot()}, _roll
		)
		if not _check(
			restored.get("ok", false),
			"Round %d cold restore route %d: %s" % [round_number, route, str(restored)]
		):
			return false
		battle = restored["battle"]
	return true


func _boss_battle(battle: RefCounted) -> bool:
	var state: Dictionary = battle.snapshot()
	var occupied: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] not in [0, 80] and actor["visible"]:
			occupied[Vector2i(actor["x"], actor["y"])] = true
	var cell := Vector2i(-1, -1)
	for y: int in range(30):
		for x: int in range(29):
			if not occupied.has(Vector2i(x, y)) and not occupied.has(Vector2i(x + 1, y)):
				cell = Vector2i(x, y)
				break
		if cell.x >= 0:
			break
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = cell.x
			actor["y"] = cell.y
			actor["inventory"] = [{"id": "m16:test:sword", "templateId": 1, "durability": 30}]
			actor["equippedInstanceId"] = "m16:test:sword"
			actor["attributes"]["strength"] = 30
			actor["attributes"]["skill"] = 30
		elif actor["id"] == 80:
			actor["x"] = cell.x + 1
			actor["y"] = cell.y
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
	if not _check(
		cell.x >= 0 and battle.restore_snapshot(state)["ok"], "Restore controlled m16 boss combat"
	):
		return false
	var result: Dictionary = battle.attack_unit(0, 80)
	if not _check(
		(
			result.get("ok", false)
			and battle.outcome.is_empty()
			and battle.unit(92)["visible"]
			and battle.unit(93)["visible"]
			and battle.unit(94)["visible"]
			and result["retirements"].size() == 1
			and (
				result["retirements"][0]["arrivalQueue"].map(
					func(a: Dictionary) -> int: return a["unit"]
				)
				== [92, 93, 94]
			)
		),
		"m16 boss death queues elements before victory: " + str(result)
	):
		return false
	if not _map_element_dialogue(battle):
		return false
	for target: int in [92, 93, 94]:
		state = battle.snapshot()
		occupied.clear()
		for actor: Dictionary in state["units"]:
			if actor["id"] not in [0, target] and actor["visible"]:
				occupied[Vector2i(actor["x"], actor["y"])] = true
		cell = Vector2i(-1, -1)
		for y: int in range(30):
			for x: int in range(29):
				if not occupied.has(Vector2i(x, y)) and not occupied.has(Vector2i(x + 1, y)):
					cell = Vector2i(x, y)
					break
			if cell.x >= 0:
				break
		for actor: Dictionary in state["units"]:
			if actor["id"] == 0:
				actor["x"] = cell.x
				actor["y"] = cell.y
				actor["action"] = 0
			elif actor["id"] == target:
				actor["x"] = cell.x + 1
				actor["y"] = cell.y
				actor["hp"] = 1
				actor["attributes"]["defense"] = 0
		if not _check(battle.restore_snapshot(state)["ok"], "Restore controlled element combat"):
			return false
		result = battle.attack_unit(0, target)
		if not _check(result.get("ok", false), "Element combat succeeds: " + str(result)):
			return false
		if target == 92:
			var cold: Dictionary = Session.new().open(
				M12.CHAPTER, "m16", {"snapshot": battle.snapshot()}, _roll
			)
			if not _check(
				(
					result["storyBefore"] == ["element_first_combat"]
					and cold.get("ok", false)
					and cold["battle"].event_completed("element_first_combat")
					and (cold["battle"].unit(92)["flags"] & 4) != 0
				),
				"m16 first element dialogue and source flag survive cold restore"
			):
				return false
		if not _check(
			(battle.outcome.get("kind") == "victory") == (target == 94),
			"Victory waits for all elements"
		):
			return false
	var before_gold: int = battle.gold
	var complete: Dictionary = battle.complete_victory(2)
	return _check(
		(
			complete.get("ok", false)
			and complete["progress"].get("chapterCompleted", false)
			and complete["progress"]["gold"] == before_gold + 1000
		),
		"m16 completion produces chapter progress and 1000 gold: " + str(complete)
	)


func _map_element_dialogue(battle: RefCounted) -> bool:
	var original: Dictionary = battle.snapshot()
	var controlled: Dictionary = original.duplicate(true)
	for actor: Dictionary in controlled["units"]:
		match int(actor["id"]):
			8:
				actor["x"] = 7
				actor["y"] = 10
				actor["attributes"]["skill"] = 30
				actor["attributes"]["magic"] = 30
				actor["inventory"] = [{"id": "m16:map:50", "templateId": 50, "durability": 10}]
				actor["equippedInstanceId"] = "m16:map:50"
			92:
				actor["x"] = 9
				actor["y"] = 10
				actor["hp"] = 1
				actor["attributes"]["magic"] = 0
			_:
				if actor["visible"] and actor["y"] == 10 and actor["x"] in [7, 9]:
					actor["visible"] = false
	if not _check(battle.restore_snapshot(controlled)["ok"], "Restore m16 map attack setup"):
		return false
	var result: Dictionary = battle.cast_map_attack(8, "m16:map:50", 92)
	if not _check(
		(
			result.get("ok", false)
			and 92 in result["targetIds"]
			and result["storyBefore"].is_empty()
			and not battle.event_completed("element_first_combat")
			and (battle.unit(92)["flags"] & 4) == 0
		),
		(
			"m16 map attack leaves the element's first ordinary combat dialogue available: "
			+ str(result)
		)
	):
		return false
	var cold: Dictionary = Session.new().open(
		M12.CHAPTER, "m16", {"snapshot": battle.snapshot()}, _roll
	)
	if not _check(
		(
			cold.get("ok", false)
			and not cold["battle"].event_completed("element_first_combat")
			and (cold["battle"].unit(92)["flags"] & 4) == 0
		),
		"m16 map attack preserves the dialogue boundary across cold restore"
	):
		return false
	var resumed: RefCounted = cold["battle"]
	controlled = resumed.snapshot()
	for actor: Dictionary in controlled["units"]:
		if actor["id"] == 0:
			actor["x"] = 8
			actor["y"] = 10
			actor["action"] = 0
		elif (
			actor["id"] not in [8, 92] and actor["visible"] and actor["x"] == 8 and actor["y"] == 10
		):
			actor["visible"] = false
	if not _check(resumed.restore_snapshot(controlled)["ok"], "Restore m16 ordinary attack setup"):
		return false
	var ordinary: Dictionary = resumed.attack_unit(0, 92)
	return _check(
		(
			ordinary.get("ok", false)
			and ordinary["storyBefore"] == ["element_first_combat"]
			and battle.restore_snapshot(original)["ok"]
		),
		"m16 ordinary combat still plays the dialogue after the saved map attack: " + str(ordinary)
	)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
