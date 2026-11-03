extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const CHAPTER = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	var session := Session.new()
	var first: Dictionary = session.open(CHAPTER, "", {"new": true}, _zero)
	first["battle"].win_with_assistance()
	var progress: Dictionary = first["battle"].complete_victory(0)["progress"]
	for sample: Array in [[16, 5, 3, 63], [21, 16, 4, 76]]:
		var opened: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _zero)
		if not opened["ok"]:
			fail("Open actual m1: " + str(opened))
			return
		var battle: RefCounted = opened["battle"]
		var state: Dictionary = battle.snapshot()
		for actor: Dictionary in state["units"]:
			if actor["id"] == 0:
				actor["x"] = sample[0]
				actor["y"] = sample[1]
				actor["action"] = 0
				actor["visible"] = true
				actor["flags"] = int(actor["flags"]) & ~1
				actor["inventory"] = []
				actor["equippedInstanceId"] = ""
		if not battle.restore_snapshot(state)["ok"]:
			fail("Restore actual m1 chest position")
			return
		var waited: Dictionary = battle.wait_unit(0)
		if (
			not waited["ok"]
			or battle.event_completed("location:chest_%d" % sample[2])
			or not battle.restore_snapshot(state)["ok"]
		):
			fail("Waiting on an m1 chest must leave it unopened")
			return
		var result: Dictionary = battle.open_chest(0)
		if (
			not result.get("claimed", false)
			or result["rewards"]["loot"][0]["item"]["templateId"] != sample[3]
			or not battle.event_completed("location:chest_%d" % sample[2])
		):
			fail("Opening each m1 chest must grant its original reward once: " + str(result))
			return
	print("PASS m1 chests: waiting preserves the chest and explicit opening grants the reward")
	quit(0)


func _zero(_limit: int) -> int:
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
