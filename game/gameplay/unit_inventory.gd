extends RefCounted

const BAG_CAPACITY: int = 6
const WAREHOUSE_CAPACITY: int = 40

# Shared item rules; battle and world progress own their mutable units and warehouses.
var _combat: RefCounted
var _roll: Callable


func _init(combat: RefCounted, random_source: Callable) -> void:
	_combat = combat
	_roll = random_source


func equip(actor: Dictionary, instance_id: String) -> Dictionary:
	for held: Dictionary in actor["inventory"]:
		if held["id"] == instance_id:
			if not can_equip(actor, held):
				return _failure("EQUIPMENT_NOT_ALLOWED")
			actor["equippedInstanceId"] = instance_id
			actor["inventory"].erase(held)
			actor["inventory"].push_front(held)
			return {"ok": true, "kind": "equip", "unit": actor["id"], "item": instance_id}
	return _failure("ITEM_NOT_OWNED")


func candidates(actor: Dictionary, operation: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for held: Dictionary in actor["inventory"]:
		var eligible: bool = false
		match operation:
			"use":
				eligible = _can_use(held)
			"equip":
				eligible = can_equip(actor, held)
			"discard":
				eligible = _can_discard(held)
		if eligible:
			items.append(held.duplicate(true))
	return items


func can_equip(actor: Dictionary, held: Dictionary) -> bool:
	return _combat.can_equip(actor, held)


func discard(actor: Dictionary, instance_id: String) -> Dictionary:
	var held: Dictionary = held_item(actor, instance_id)
	if held.is_empty():
		return _failure("ITEM_NOT_OWNED")
	if not _can_discard(held):
		return _failure("ITEM_CANNOT_BE_DISCARDED")
	actor["inventory"].erase(held)
	auto_equip(actor)
	return {"ok": true, "kind": "discard", "unit": actor["id"], "item": instance_id}


func cleanup_combat(actor: Dictionary) -> void:
	if actor["inventory"].is_empty():
		return
	for index: int in range(actor["inventory"].size() - 1, -1, -1):
		var held: Dictionary = actor["inventory"][index]
		if int(held["templateId"]) < 60 and held["durability"] <= 0:
			actor["inventory"].remove_at(index)
	auto_equip(actor)
	actor["flags"] &= ~(8 | 32)


func broken_items(participants: Array, current_units: Dictionary) -> Array[Dictionary]:
	var broken: Array[Dictionary] = []
	for participant: Dictionary in participants:
		for held: Dictionary in participant["inventory"]:
			var remaining: Dictionary = held_item(current_units[int(participant["id"])], held["id"])
			if held["durability"] > 0 and (remaining.is_empty() or remaining["durability"] <= 0):
				broken.append(
					{
						"unit": participant["id"],
						"item": held["id"],
						"templateId": held["templateId"]
					}
				)
	return broken


func consume_weapon(actor: Dictionary) -> void:
	actor["proficiency"] += 1
	var protected: bool = false
	for held: Dictionary in actor["inventory"]:
		if int(held["templateId"]) == 87:
			protected = _roll.call(100) < int(actor["attributes"]["luck"])
			break
	if protected:
		return
	for held: Dictionary in actor["inventory"]:
		if held["id"] == actor["equippedInstanceId"]:
			held["durability"] -= 1
			if held["durability"] <= 0:
				actor["equippedInstanceId"] = ""
				if actor["faction"] == 2:
					actor["inventory"].erase(held)
					auto_equip(actor)
			return


func auto_equip(actor: Dictionary) -> void:
	actor["equippedInstanceId"] = ""
	for held: Dictionary in actor["inventory"]:
		if can_equip(actor, held):
			actor["equippedInstanceId"] = held["id"]
			actor["inventory"].erase(held)
			actor["inventory"].push_front(held)
			return


func consume_template(actor: Dictionary, template_id: int) -> bool:
	for held: Dictionary in actor["inventory"]:
		if int(held["templateId"]) == template_id:
			held["durability"] -= 1
			if held["durability"] <= 0:
				actor["inventory"].erase(held)
			return true
	return false


func transfer_drop(dead: Dictionary, recipient: Dictionary, warehouse: Array) -> Dictionary:
	var marked: int = int(dead["dropTemplateId"])
	if marked <= 0:
		return {}
	for held: Dictionary in dead["inventory"]:
		if held["templateId"] != marked:
			continue
		var destination: String = "inventory"
		if recipient["inventory"].size() < BAG_CAPACITY:
			recipient["inventory"].append(held)
		elif warehouse.size() < WAREHOUSE_CAPACITY:
			warehouse.append(held)
			destination = "warehouse"
		else:
			return {}
		dead["inventory"].erase(held)
		if dead["equippedInstanceId"] == held["id"]:
			dead["equippedInstanceId"] = ""
		return {"unit": recipient["id"], "item": held.duplicate(true), "destination": destination}
	return {}


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}


func held_item(actor: Dictionary, instance_id: String) -> Dictionary:
	for held: Dictionary in actor["inventory"]:
		if held["id"] == instance_id:
			return held
	return {}


func can_heal_with(actor: Dictionary, held: Dictionary) -> bool:
	return (
		not held.is_empty()
		and held["durability"] > 0
		and int(held["templateId"]) in [53, 54, 55, 56]
		and (int(actor["equipMask"]) & 32) != 0
	)


func can_heal(actor: Dictionary, target: Dictionary, instance_id: String) -> bool:
	var held: Dictionary = held_item(actor, instance_id)
	if not can_heal_with(actor, held):
		return false
	return actor["id"] != target["id"] and _combat.in_range(actor, target, int(held["templateId"]))


func heal(actor: Dictionary, target: Dictionary, instance_id: String) -> Dictionary:
	if not can_heal(actor, target, instance_id):
		return _failure("INVALID_HEAL_TARGET")
	var held: Dictionary = held_item(actor, instance_id)
	var template: int = int(held["templateId"])
	if template in [55, 56]:
		target["flags"] &= ~(8 | 32)
		target["flags"] |= 8 if template == 55 else 32
		return {
			"ok": true,
			"kind": "staff_buff",
			"actor": actor["id"],
			"target": target["id"],
			"item": instance_id,
			"expiredItem": _consume_held(actor, held)
		}
	# The original draws a critical roll here; its null-target healing formula ignores the flag.
	_roll.call(100)
	var before: int = int(target["hp"])
	target["hp"] = mini(
		int(target["maxHp"]), before + _combat.healing_amount(actor, int(held["templateId"]))
	)
	var expired: Dictionary = _consume_held(actor, held)
	return {
		"ok": true,
		"kind": "heal",
		"actor": actor["id"],
		"target": target["id"],
		"item": instance_id,
		"expiredItem": expired,
		"hpBefore": before,
		"hpAfter": target["hp"],
		"healed": int(target["hp"]) - before
	}


func use_item(actor: Dictionary, instance_id: String) -> Dictionary:
	var held: Dictionary = held_item(actor, instance_id)
	if held.is_empty() or held["durability"] <= 0:
		return _failure("ITEM_NOT_OWNED")
	if not _can_use(held):
		return _failure("ITEM_NOT_USABLE")
	var before: int = int(actor["hp"])
	var amount: int = _self_heal_amount(actor, held)
	var consumed: bool = before < int(actor["maxHp"])
	var expired: Dictionary = {}
	if consumed:
		actor["hp"] = mini(int(actor["maxHp"]), before + amount)
		expired = _consume_held(actor, held)
	return {
		"ok": true,
		"kind": "use_item",
		"actor": actor["id"],
		"item": instance_id,
		"hpBefore": before,
		"hpAfter": actor["hp"],
		"healed": int(actor["hp"]) - before,
		"consumed": consumed,
		"expiredItem": expired
	}


func _can_use(held: Dictionary) -> bool:
	return held["durability"] > 0 and int(held["templateId"]) in [9, 18, 26, 37, 60, 61, 62]


func _can_discard(held: Dictionary) -> bool:
	return int(held["templateId"]) != 50


func _self_heal_amount(actor: Dictionary, held: Dictionary) -> int:
	var template: int = int(held["templateId"])
	if template == 60:
		return 10
	if template == 61:
		return 20
	if template == 62:
		return int(actor["maxHp"]) - int(actor["hp"])
	return int(_combat.item_definition(template)["power"])


func _consume_held(actor: Dictionary, held: Dictionary) -> Dictionary:
	held["durability"] -= 1
	if held["durability"] <= 0:
		actor["inventory"].erase(held)
		if held["id"] == actor["equippedInstanceId"]:
			auto_equip(actor)
		if int(_combat.item_definition(int(held["templateId"]))["defaultDurability"]) > 1:
			return held.duplicate(true)
	return {}


func trade(
	actor: Dictionary, recipient: Dictionary, instance_id: String, exchange_id: String
) -> Dictionary:
	var held: Dictionary = held_item(actor, instance_id)
	var exchanged: Dictionary = (
		held_item(recipient, exchange_id) if not exchange_id.is_empty() else {}
	)
	if held.is_empty() or (not exchange_id.is_empty() and exchanged.is_empty()):
		return _failure("ITEM_NOT_OWNED")
	if exchanged.is_empty() and recipient["inventory"].size() >= BAG_CAPACITY:
		return _failure("INVENTORY_FULL")
	if exchanged.is_empty():
		actor["inventory"].erase(held)
		recipient["inventory"].append(held)
	else:
		var source_slot: int = actor["inventory"].find(held)
		var destination_slot: int = recipient["inventory"].find(exchanged)
		actor["inventory"][source_slot] = exchanged
		recipient["inventory"][destination_slot] = held
	for owner: Dictionary in [actor, recipient]:
		if held_item(owner, owner["equippedInstanceId"]).is_empty():
			owner["equippedInstanceId"] = ""
	return {
		"ok": true,
		"kind": "trade",
		"actor": actor["id"],
		"target": recipient["id"],
		"item": instance_id,
		"exchange": exchange_id
	}
