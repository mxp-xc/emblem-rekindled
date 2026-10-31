extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not content.get("ok", false):
		fail("World shop fixture requires valid chapter content: " + str(content))
		return
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 23]
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	battle.move_unit(0, Vector2i(8, 24))
	battle.wait_unit(0)
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	var inventory: RefCounted = load("res://gameplay/world_inventory.gd").new(content)
	if not inventory.has_method("shop_stock"):
		fail("The local world shop must use the original node's seven-item stock")
		return
	var stock: Array = inventory.shop_stock(progress)
	if (
		stock.map(func(item: Dictionary) -> int: return int(item["templateId"]))
		!= [1, 2, 3, 11, 53, 54, 60]
	):
		fail(
			"Node zero stock comes from the current party node, not the map cursor or guessed goods"
		)
		return
	var before: Dictionary = progress.duplicate(true)
	var bought: Dictionary = inventory.apply(progress, "buy", {"unit": 0, "template": 1})
	if not bought["ok"]:
		fail("The ordinary local shop sells iron swords without payment activation")
		return
	var acquired: Dictionary = bought["progress"]
	var hero: Dictionary = inventory.actor(acquired, 0)
	var iron: Dictionary = hero["inventory"][-1]
	if (
		acquired["gold"] != 5000
		or int(iron["templateId"]) != 1
		or int(iron["durability"]) != 30
		or hero["action"] != 0
		or progress != before
	):
		fail("Buying charges the original price and creates one full-use owned instance atomically")
		return
	var again: Dictionary = inventory.apply(acquired, "buy", {"unit": 0, "template": 1})
	if (
		not again["ok"]
		or inventory.actor(again["progress"], 0)["inventory"][-1]["id"] == iron["id"]
	):
		fail("The fixed original stock is repeatable, with independent owned item identities")
		return
	if not inventory.has_method("sale_price"):
		fail("The local shop must expose original remaining-use sale prices")
		return
	if inventory.sale_price({"templateId": 53, "durability": 1}) != 54:
		fail("A one-use healing staff sells for the original floored price 54")
		return
	var sword: Dictionary = inventory.actor(progress, 0)["inventory"][0]
	var sold: Dictionary = inventory.apply(progress, "sell", {"unit": 0, "item": sword["id"]})
	if not sold["ok"] or sold["progress"]["gold"] != 12000:
		fail("The currently equipped holy sword may be sold for its original 6000 gold price")
		return
	if inventory.actor(sold["progress"], 0)["equippedInstanceId"] != "":
		fail("A world transaction must never persist a reference to a sold held item")
		return
	var keyed: Dictionary = progress.duplicate(true)
	inventory.actor(keyed, 0)["inventory"].append(
		{"id": "test:key", "templateId": 64, "durability": 1}
	)
	var opened: Dictionary = inventory.apply(keyed, "open_shop", {"unit": 0})
	if not opened["ok"] or not opened.get("special", false):
		fail("Entering a local shop with the original key must choose its special stock")
		return
	if inventory.actor(opened["progress"], 0)["inventory"].size() != 2 or keyed["gold"] != 6000:
		fail("The key is consumed on entry, even without purchasing, without charging gold")
		return
	var reopened: Dictionary = inventory.apply(opened["progress"], "open_shop", {"unit": 0})
	if not reopened["ok"] or reopened.get("special", true):
		fail("Leaving and reopening without a key returns to ordinary local stock")
		return
	var full: Dictionary = progress.duplicate(true)
	var full_hero: Dictionary = inventory.actor(full, 0)
	while full_hero["inventory"].size() < 6:
		full_hero["inventory"].append(
			{
				"id": "test:full_%d" % full_hero["inventory"].size(),
				"templateId": 60,
				"durability": 1
			}
		)
	var routed: Dictionary = inventory.apply(full, "buy", {"unit": 0, "template": 1})
	if (
		not routed["ok"]
		or routed["destination"] != "warehouse"
		or routed["progress"]["warehouse"].size() != 1
		or inventory.actor(routed["progress"], 0)["inventory"].size() != 6
	):
		fail("An affordable purchase goes to the warehouse when the six-item bag is full")
		return
	for index: int in range(40):
		full["warehouse"].append(
			{"id": "test:warehouse_%d" % index, "templateId": 60, "durability": 1}
		)
	var unchanged: Dictionary = full.duplicate(true)
	var denied: Dictionary = inventory.apply(full, "buy", {"unit": 0, "template": 1})
	if denied["ok"] or denied["error"] != "WAREHOUSE_FULL" or full != unchanged:
		fail("Two full containers reject a purchase without charging gold or adding a partial item")
		return
	full["gold"] = 0
	denied = inventory.apply(full, "buy", {"unit": 0, "template": 1})
	if denied["ok"] or denied["error"] != "INSUFFICIENT_GOLD" or full["gold"] != 0:
		fail("Insufficient funds cannot buy even when a full container has not yet been checked")
		return
	var ineligible: Dictionary = inventory.apply(progress, "buy", {"unit": 0, "template": 53})
	if (
		not ineligible["ok"]
		or ineligible["progress"]["gold"] != 3500
		or int(inventory.actor(ineligible["progress"], 0)["inventory"][-1]["templateId"]) != 53
	):
		fail("The gray healing staff is still purchasable by a character who cannot equip it")
		return
	var capped: Dictionary = progress.duplicate(true)
	capped["gold"] = 9999990
	var herb: Dictionary = inventory.actor(capped, 0)["inventory"][1]
	herb["durability"] = 1
	var capped_sale: Dictionary = inventory.apply(capped, "sell", {"unit": 0, "item": herb["id"]})
	if not capped_sale["ok"] or capped_sale["progress"]["gold"] != 9999999:
		fail("Selling still removes the held item while capping gold at the original limit")
		return
	var store: RefCounted = load("res://persistence/battle_store.gd").new(content)
	for candidate: Dictionary in [
		acquired,
		again["progress"],
		sold["progress"],
		opened["progress"],
		routed["progress"],
		ineligible["progress"],
		capped_sale["progress"]
	]:
		if not store.encode_progress(candidate)["ok"]:
			fail(
				"Every committed world shop result must satisfy the existing saved-progress contract"
			)
			return
	print(
		"PASS world shop: stock, repeated buys, identity, sale price, key, caps, eligibility, valid saves"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
