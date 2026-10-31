extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for destination: String in ["inventory", "warehouse", "full"]:
		var battle: RefCounted = Battle.new(content, func(_limit: int) -> int: return 0)
		var state: Dictionary = battle.snapshot()
		var dropped: Dictionary
		for actor: Dictionary in state["units"]:
			if actor["id"] == 0:
				actor["x"] = 8
				actor["y"] = 20
				if destination != "inventory":
					while actor["inventory"].size() < 6:
						actor["inventory"].append(
							{
								"id": "capacity:hero:%d" % actor["inventory"].size(),
								"templateId": 60,
								"durability": 1
							}
						)
			elif actor["id"] == 58:
				actor["x"] = 8
				actor["y"] = 21
				actor["hp"] = 1
				actor["inventory"][0]["durability"] = 7
				dropped = actor["inventory"][0].duplicate(true)
		if destination == "full":
			for index: int in range(40):
				state["warehouse"].append(
					{"id": "capacity:warehouse:%d" % index, "templateId": 60, "durability": 1}
				)
		if not battle.restore_snapshot(state)["ok"]:
			fail("The source equipped-drop capacity scenario must restore")
			return
		var weapon: String = battle.unit(0)["equippedInstanceId"]
		var result: Dictionary = battle.attack_unit(0, 58)
		if not result["ok"] or battle.unit(58)["hp"] != 0:
			fail("The source marked weapon carrier must be killed by the actual combat command")
			return
		var loot: Array = result["rewards"]["loot"]
		if destination == "full":
			if (
				not loot.is_empty()
				or battle.unit(58)["inventory"] != [dropped]
				or battle.unit(58)["equippedInstanceId"] != dropped["id"]
			):
				fail(
					"If both capacities are full, the item and its owner's reference must stay intact"
				)
				return
		else:
			if (
				loot.size() != 1
				or loot[0]["destination"] != destination
				or loot[0]["item"] != dropped
			):
				fail(
					"The marked held instance and current durability must reach the available destination"
				)
				return
			if (
				not battle.unit(58)["inventory"].is_empty()
				or not battle.unit(58)["equippedInstanceId"].is_empty()
			):
				fail(
					"A dead carrier cannot retain an equipment reference to the transferred instance"
				)
				return
		if battle.unit(0)["equippedInstanceId"] != weapon:
			fail("Receiving loot must not auto-equip the recipient after source combat cleanup")
			return
		var path := "user://test_loot_record_%d.json" % Time.get_ticks_usec()
		var store: RefCounted = Store.new(content, path)
		if not store.write(battle)["ok"]:
			fail("A completed kill/drop is an ordinary stable save point")
			return
		var restored: Dictionary = store.read()
		if not restored["ok"] or restored["battle"].snapshot() != battle.snapshot():
			fail(
				"Save/read after the equipped drop must preserve the entire battle: " + destination
			)
			return
		if destination != "full":
			var valid: Dictionary = battle.snapshot()
			# Reproduce the invalid live producer observed in the full Root run.
			battle.get("_units")[58]["equippedInstanceId"] = dropped["id"]
			if (
				store.write(battle)["ok"]
				or not store.read()["ok"]
				or store.read()["battle"].snapshot() != valid
			):
				fail(
					"An invalid live equipment reference must not replace the last readable archive"
				)
				return
		DirAccess.remove_absolute(path)
	print(
		"PASS loot record: equipped-drop ownership, inventory/warehouse/full, stable disk roundtrip"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
