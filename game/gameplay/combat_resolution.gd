extends RefCounted

var _combat: RefCounted
var _inventory: RefCounted
var _roll: Callable


func _init(combat: RefCounted, inventory: RefCounted, random_source: Callable) -> void:
	_combat = combat
	_inventory = inventory
	_roll = random_source


func resolve(actor: Dictionary, target: Dictionary, commander: Dictionary) -> Dictionary:
	var participants: Array = [actor.duplicate(true), target.duplicate(true)]
	var attack_count: int = (
		2 if _combat.item_definition(_combat.weapon_id(actor))["doubleStrike"] else 1
	)
	var counter_count: int = (
		2 if _combat.item_definition(_combat.weapon_id(target))["doubleStrike"] else 1
	)
	var counter_allowed: bool = _combat.can_counter(target, actor)
	var strikes: Array[Dictionary] = []
	_perform_strikes(actor, target, attack_count, false, strikes, commander)
	if counter_allowed:
		_perform_strikes(target, actor, counter_count, true, strikes, commander)
	if actor["hp"] > 0 and target["hp"] > 0:
		var speed_difference: int = (
			_combat.effective_speed(actor, commander) - _combat.effective_speed(target, commander)
		)
		if speed_difference >= 5:
			_perform_strikes(actor, target, attack_count, false, strikes, commander)
		elif counter_allowed and speed_difference <= -5:
			_perform_strikes(target, actor, counter_count, true, strikes, commander)
	return {"participants": participants, "strikes": strikes}


func _perform_strikes(
	actor: Dictionary,
	target: Dictionary,
	count: int,
	counter: bool,
	strikes: Array[Dictionary],
	commander: Dictionary
) -> void:
	for index: int in range(count):
		if actor["hp"] <= 0 or target["hp"] <= 0:
			return
		var weapon: int = _combat.weapon_id(actor)
		if weapon == 0:
			return
		var forecast: Dictionary = _combat.forecast(actor, target, commander)
		var hit: bool = _roll.call(100) < int(forecast["hit"])
		var critical: bool = false
		var damage: int = 0
		var healed: int = 0
		var hp_before: int = target["hp"]
		if hit:
			var critical_rate: int = int(forecast["critical"])
			if actor["classGroup"] == 10 and critical_rate != 0:
				critical_rate = 100
			if actor["faction"] == 2 and critical_rate <= 10:
				critical_rate = 0
			critical = _roll.call(100) < critical_rate
			damage = mini(
				int(forecast["criticalDamage"] if critical else forecast["damage"]), target["hp"]
			)
			if (
				weapon == 47
				and not (target["faction"] == 2 and target["id"] >= 80 and target["id"] <= 94)
			):
				damage = maxi(0, int(target["hp"]) - 1)
			target["hp"] -= damage
			if _combat.item_definition(weapon)["drainsHp"]:
				healed = mini(damage, int(actor["maxHp"]) - int(actor["hp"]))
				actor["hp"] += healed
			if (
				weapon == 8
				and (target["id"] < 80 or target["id"] >= 105)
				and int(_combat.item_definition(_combat.weapon_id(target))["categoryMask"]) == 1
				and _roll.call(100) < 15
			):
				for held: Dictionary in target["inventory"]:
					if held["id"] == target["equippedInstanceId"]:
						held["durability"] = -10
						target["equippedInstanceId"] = ""
			_inventory.consume_weapon(actor)
			var current_kind: String = (
				_combat.item_definition(_combat.weapon_id(actor))["damageKind"]
			)
			if current_kind in ["physical", "none"]:
				if not _inventory.consume_template(target, 65):
					_inventory.consume_template(target, 66)
			else:
				_inventory.consume_template(target, 67)
		strikes.append(
			{
				"attacker": actor["id"],
				"defender": target["id"],
				"weapon": weapon,
				"counter": counter,
				"hit": hit,
				"critical": critical,
				"hpBefore": hp_before,
				"hpAfter": target["hp"],
				"damage": damage,
				"heal": healed
			}
		)
