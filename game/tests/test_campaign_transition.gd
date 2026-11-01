extends SceneTree


func _initialize() -> void:
	var loader: RefCounted = load("res://app/chapter_content.gd").new()
	var first: Dictionary = loader.load_chapter("res://content/chapter_1/chapter.json")
	var second: Dictionary = loader.load_chapter(
		"res://content/chapter_1/chapter.json",
		"m1",
		{
			"party":
			[{"id": 0, "sourceId": 0, "classId": 0}, {"id": 9, "sourceId": 9, "classId": 4}],
			"worldStep": 1,
			"partyOrder": [9, 0],
			"route": 0
		}
	)
	if not first["ok"] or not second["ok"]:
		fail(
			(
				"Both chapter battles must load their own validated content: "
				+ str(second.get("error", ""))
			)
		)
		return
	if (
		second["map"]["width"] != 22
		or second["map"]["height"] != 22
		or second["entry"]["battleId"] != "m1"
	):
		fail("The next battle must use the original 22x22 Sofia Mountains map and m1 identity")
		return
	var battle_type: Script = load("res://gameplay/battle_state.gd")
	var opening: RefCounted = battle_type.new(first, func(_limit: int) -> int: return 0)
	opening.complete_event("level_tutorial")
	opening.win_with_assistance()
	var progress: Dictionary = opening.complete_victory(0)["progress"]
	if progress["party"].map(func(actor: Dictionary) -> int: return int(actor["id"])) != [0, 9]:
		fail("Settlement must return recruit order independently of native battle iteration order")
		return
	progress["gold"] = 12345
	for actor: Dictionary in progress["party"]:
		if actor["id"] == 0:
			actor["level"] = 4
			actor["experience"] = 42
			actor["proficiency"] = 50
			actor["attributes"]["strength"] = 13
			actor["inventory"][0]["durability"] = 7
			actor["y"] = 24
	progress["warehouse"] = [{"id": "chapter_1:unit_65:item_0", "templateId": 1, "durability": 17}]
	var before: Dictionary = progress.duplicate(true)
	var battle: RefCounted = battle_type.new(second, func(_limit: int) -> int: return 0)
	if not battle.begin_from_progress(progress)["ok"] or progress != before:
		fail("Entering m1 must atomically inherit the party without modifying the world record")
		return
	var alm: Dictionary = battle.unit(0)
	if (
		alm["level"] != 4
		or alm["experience"] != 42
		or alm["proficiency"] != 50
		or alm["attributes"]["strength"] != 13
		or alm["inventory"][0]["durability"] != 7
		or alm["x"] != 1
		or alm["y"] != 15
		or alm["visible"]
		or battle.unit(9)["visible"]
		or not battle.unit(6)["visible"]
		or not battle.unit(6)["formal"]
		or battle.unit(6)["maxHp"] != 25
		or battle.gold != 12345
		or battle.snapshot()["warehouse"] != progress["warehouse"]
		or not battle.event_completed("level_tutorial")
	):
		fail(
			"Cultivation/items/funds must survive while battle-local deployment and Fols come from m1"
		)
		return
	var state: Dictionary = battle.snapshot()
	var invalid: Dictionary = progress.duplicate(true)
	invalid["warehouse"].append(alm["inventory"][0].duplicate(true))
	var rejected: RefCounted = battle_type.new(second)
	var untouched: Dictionary = rejected.snapshot()
	if rejected.begin_from_progress(invalid)["ok"] or rejected.snapshot() != untouched:
		fail("Duplicate held identities must reject before publishing any inherited state")
		return
	var events: Array = advance_round(battle)
	if events.size() != 1 or events[0]["sequence"] != "allied_arrival" or battle.round_number != 2:
		fail("The first enemy phase must reveal the two allied entrance groups exactly once")
		return
	for id: int in [0, 9, 95, 96, 97, 98]:
		if not battle.unit(id)["visible"]:
			fail("Every original first-round arrival must become actionable")
			return
	var store: RefCounted = load("res://persistence/battle_store.gd").new(first)
	var encoded: Dictionary = store.encode(battle, 77)
	if not encoded["ok"] or encoded["record"]["battleId"] != "m1":
		fail("The shared repository must encode the actual battle rather than firstBattle")
		return
	var decoded: Dictionary = store.decode(encoded["record"])
	if (
		not decoded["ok"]
		or decoded["battle"].snapshot() != battle.snapshot()
		or decoded["elapsedMinutes"] != 77
		or not decoded["battle"].event_completed("level_tutorial")
	):
		fail("m1 continue must restore deployment, event flags, route context and time")
		return
	battle = decoded["battle"]
	events = advance_round(battle)
	if events.size() != 1 or events[0]["sequence"] != "enemy_arrival" or battle.round_number != 3:
		fail("Restoring round two must not replay allies and must retain the later enemy event")
		return
	for id: int in [63, 59, 60]:
		if not battle.unit(id)["visible"]:
			fail("The original second-round enemy ambush must be revealed")
			return
	if not battle.win_with_assistance()["ok"]:
		fail("The restored player boundary must remain playable")
		return
	var completed: Dictionary = battle.complete_victory(1)["progress"]
	if (
		completed["completedBattle"] != "m1"
		or completed["worldNode"] != 1
		or completed["worldStep"] != 2
		or completed["route"] != 1
		or completed["party"].size() != 3
		or (
			completed["party"].map(func(actor: Dictionary) -> int: return int(actor["id"]))
			!= [0, 9, 6]
		)
		or completed["gold"] != 13345
		or not completed.get("levelTutorialSeen", false)
		or not battle.complete_victory(1).get("alreadyComplete", false)
		or battle.complete_victory(0)["ok"]
	):
		fail(
			"m1 must settle once at node1, retain three formal members and select the Silque route"
		)
		return
	var world: Dictionary = store.encode_progress(completed)
	if (
		not world["ok"]
		or not store.decode(world["record"])["ok"]
		or world["record"]["battleId"] != "m1"
		or store.decode(JSON.parse_string(JSON.stringify(world["record"])))["progress"] != completed
	):
		fail("The completed second battle must round-trip as an independent world record")
		return
	var visited: Dictionary = completed.duplicate(true)
	visited["worldLocation"] = 0
	var inventory: RefCounted = load("res://gameplay/world_inventory.gd").new(second)
	if inventory.shop_stock(visited) != inventory.shop_stock(progress):
		fail("Visiting node zero must use that location's original shop stock")
		return
	if not store.encode_progress(visited)["ok"]:
		fail("A visited route location must remain savable without changing completion")
		return
	visited["worldLocation"] = 8
	if store.encode_progress(visited)["ok"]:
		fail("The not-yet-entered next node cannot be forged as a visited save location")
		return
	var old: Dictionary = store.encode_progress(progress)["record"]
	old["progress"].erase("worldStep")
	old["progress"].erase("levelTutorialSeen")
	if not store.decode(old)["ok"] or store.decode(old)["progress"]["worldStep"] != 1:
		fail(
			"Existing first-battle world records must still resume at their original route frontier"
		)
		return
	var legacy: RefCounted = battle_type.new(second)
	if (
		not legacy.begin_from_progress(store.decode(old)["progress"])["ok"]
		or legacy.event_completed("level_tutorial")
	):
		fail("An old world without a tutorial marker remains readable without inventing a read")
		return
	var bad_tutorial: Dictionary = old.duplicate(true)
	bad_tutorial["progress"]["levelTutorialSeen"] = "true"
	if store.decode(bad_tutorial)["ok"]:
		fail("Malformed cross-battle tutorial state must reject before replacing a record")
		return
	var unknown: Dictionary = encoded["record"].duplicate(true)
	unknown["battleId"] = "m99"
	if (
		store.decode(unknown)["ok"]
		or battle_type.new(second).restore_snapshot(state)["ok"] == false
	):
		fail("Unknown battles must reject while a valid m1 snapshot stays restorable")
		return
	print(
		"PASS campaign transition: inheritance, item identities, two arrivals, m1 save and settlement"
	)
	quit(0)


func advance_round(battle: RefCounted) -> Array:
	var events: Array = []
	var advanced: Dictionary = battle.end_phase()
	if not advanced["ok"]:
		fail("Cannot begin the next phase: " + str(advanced))
		return events
	while battle.phase != 0:
		while battle.automatic_actor() >= 0:
			battle.wait_unit(battle.automatic_actor())
		advanced = battle.end_phase()
		if not advanced["ok"]:
			fail("Completed automatic actors must release the next phase")
			return events
		events.append_array(advanced["events"])
	return events


func fail(message: String) -> void:
	push_error(message)
	quit(1)
