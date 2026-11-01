extends RefCounted

const Combat = preload("res://gameplay/combat_rules.gd")
const Inventory = preload("res://gameplay/unit_inventory.gd")
var _inventory: RefCounted
var _rules: Dictionary
var _items: Dictionary = {}


func _init(content: Dictionary) -> void:
	_rules = content["rules"]
	for item: Dictionary in _rules["itemTemplates"]:
		_items[int(item["id"])] = item
	_inventory = Inventory.new(Combat.new(content["rules"], content["map"]["terrain"]), Callable())


func apply(progress: Dictionary, operation: String, details: Dictionary) -> Dictionary:
	var next: Dictionary = progress.duplicate(true)
	var owner: Dictionary = actor(next, int(details.get("unit", -1)))
	if owner.is_empty():
		return {"ok": false, "error": "UNIT_NOT_IN_PARTY"}
	if operation == "open_shop":
		var special: bool = _inventory.consume_template(owner, 64)
		return {"ok": true, "progress": next, "special": special}
	if operation == "sell":
		var held: Dictionary = _inventory.held_item(owner, details.get("item", ""))
		if held.is_empty():
			return {"ok": false, "error": "ITEM_NOT_OWNED"}
		next["gold"] = mini(9999999, int(next["gold"]) + sale_price(held))
		owner["inventory"].erase(held)
		if owner["equippedInstanceId"] == held["id"]:
			owner["equippedInstanceId"] = ""
		return {"ok": true, "progress": next}
	if operation == "buy":
		var template: int = int(details.get("template", -1))
		var available: bool = false
		for item: Dictionary in shop_stock(next, details.get("special", false)):
			if int(item["templateId"]) == template:
				available = true
		if not available:
			return {"ok": false, "error": "ITEM_NOT_FOR_SALE"}
		var price: int = int(_items[template]["price"])
		if int(next["gold"]) < price:
			return {"ok": false, "error": "INSUFFICIENT_GOLD"}
		var in_bag: bool = owner["inventory"].size() < Inventory.BAG_CAPACITY
		if not in_bag and next["warehouse"].size() >= Inventory.WAREHOUSE_CAPACITY:
			return {"ok": false, "error": "WAREHOUSE_FULL"}
		var item: Dictionary = {
			"id": _new_item_id(next),
			"templateId": template,
			"durability": int(_items[template]["defaultDurability"])
		}
		var destination: Array = owner["inventory"] if in_bag else next["warehouse"]
		destination.append(item)
		next["gold"] -= price
		return {"ok": true, "progress": next, "destination": "inventory" if in_bag else "warehouse"}
	if operation == "finish":
		_inventory.auto_equip(owner)
		if details.has("partner"):
			var partner: Dictionary = actor(next, int(details["partner"]))
			if partner.is_empty():
				return {"ok": false, "error": "UNIT_NOT_IN_PARTY"}
			_inventory.auto_equip(partner)
		return {"ok": true, "progress": next}
	if operation == "trade":
		var partner: Dictionary = actor(next, int(details.get("partner", -1)))
		if partner.is_empty() or partner["id"] == owner["id"]:
			return {"ok": false, "error": "INVALID_TRADE_TARGET"}
		var result: Dictionary = _inventory.trade(
			owner, partner, details.get("item", ""), details.get("exchange", "")
		)
		if not result["ok"]:
			return result
		return {"ok": true, "progress": next}
	if operation not in ["deposit", "take"]:
		return {"ok": false, "error": "INVALID_WORLD_OPERATION"}
	var source: Array = owner["inventory"] if operation == "deposit" else next["warehouse"]
	var destination: Array = next["warehouse"] if operation == "deposit" else owner["inventory"]
	var held: Dictionary = {}
	for item: Dictionary in source:
		if item["id"] == details.get("item", ""):
			held = item
			break
	if held.is_empty():
		return {"ok": false, "error": "ITEM_NOT_OWNED"}
	if (
		destination.size()
		>= (Inventory.WAREHOUSE_CAPACITY if operation == "deposit" else Inventory.BAG_CAPACITY)
	):
		return {
			"ok": false, "error": "WAREHOUSE_FULL" if operation == "deposit" else "INVENTORY_FULL"
		}
	source.erase(held)
	destination.append(held)
	if operation == "deposit" and owner["equippedInstanceId"] == held["id"]:
		owner["equippedInstanceId"] = ""
	return {"ok": true, "progress": next}


func actor(progress: Dictionary, id: int) -> Dictionary:
	for member: Dictionary in progress["party"]:
		if member["id"] == id:
			return member
	return {}


func shop_stock(progress: Dictionary, special: bool = false) -> Array[Dictionary]:
	var stock: Array[Dictionary] = []
	var node: int = int(progress["worldNode"])
	var index: int = 0 if special else int(_rules["nodeShopStockIndices"][node])
	for value: Variant in _rules["shopStocks"][index]:
		var template: int = int(value)
		stock.append(
			{
				"templateId": template,
				"durability": int(_items[template]["defaultDurability"]),
				"price": int(_items[template]["price"])
			}
		)
	return stock


func sale_price(held: Dictionary) -> int:
	if held.is_empty() or int(held["durability"]) <= 0:
		return 1
	var definition: Dictionary = _items[int(held["templateId"])]
	var half: int = floori(float(definition["price"]) / 2)
	var maximum: int = int(definition["defaultDurability"])
	return half if maximum <= 0 else floori(float(half) * int(held["durability"]) / maximum)


func can_equip(owner: Dictionary, held: Dictionary) -> bool:
	return _inventory.can_equip(owner, held)


func _new_item_id(progress: Dictionary) -> String:
	var ids: Dictionary = {}
	for member: Dictionary in progress["party"]:
		for held: Dictionary in member["inventory"]:
			ids[held["id"]] = true
	for held: Dictionary in progress["warehouse"]:
		ids[held["id"]] = true
	var index: int = 0
	while ids.has("%s:shop_%d" % [progress["chapterId"], index]):
		index += 1
	return "%s:shop_%d" % [progress["chapterId"], index]
