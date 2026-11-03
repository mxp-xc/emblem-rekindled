extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")
var _draws: int = 0


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = Battle.new(content, _roll)
	var state: Dictionary = battle.snapshot()
	var marked: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = 8
			actor["y"] = 20
		elif actor["id"] == 59:
			actor["x"] = 8
			actor["y"] = 21
			actor["hp"] = 1
			actor["attributes"]["defense"] = 0
			for held: Dictionary in actor["inventory"]:
				if held["templateId"] == actor["dropTemplateId"]:
					held["durability"] = 7
					marked = held.duplicate(true)
			actor["inventory"].append(
				{"id": "revival_drop_ring", "templateId": 80, "durability": 1}
			)
	if not _expect(
		battle.restore_snapshot(state)["ok"], "A legal ordinary marked carrier restores"
	):
		return
	var prepared: Dictionary = state.duplicate(true)
	var first: Dictionary = battle.attack_unit(0, 59)
	if not _expect(
		first["ok"] and first["revivals"].size() == 1 and first["rewards"]["loot"].size() == 1,
		"An ordinary lethal hit rewards the knockdown before the carrier revives"
	):
		return
	var received: Dictionary = first["rewards"]["loot"][0]["item"]
	if not _expect(
		(
			_has(battle.unit(59), marked["id"], 7)
			and received["id"] != marked["id"]
			and received["templateId"] == marked["templateId"]
			and received["durability"] == 7
		),
		"A revived carrier retains its marked current item while the recipient gets a distinct copy"
	):
		return
	var saved: Dictionary = Store.new(content).encode(battle)
	if not _expect(
		saved["ok"], "Both live held identities must satisfy the ordinary save contract"
	):
		return
	_draws = 0
	var cold: Dictionary = Store.new(content).decode(
		JSON.parse_string(JSON.stringify(saved["record"])), _roll
	)
	if not _expect(
		cold["ok"] and _draws == 0 and cold["battle"].snapshot() == battle.snapshot(),
		"A fresh Store restores independent recipient/source held state without initialization draws"
	):
		return
	battle = cold["battle"]
	for expected: int in [1, 2, 0]:
		if not _expect(
			battle.end_phase()["ok"] and battle.phase == expected,
			"The next ordinary turn grants another legal action"
		):
			return
		while battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"],
				"Other actors finish their normal phase without fixture combat"
			):
				return
	state = battle.snapshot()
	for actor: Dictionary in state["units"]:
		if actor["id"] == 59:
			# Only HP is controlled for the second actual lethal hit; no item is reinserted.
			actor["hp"] = 1
	if not _expect(
		battle.restore_snapshot(state)["ok"], "The revived carrier keeps its saved items"
	):
		return
	if not _expect(
		battle.equip_unit(0, received["id"])["ok"],
		"The separately received item can be equipped through the public inventory command"
	):
		return
	var final: Dictionary = battle.attack_unit(0, 59)
	if not _expect(
		(
			final["ok"]
			and final["revivals"].is_empty()
			and final["rewards"]["loot"].size() == 1
			and final["rewards"]["loot"][0]["item"] == marked
			and _has(battle.unit(0), received["id"], 6)
			and _has(battle.unit(0), marked["id"], 7)
			and not battle.unit(59)["visible"]
		),
		"The second real hit wears only the recipient copy and transfers the original at final death"
	):
		return
	var settled: Dictionary = battle.snapshot()
	if not _expect(
		not battle.attack_unit(0, 59)["ok"] and battle.snapshot() == settled,
		"Repeating the committed hit cannot duplicate either reward"
	):
		return
	saved = Store.new(content).encode(battle)
	if not _expect(saved["ok"], "Both awarded instances remain valid after final retirement"):
		return
	if not _boundaries(content, prepared, marked):
		return
	print(
		"PASS revival drops: retained source, unique cold items, independent wear, second actual drop"
	)
	quit(0)


func _boundaries(content: Dictionary, prepared: Dictionary, marked: Dictionary) -> bool:
	for scenario: Array in [
		["bag5warehouse39", 5, 39],
		["bag5warehouse40", 5, 40],
		["bag6warehouse39", 6, 39],
		["bag6warehouse40", 6, 40],
		["no_ring", 2, 0],
		["empty_ring", 2, 0],
		["marked_ring", 2, 0],
		["collisions", 5, 39]
	]:
		var state: Dictionary = prepared.duplicate(true)
		var name: String = scenario[0]
		for index: int in range(scenario[2]):
			state["warehouse"].append(
				{"id": "drop_capacity_warehouse_%d" % index, "templateId": 60, "durability": 1}
			)
		for actor: Dictionary in state["units"]:
			if actor["id"] == 0:
				while actor["inventory"].size() < scenario[1]:
					actor["inventory"].append(
						{
							"id": "drop_capacity_bag_%d" % actor["inventory"].size(),
							"templateId": 60,
							"durability": 1
						}
					)
				if name == "collisions":
					actor["inventory"][-1]["id"] = marked["id"] + ":drop_1"
			elif actor["id"] == 9 and name == "collisions":
				actor["inventory"].append(
					{"id": marked["id"] + ":drop_3", "templateId": 60, "durability": 1}
				)
			elif actor["id"] == 59:
				if name == "no_ring":
					actor["inventory"] = actor["inventory"].filter(
						func(held: Dictionary) -> bool: return held["templateId"] != 80
					)
				elif name == "empty_ring":
					for held: Dictionary in actor["inventory"]:
						if held["templateId"] == 80:
							held["durability"] = 0
				elif name == "marked_ring":
					actor["dropTemplateId"] = 80
				elif name == "collisions":
					actor["inventory"].append(
						{"id": marked["id"] + ":drop_4", "templateId": 60, "durability": 1}
					)
		if name == "collisions":
			state["warehouse"][0]["id"] = marked["id"] + ":drop_2"
		var existing: Dictionary = _identities(state)
		var battle: RefCounted = Battle.new(content, _roll)
		if not _expect(
			battle.restore_snapshot(state)["ok"], "Capacity and identity fixture restores: " + name
		):
			return false
		var result: Dictionary = battle.attack_unit(0, 59)
		if not _expect(result["ok"], "Every boundary uses an actual lethal ordinary hit: " + name):
			return false
		var loot: Array = result["rewards"]["loot"]
		var ordinary: bool = name in ["no_ring", "empty_ring", "marked_ring"]
		if ordinary:
			var expected_id: String = "revival_drop_ring" if name == "marked_ring" else marked["id"]
			if not _expect(
				(
					result["revivals"].is_empty()
					and not battle.unit(59)["visible"]
					and loot.size() == 1
					and loot[0]["item"]["id"] == expected_id
				),
				"No usable ring and marked80 retain their original transfer order: " + name
			):
				return false
		elif scenario[1] == 6 and scenario[2] == 40:
			if not _expect(
				(
					loot.is_empty()
					and result["revivals"].size() == 1
					and _has(battle.unit(59), marked["id"], 7)
					and _identities(battle.snapshot()).size() == existing.size() - 1
				),
				"Both full containers create no held item and leave the marked source intact"
			):
				return false
		else:
			if not _expect(
				(
					loot.size() == 1
					and loot[0]["destination"] == ("inventory" if scenario[1] == 5 else "warehouse")
					and not existing.has(loot[0]["item"]["id"])
					and loot[0]["item"]["durability"] == 7
					and _has(battle.unit(59), marked["id"], 7)
				),
				"Revival loot reaches available capacity with a globally unused identity: " + name
			):
				return false
		var saved: Dictionary = Store.new(content).encode(battle)
		if not _expect(saved["ok"], "Every held identity boundary can be saved: " + name):
			return false
		_draws = 0
		var cold: Dictionary = Store.new(content).decode(
			JSON.parse_string(JSON.stringify(saved["record"])), _roll
		)
		if not _expect(
			cold["ok"] and _draws == 0 and cold["battle"].snapshot() == battle.snapshot(),
			"Every capacity and collision result survives a cold JSON restore: " + name
		):
			return false
	return true


func _identities(state: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	for actor: Dictionary in state["units"]:
		for held: Dictionary in actor["inventory"]:
			ids[held["id"]] = true
	for held: Dictionary in state["warehouse"]:
		ids[held["id"]] = true
	return ids


func _has(actor: Dictionary, id: String, durability: int) -> bool:
	for held: Dictionary in actor["inventory"]:
		if held["id"] == id:
			return held["durability"] == durability
	return false


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
