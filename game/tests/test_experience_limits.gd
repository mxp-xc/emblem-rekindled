extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")

var rolls: int = 0


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for healing: bool in [true, false]:
		for level: int in [19, 20]:
			var battle: RefCounted = Battle.new(content, _roll)
			var state: Dictionary = battle.snapshot()
			var owner: int = 9 if healing else 0
			for actor: Dictionary in state["units"]:
				if actor["id"] == owner:
					actor["level"] = level
					actor["experience"] = 99
					actor["inventory"][0]["durability"] = 1
				if actor["id"] == 0:
					actor["hp"] = 20
					if not healing:
						actor["x"] = 8
						actor["y"] = 20
				elif actor["id"] == 59 and not healing:
					actor["x"] = 8
					actor["y"] = 21
					actor["hp"] = 1
			if not battle.restore_snapshot(state)["ok"]:
				fail("Controlled source Lv19/Lv20 reward boundary must restore")
				return
			var before: Dictionary = battle.unit(owner)
			var held: Dictionary = before["inventory"][0]
			var before_rolls: int = rolls
			var result: Dictionary = (
				battle.heal_unit(9, 0, held["id"]) if healing else battle.attack_unit(0, 59)
			)
			var actor: Dictionary = battle.unit(owner)
			var reward: Dictionary = result["rewards"]["experience"]
			if not result["ok"] or actor["action"] != 2:
				fail("The level limit must never suppress the actual action")
				return
			if level == 20:
				if (
					not reward.is_empty()
					or actor["experience"] != 99
					or actor["level"] != 20
					or actor["attributes"] != before["attributes"]
					or actor["maxHp"] != before["maxHp"]
				):
					fail(
						"Source Lv20 keeps XP/attributes unchanged and queues no experience or growth"
					)
					return
			elif reward["amount"] != 1 or actor["level"] != 20 or actor["experience"] != 0:
				fail("Source Lv19 samples earn one XP and cross from 99 to Lv20/XP0")
				return
			if healing:
				if (
					result["expiredItem"]["templateId"] != 53
					or battle.unit(0)["hp"] != 30
					or rolls - before_rolls != (9 if level == 19 else 1)
				):
					fail("Staff healing/expiry remains; only eight growth draws disappear at Lv20")
					return
			elif result["rewards"]["loot"].size() != 1 or result["brokenItems"].is_empty():
				fail("Weapon expiry and marked drops remain even when XP is capped")
				return
	var battle: RefCounted = Battle.new(content, _roll)
	var rules: RefCounted = load("res://gameplay/combat_rules.gd").new(
		content["rules"], content["map"]["terrain"]
	)
	for id: int in [55, 48, 52]:
		if rules.experience_gain(battle.unit(id), {}, false, true, false) != 0:
			fail("The original recipient class groups 7/8/9 cannot receive XP")
			return
		if rules.experience_gain(battle.unit(0), battle.unit(id), true, true, false) <= 0:
			fail("Killing an excluded monster class must still reward an eligible recipient")
			return
	if rules.experience_gain(battle.unit(95), {}, false, true, false) != 12:
		fail("An ordinary recipient class must retain its source XP")
		return
	print(
		"PASS experience limits: Lv19/20 action, XP/growth RNG, expiry/drop, recipient class filtering"
	)
	quit(0)


func _roll(_limit: int) -> int:
	rolls += 1
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
