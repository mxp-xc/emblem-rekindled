extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not content.get("ok", false):
		fail("World inventory fixture requires valid chapter content: " + str(content))
		return
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	var original: Dictionary = progress.duplicate(true)
	var path: String = "res://gameplay/world_inventory.gd"
	if not FileAccess.file_exists(path):
		fail("The world inventory must support a protected deposit without tactical actions")
		return
	var inventory: RefCounted = load(path).new(content)
	var hero: Dictionary = actor(progress, 0)
	var sword: Dictionary = hero["inventory"][0].duplicate(true)
	var deposited: Dictionary = inventory.apply(
		progress, "deposit", {"unit": 0, "item": sword["id"]}
	)
	if not deposited["ok"]:
		fail("A world deposit must accept the owned holy sword")
		return
	var next: Dictionary = deposited["progress"]
	if (
		next["warehouse"] != [sword]
		or actor(next, 0)["inventory"].size() != 1
		or actor(next, 0)["equippedInstanceId"] != ""
		or actor(next, 0)["action"] != 0
		or next["gold"] != 6000
		or progress != original
	):
		fail(
			"Deposit preserves item identity/uses and funds/actions, preparing a separate valid state"
		)
		return
	var store: RefCounted = load("res://persistence/battle_store.gd").new(content)
	if not store.encode_progress(next)["ok"]:
		fail("A completed deposit must remain a valid restorable world record")
		return
	var taken: Dictionary = inventory.apply(next, "take", {"unit": 9, "item": sword["id"]})
	if not taken["ok"]:
		fail("A non-adjacent formal companion may retrieve a weapon she cannot equip")
		return
	var retrieved: Dictionary = taken["progress"]
	if (
		not retrieved["warehouse"].is_empty()
		or actor(retrieved, 9)["inventory"][-1] != sword
		or actor(retrieved, 9)["equippedInstanceId"] != ""
		or actor(retrieved, 9)["action"] != 0
		or next["warehouse"] != [sword]
		or not store.encode_progress(retrieved)["ok"]
	):
		fail(
			"Retrieval preserves uses, identity, ineligible ownership and the separate valid input"
		)
		return
	var staff: Dictionary = actor(retrieved, 9)["inventory"][0].duplicate(true)
	var traded: Dictionary = inventory.apply(
		retrieved, "trade", {"unit": 9, "partner": 0, "item": staff["id"], "exchange": ""}
	)
	if not traded["ok"]:
		fail("World transfer may move a staff to a non-adjacent ineligible companion")
		return
	var exchanged: Dictionary = traded["progress"]
	if (
		actor(exchanged, 0)["inventory"][-1] != staff
		or actor(exchanged, 9)["inventory"].size() != 2
		or actor(exchanged, 0)["action"] != 0
		or exchanged["gold"] != 6000
		or not store.encode_progress(exchanged)["ok"]
	):
		fail(
			"World transfer preserves item uses and actions without tactical adjacency/equip checks"
		)
		return
	var ordered: Dictionary = original.duplicate(true)
	var ordered_hero: Dictionary = actor(ordered, 0)
	ordered_hero["inventory"].push_front({"id": "test:staff", "templateId": 53, "durability": 23})
	ordered_hero["inventory"].insert(2, {"id": "test:iron", "templateId": 1, "durability": 30})
	# The holy sword is still ahead of iron, so put iron first among usable weapons.
	var holy: Dictionary = ordered_hero["inventory"][1]
	ordered_hero["inventory"].erase(holy)
	ordered_hero["inventory"].append(holy)
	var finished: Dictionary = inventory.apply(ordered, "finish", {"unit": 0})
	if not finished["ok"] or actor(finished["progress"], 0)["equippedInstanceId"] != "test:iron":
		fail(
			"Leaving world item screens equips the first eligible held weapon in its current order"
		)
		return
	var full: Dictionary = original.duplicate(true)
	for index: int in range(40):
		full["warehouse"].append(
			{"id": "test:warehouse_%d" % index, "templateId": 60, "durability": 2}
		)
	for member: Dictionary in full["party"]:
		while member["inventory"].size() < 6:
			member["inventory"].append(
				{
					"id": "test:bag_%d_%d" % [member["id"], member["inventory"].size()],
					"templateId": 60,
					"durability": 1
				}
			)
	var full_before: Dictionary = full.duplicate(true)
	var denied: Dictionary = inventory.apply(full, "deposit", {"unit": 0, "item": sword["id"]})
	if denied["ok"] or denied["error"] != "WAREHOUSE_FULL" or full != full_before:
		fail("Forty-item warehouse rejects a deposit without changing either inventory")
		return
	denied = inventory.apply(full, "take", {"unit": 0, "item": "test:warehouse_0"})
	if denied["ok"] or denied["error"] != "INVENTORY_FULL" or full != full_before:
		fail("Six-item actor rejects retrieval without changing either inventory")
		return
	var swap: Dictionary = inventory.apply(
		full, "trade", {"unit": 0, "partner": 9, "item": sword["id"], "exchange": staff["id"]}
	)
	if (
		not swap["ok"]
		or actor(swap["progress"], 0)["inventory"].size() != 6
		or actor(swap["progress"], 9)["inventory"].size() != 6
	):
		fail("Two full six-item bags still exchange existing items")
		return
	var round_trip: Dictionary = original.duplicate(true)
	actor(round_trip, 0)["inventory"].insert(
		1, {"id": "test:round_iron", "templateId": 1, "durability": 30}
	)
	var first_swap: Dictionary = inventory.apply(
		round_trip, "trade", {"unit": 0, "partner": 9, "item": sword["id"], "exchange": staff["id"]}
	)
	var second_swap: Dictionary = inventory.apply(
		first_swap["progress"],
		"trade",
		{"unit": 0, "partner": 9, "item": staff["id"], "exchange": sword["id"]}
	)
	if actor(second_swap["progress"], 0)["inventory"] != actor(round_trip, 0)["inventory"]:
		fail(
			"World swap-back must restore exact slot order before exit, without early re-equipping"
		)
		return
	var exited: Dictionary = inventory.apply(
		second_swap["progress"], "finish", {"unit": 0, "partner": 9}
	)
	if actor(exited["progress"], 0)["equippedInstanceId"] != sword["id"]:
		fail(
			"Leaving after a swap-back must equip the original first weapon, not the intervening iron"
		)
		return
	print(
		"PASS world inventory: identity, capacities, ineligible transfers, slot order and exit equipment"
	)
	quit(0)


func actor(progress: Dictionary, id: int) -> Dictionary:
	for member: Dictionary in progress["party"]:
		if member["id"] == id:
			return member
	return {}


func fail(message: String) -> void:
	push_error(message)
	quit(1)
