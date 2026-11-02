extends SceneTree

const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var _draws: int = 0


func _initialize() -> void:
	var content: Dictionary = Content.new().load_chapter("res://content/chapter_1/chapter.json")
	var battle: RefCounted = Battle.new(content, _roll)
	if not battle.move_unit(0, Vector2i(9, 12))["ok"]:
		_fail("The action gate fixture requires a valid provisional move")
		return
	var commands: Array[Callable] = [
		func(id: int) -> Dictionary: return battle.wait_unit(id),
		func(id: int) -> Dictionary: return battle.equip_unit(id, "missing"),
		func(id: int) -> Dictionary: return battle.discard_item(id, "missing"),
		func(id: int) -> Dictionary: return battle.attack_options(id, "missing"),
		func(id: int) -> Dictionary: return battle.map_attack_preview(id, "missing"),
		func(id: int) -> Dictionary: return battle.attack_unit(id, 30),
		func(id: int) -> Dictionary: return battle.heal_unit(id, 0, "missing"),
		func(id: int) -> Dictionary: return battle.use_item(id, "missing"),
		func(id: int) -> Dictionary: return battle.begin_trade(id, 0),
		func(id: int) -> Dictionary: return battle.trade_item(id, 0, "missing", "missing")
	]
	var before: Dictionary = battle.snapshot()
	var draws: int = _draws
	for id: int in [9, -1]:
		var expected: String = "ACTION_PENDING" if id == 9 else "UNIT_NOT_READY"
		for command: Callable in commands:
			var result: Dictionary = command.call(id)
			if result.get("error") != expected or battle.snapshot() != before or _draws != draws:
				_fail("Rejected operations must share error priority without changing state or RNG")
				return
		if (
			not battle.actions_for(id).is_empty()
			or not battle.item_options(id).is_empty()
			or not battle.attack_weapons(id).is_empty()
		):
			_fail("Queries must hide operations rejected by the command gate")
			return
	var held: Dictionary = battle.unit(0)["inventory"][0]
	if not battle.equip_unit(0, held["id"])["ok"] or battle.item_options(0).is_empty():
		_fail("The pending move owner must still be allowed to manage equipment")
		return
	if battle.move_unit(0, Vector2i(8, 12)).get("error") != "ACTION_PENDING":
		_fail("A second move must remain stricter than other unit operations")
		return
	if battle.begin_automatic_action(0).get("error") != "INVALID_AUTOMATIC_ACTOR":
		_fail("Automatic actions must retain their separate actor contract")
		return
	print("PASS action eligibility: error priority, pending owner, queries and rejection isolation")
	quit(0)


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
