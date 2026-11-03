extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var combat: RefCounted = load("res://gameplay/combat_rules.gd").new(
		content["rules"], content["map"]["terrain"]
	)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	var actor: Dictionary = battle.unit(0).duplicate(true)
	var target: Dictionary = battle.unit(65).duplicate(true)
	var original_power: int = combat.power(actor)
	var original_critical: String = combat.information(actor)["critical"]
	actor["inventory"].append({"id": "power_seal", "templateId": 84, "durability": 1})
	if (
		combat.power(actor) != original_power
		or combat.information(actor)["critical"] != original_critical
	):
		fail("A seal ring does not suppress critical in target-free information or chapter power")
		return
	if combat.forecast(actor, target)["critical"] != 0:
		fail("A seal ring still suppresses the owner's actual combat critical")
		return
	actor["inventory"].pop_back()
	target["inventory"].append({"id": "target_seal", "templateId": 84, "durability": 1})
	if combat.forecast(actor, target)["critical"] != 0:
		fail("A target seal ring still suppresses incoming combat critical")
		return
	print("PASS chapter power: empty-target seal semantics and actual combat protection")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
