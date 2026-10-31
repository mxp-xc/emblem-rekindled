extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var script: Script = load("res://gameplay/battle_state.gd")
	var low: RefCounted = script.new(content, func(_limit: int) -> int: return 0)
	var high: RefCounted = script.new(content, func(limit: int) -> int: return limit - 1)
	if (
		low.unit(10)["inventory"][0]["templateId"] != 23
		or high.unit(10)["inventory"][0]["templateId"] != 27
	):
		fail("New battles must draw weighted equipment choices, not reuse a prepared snapshot")
		return
	# Original base row 18 HP25 + floor(50% * level1), then independent 0..2.
	if low.unit(10)["maxHp"] != 25 or high.unit(10)["maxHp"] != 27:
		fail(
			(
				"NPC HP must include the original independent 0..2 initialization noise: got %s/%s"
				% [low.unit(10)["maxHp"], high.unit(10)["maxHp"]]
			)
		)
		return
	if (
		low.unit(95)["formal"]
		or low.unit(95)["sourceId"] != 2
		or low.unit(95)["growthTemplateId"] != 12
	):
		fail("Temporary troops must retain source identity and use runtime class growth")
		return
	if not low.unit(0)["formal"] or low.unit(0)["hp"] != 30 or high.unit(0)["hp"] != 30:
		fail("Formal character initialization must not acquire NPC random noise")
		return
	var duplicate_content: Dictionary = content.duplicate(true)
	for spawn: Dictionary in duplicate_content["spawns"]:
		if spawn["id"] == 64:
			spawn["itemChoices"] = [22, 0, 0]
	var duplicate_items: RefCounted = script.new(
		duplicate_content, func(_limit: int) -> int: return 0
	)
	var inventory: Array = duplicate_items.unit(64)["inventory"]
	if (
		inventory.size() != 2
		or inventory[0]["id"] == inventory[1]["id"]
		or inventory[0]["templateId"] != 22
		or inventory[1]["templateId"] != 22
	):
		fail("Two held items of one template must remain distinct instances")
		return
	print("PASS new battle: original random stats/equipment, temporary identity, item instances")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
