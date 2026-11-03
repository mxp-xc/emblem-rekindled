extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	var opening: Dictionary = Session.new().open(CHAPTER, "m0", {"new": true}, _roll)
	opening["battle"].win_with_assistance()
	var progress: Dictionary = opening["battle"].complete_victory(0)["progress"]
	var opened: Dictionary = Session.new().open(CHAPTER, "m1", {"progress": progress}, _roll)
	var battle: RefCounted = opened["battle"]
	var fols: Dictionary = battle.unit(6)
	battle.share_experience = true
	var target: int = -1
	for unit: Dictionary in battle.snapshot()["units"]:
		if unit["faction"] == 2 and unit["visible"]:
			target = int(unit["id"])
			break
	for actor_id: int in [6, 95]:
		if actor_id == 95:
			battle.end_phase()
			while battle.phase != 0:
				while battle.automatic_actor() >= 0:
					battle.wait_unit(battle.automatic_actor())
				battle.end_phase()
		var state: Dictionary = battle.snapshot()
		for unit: Dictionary in state["units"]:
			if actor_id == 95 and unit["id"] == 6:
				unit["x"] = fols["x"]
				unit["y"] = fols["y"]
			if unit["id"] == actor_id:
				unit["x"] = 8
				unit["y"] = 8
			elif unit["id"] == target:
				unit["x"] = 8
				unit["y"] = 9
		if not battle.restore_snapshot(state)["ok"]:
			fail("Controlled adjacent combat on actual m1 must restore")
			return
		for distance: int in range(1, 4):
			for unit: Dictionary in state["units"]:
				if unit["id"] == target:
					unit["y"] = 8 + distance
			if not battle.restore_snapshot(state)["ok"]:
				continue
			if battle.attack_preview(actor_id, target)["ok"]:
				break
		var before: Dictionary = {}
		for unit: Dictionary in state["units"]:
			before[int(unit["id"])] = unit
		var result: Dictionary = battle.attack_unit(actor_id, target)
		if not result["ok"]:
			fail("Actual m1 fighter must earn XP through combat: " + str(result))
			return
		var amount: int = result["rewards"]["experience"]["amount"]
		for old: Dictionary in before.values():
			var expected: int = int(old["experience"])
			if (
				old["id"] == actor_id
				or (old["formal"] and old["faction"] == 0 and old["visible"] and old["hp"] > 0)
			):
				expected = (expected + amount) % 100
			if battle.unit(old["id"])["experience"] != expected:
				fail("Only acting ordinary troops or arrived formal members may gain XP")
				return
		if (
			actor_id == 6
			and (battle.unit(0)["experience"] != 0 or battle.unit(9)["experience"] != 0)
		):
			fail("Alm's m1 reinforcement group must not gain XP before arriving")
			return
	print(
		"PASS shared arrival: real m1 arrival boundary and ordinary attack shares only to arrived party"
	)
	quit(0)


func _roll(limit: int) -> int:
	return limit - 1


func fail(message: String) -> void:
	push_error(message)
	quit(1)
