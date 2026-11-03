extends SceneTree

const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Combat = preload("res://gameplay/combat_rules.gd")


func _initialize() -> void:
	var content: Dictionary = Content.new().load_chapter("res://content/chapter_1/chapter.json")
	var battle: RefCounted = Battle.new(content, func(_limit: int) -> int: return 0)
	var actor: Dictionary = battle.unit(0).duplicate(true)
	var target: Dictionary = battle.unit(59).duplicate(true)
	var combat := Combat.new(content["rules"], content["map"]["terrain"])
	actor["attributes"]["strength"] = 11
	actor["flags"] = 0
	target["flags"] = 0
	target["inventory"] = []
	target["equippedInstanceId"] = ""
	_equip(actor, 12)
	target["attributes"]["defense"] = 0
	var low_defense: int = combat.forecast(actor, target)["damage"]
	target["attributes"]["defense"] = 20
	if not _expect(
		combat.forecast(actor, target)["damage"] == low_defense, "12 ignores nonzero defense"
	):
		return
	# Keep both effective and ordinary damage above the minimum on the original tile.
	actor["attributes"]["strength"] = 30
	target["attributes"]["defense"] = 0
	for weapon: int in [9, 11, 16, 18, 20, 24, 26, 37, 39]:
		_equip(actor, weapon)
		target["classGroup"] = 0
		var normal: int = combat.forecast(actor, target)["damage"]
		for group: Variant in combat.item_definition(weapon)["effectiveGroups"]:
			target["classGroup"] = int(group)
			var effective: int = combat.forecast(actor, target)["damage"]
			if not _expect(
				effective == normal + int(combat.item_definition(weapon)["power"]),
				(
					"Weapon %d group %d effective damage: normal=%d effective=%d"
					% [weapon, int(group), normal, effective]
				)
			):
				return
	_equip(actor, 11)
	_equip(target, 21)
	target["classGroup"] = 0
	var advantage: int = combat.forecast(actor, target)["damage"]
	target["classGroup"] = 2
	var effective_advantage: int = combat.forecast(actor, target)["damage"]
	if not _expect(
		effective_advantage == advantage + int(combat.item_definition(11)["power"]) - 1,
		"Effective target suppresses the ordinary sword-vs-axe advantage"
	):
		return
	target["classGroup"] = 0
	target["inventory"] = []
	target["equippedInstanceId"] = ""
	_equip(actor, 12)
	actor["attributes"]["strength"] = 11
	var unguarded: int = combat.forecast(actor, target)["damage"]
	if not _expect(unguarded == 21, "Controlled hit is odd before the guard reduction"):
		return
	target["inventory"] = [{"id": "guard", "templateId": 83, "durability": 1}]
	if not _expect(
		combat.forecast(actor, target)["damage"] == 10, "83 halves odd damage by truncation"
	):
		return
	target["inventory"] = [{"id": "bow", "templateId": 35, "durability": 1}]
	target["equippedInstanceId"] = "bow"
	if not _expect(combat.forecast(actor, target)["damage"] == 10, "Equipped 35 halves damage"):
		return
	target["inventory"].append({"id": "guard", "templateId": 83, "durability": 1})
	if not _expect(
		combat.forecast(actor, target)["damage"] == 10, "35 and 83 together halve only once"
	):
		return
	print("PASS m15 item rules: 12, 37, 35 and 83")
	quit(0)


func _equip(actor: Dictionary, template: int) -> void:
	actor["inventory"] = [{"id": "weapon", "templateId": template, "durability": 30}]
	actor["equippedInstanceId"] = "weapon"


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
