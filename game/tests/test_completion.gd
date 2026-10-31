extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	if not battle.has_method("complete_victory"):
		fail("Route choice and campaign completion are missing")
		return
	var state: Dictionary = battle.snapshot()
	for unit: Dictionary in state["units"]:
		if unit["id"] == 0:
			unit["level"] = 3
			unit["experience"] = 42
			unit["hp"] = 7
			unit["inventory"][0]["durability"] = 8
			var herb: Dictionary = unit["inventory"].pop_back()
			herb["durability"] = 2
			state["warehouse"].append(herb)
	if not battle.restore_snapshot(state)["ok"]:
		fail("Completion setup must be a valid stable battle")
		return
	battle.configure_commander(0, true, true)
	var store: RefCounted = load("res://persistence/battle_store.gd").new(
		content, "user://test_completion_%d.json" % Time.get_ticks_usec()
	)
	store.write(battle)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var result: Dictionary = battle.complete_victory(0)
	if not result["ok"]:
		fail("A valid victory route must settle successfully")
		return
	var progress: Dictionary = result["progress"]
	if (
		progress["gold"] != 6000
		or progress["route"] != 0
		or progress["worldNode"] != 0
		or progress["commander"] != 0
		or progress["commandPolicy"] != 5
		or progress["party"].size() != 2
	):
		fail(
			"Original gold, route, world node and commander state must carry into completed progress"
		)
		return
	for unit: Dictionary in progress["party"]:
		if (
			not unit["formal"]
			or unit["hp"] != unit["maxHp"]
			or unit["action"] != 0
			or unit["flags"] != 0
			or not unit["visible"]
		):
			fail("Completion must retain only formal heroes, heal and clear their statuses/actions")
			return
		if (
			unit["id"] == 0
			and (
				unit["level"] != 3
				or unit["experience"] != 42
				or unit["inventory"][0]["durability"] != 8
			)
		):
			fail("Formal growth and held durability cannot reset at completion")
			return
	if (
		progress["warehouse"][0]["durability"] != 2
		or battle.complete_victory(0)["progress"] != progress
		or battle.complete_victory(2)["ok"]
	):
		fail("Repeated completion must retain the chosen route and never duplicate reward")
		return
	var encoded: Dictionary = store.encode_progress(progress)
	var restored: Dictionary = store.decode(JSON.parse_string(JSON.stringify(encoded["record"])))
	if not restored["ok"] or restored["progress"] != progress:
		fail("Completed progress must survive a canonical JSON roundtrip")
		return
	var corrupt: Dictionary = encoded["record"].duplicate(true)
	corrupt["progress"]["party"][0]["id"] = 95
	if store.write_progress(corrupt["progress"])["ok"] or not store.read().has("battle"):
		fail("Invalid completed progress must preserve the previous valid battle record")
		return
	if not store.write_progress(progress)["ok"] or store.read()["progress"] != progress:
		fail("The same save slot must persist and restore the completed route")
		return
	DirAccess.remove_absolute(store.path)
	print(
		"PASS completion: roster, recovery, growth/items, route, one reward, progress persistence"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
