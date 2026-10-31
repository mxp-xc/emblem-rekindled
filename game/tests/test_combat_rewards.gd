extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 21]
		elif spawn["id"] == 59:
			spawn["position"] = [9, 21]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(_limit: int) -> int: return 0
	)
	var state: Dictionary = battle.snapshot()
	var dropped_id: String
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["hp"] = 20
			actor["experience"] = 95
		elif actor["id"] == 59:
			actor["hp"] = 1
			for held: Dictionary in actor["inventory"]:
				if held["templateId"] == 1:
					held["durability"] = 7
					dropped_id = held["id"]
	if not battle.restore_snapshot(state)["ok"]:
		fail("Controlled stable combat setup must restore")
		return
	var before: Dictionary = battle.unit(0)
	var result: Dictionary = battle.attack_unit(0, 59)
	if not result.get("rewards") is Dictionary:
		fail("Combat must settle its earned experience and held drop once")
		return
	var actor: Dictionary = battle.unit(0)
	if (
		actor["level"] != 2
		or actor["experience"] != 5
		or actor["hp"] != 20
		or actor["maxHp"] != before["maxHp"] + 1
	):
		fail("Original kill XP must level once, retain modulo XP, and not heal current HP")
		return
	for stat: String in ["strength", "skill", "speed", "defense", "magic", "luck"]:
		if actor["attributes"][stat] != before["attributes"][stat] + 1:
			fail("Independent successful growth roll is missing: " + stat)
			return
	var found: bool = false
	for held: Dictionary in actor["inventory"]:
		if held["id"] == dropped_id:
			found = held["templateId"] == 1 and held["durability"] == 7
	if not found:
		fail("The marked drop must transfer its current instance/durability, not a fresh template")
		return
	for held: Dictionary in battle.unit(59)["inventory"]:
		if held["id"] == dropped_id:
			fail("A transferred item cannot retain a second owner")
			return
	var settled: Dictionary = battle.snapshot()
	if battle.attack_unit(0, 59)["ok"] or settled != battle.snapshot():
		fail("Replaying a completed attack must not grant experience or loot again")
		return
	print("PASS combat rewards: kill XP, level growth, HP, held drop identity, no duplicate reward")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
