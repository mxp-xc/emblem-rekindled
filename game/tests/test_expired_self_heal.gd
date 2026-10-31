extends SceneTree

const Battle = preload("res://gameplay/battle_state.gd")
const Store = preload("res://persistence/battle_store.gd")


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = _prepared(content)
	var holy: Dictionary = battle.unit(0)["inventory"][0].duplicate(true)
	var herb: Dictionary = battle.unit(0)["inventory"][1].duplicate(true)
	var result: Dictionary = battle.use_item(0, holy["id"])
	if (
		not result["ok"]
		or result["expiredItem"]["templateId"] != 9
		or battle.unit(0)["inventory"] != [herb]
		or battle.unit(0)["equippedInstanceId"] != ""
	):
		fail(
			"Exhausted self-healing holy sword must leave only the untouched herb and no equipment"
		)
		return
	var archive: RefCounted = Store.new(content)
	var saved: Dictionary = archive.encode(battle)
	var loaded: Dictionary = archive.decode(saved.get("record", {}))
	if not saved["ok"] or not loaded["ok"]:
		fail("The self-healing action boundary must remain a readable save")
		return
	battle = loaded["battle"]
	if not _cycle(battle, false)["ok"]:
		return
	if (
		battle.round_number != 2
		or "attack" in battle.actions_for(0)
		or not battle.attack_weapons(0).is_empty()
		or battle.unit_information(0)["attack"] != "--"
		or battle.unit(0)["inventory"] != [herb]
	):
		fail("Crossing a full round must not restore exhausted weapon effects or an attack command")
		return
	var before: Dictionary = battle.snapshot()
	if battle.attack_unit(0, 59)["ok"] or battle.snapshot() != before:
		fail("An exhausted weapon must not allow an active attack or mutate the battle")
		return
	var strikes: Dictionary = _cycle(battle, true)
	if not strikes["ok"]:
		return
	for strike: Dictionary in strikes["combat"]["strikes"]:
		if strike["attacker"] != 59:
			fail("A living unarmed defender must not counter with the exhausted holy sword")
			return
	if battle.unit(0)["inventory"] != [herb] or battle.unit(0)["equippedInstanceId"] != "":
		fail("Enemy combat and cleanup must not spend herb durability or retain ghost equipment")
		return
	saved = archive.encode(battle)
	loaded = archive.decode(saved.get("record", {}))
	if not loaded["ok"] or loaded["battle"].snapshot() != battle.snapshot():
		fail("The post-counter boundary must restore exactly, including the untouched herb")
		return
	var corrupt: Dictionary = saved["record"].duplicate(true)
	for actor: Dictionary in corrupt["state"]["units"]:
		if actor["id"] == 0:
			actor["equippedInstanceId"] = holy["id"]
	if archive.decode(corrupt)["ok"]:
		fail("A dangling exhausted equipment reference must be rejected on load")
		return
	battle = _prepared(content, true)
	result = battle.use_item(0, battle.unit(0)["inventory"][0]["id"])
	if (
		not result["ok"]
		or battle.unit(0)["equippedInstanceId"] != "replacement-iron"
		or battle.unit(0)["inventory"][0]["templateId"] != 1
		or battle.unit(0)["inventory"][1]["templateId"] != 60
		or battle.unit(0)["inventory"][1]["durability"] != 3
	):
		fail("Self-heal exhaustion must equip the first eligible held replacement, preserving herb")
		return
	print("PASS exhausted self-heal: valid equipment, full round, no ghost counter, herb and save")
	quit(0)


func _prepared(content: Dictionary, replacement: bool = false) -> RefCounted:
	var battle: RefCounted = Battle.new(content, func(limit: int) -> int: return limit - 1)
	var state: Dictionary = battle.snapshot()
	state["events"] = {"opening": true, "reinforcements": true, "level_tutorial": true}
	for actor: Dictionary in state["units"]:
		if actor["id"] == 0:
			actor["x"] = 8
			actor["y"] = 20
			actor["hp"] -= 10
			actor["inventory"][0]["durability"] = 1
			if replacement:
				actor["inventory"].append(
					{"id": "ineligible-staff", "templateId": 53, "durability": 23}
				)
				actor["inventory"].append(
					{"id": "replacement-iron", "templateId": 1, "durability": 30}
				)
		elif actor["id"] == 59:
			actor["x"] = 8
			actor["y"] = 21
		elif actor["faction"] in [1, 2]:
			actor["visible"] = false
	if not battle.restore_snapshot(state)["ok"]:
		fail("The controlled self-heal boundary must be a valid battle record")
	return battle


func _cycle(battle: RefCounted, attack: bool) -> Dictionary:
	var combat: Dictionary = {}
	if not battle.end_phase()["ok"]:
		fail("The stable player phase must advance after self-healing")
		return {"ok": false}
	while battle.phase != 0:
		while battle.automatic_actor() >= 0:
			var id: int = battle.automatic_actor()
			if not battle.begin_automatic_action(id)["ok"]:
				fail("The enemy must begin a legal automatic action")
				return {"ok": false}
			if attack and id == 59:
				var preview: Dictionary = battle.attack_preview(59, 0)
				if not preview["ok"] or preview["forecasts"]["59"]["canCounter"]:
					fail("Enemy forecast must show that the unarmed defender cannot counter")
					return {"ok": false}
				combat = battle.attack_unit(59, 0)
				if not combat["ok"]:
					fail("The enemy strike must settle through the actual battle command")
					return {"ok": false}
			elif not battle.wait_unit(id)["ok"]:
				fail("The automatic wait must finish its action")
				return {"ok": false}
		if not battle.end_phase()["ok"]:
			fail("Completed automatic phases must return to the player")
			return {"ok": false}
	return {"ok": not attack or not combat.is_empty(), "combat": combat}


func fail(message: String) -> void:
	push_error(message)
	quit(1)
