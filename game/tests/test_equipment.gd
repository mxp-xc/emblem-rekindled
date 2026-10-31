extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 96:
			spawn["itemChoices"] = [13, 1, 0]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	if not battle.has_method("equip_unit"):
		fail("Equipment command is missing")
		return
	var knight: Dictionary = battle.unit(96)
	var sword_id: String = knight["inventory"][1]["id"]
	if not battle.equip_unit(96, sword_id)["ok"]:
		fail("Knight's permitted sword must be equippable")
		return
	knight = battle.unit(96)
	if (
		knight["equippedInstanceId"] != sword_id
		or knight["inventory"][0]["id"] != sword_id
		or knight["action"] != 0
	):
		fail("Equip must keep the held instance and action available")
		return
	var before: Dictionary = battle.snapshot()
	if battle.equip_unit(0, sword_id)["ok"] or battle.snapshot() != before:
		fail("Another unit's item cannot be equipped")
		return
	var herb_id: String = battle.unit(0)["inventory"][1]["id"]
	if battle.equip_unit(0, herb_id)["ok"] or battle.snapshot() != before:
		fail("A consumable cannot bypass equipment restrictions")
		return
	print("PASS equipment: class restriction, ownership, instance identity, no action consumed")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
