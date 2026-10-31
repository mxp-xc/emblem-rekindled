extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(_limit: int) -> int: return 0
	)
	if not battle.has_method("trade_item"):
		fail("Adjacent inventory transfer/exchange is missing")
		return
	var herb: Dictionary = battle.unit(0)["inventory"][1]
	var staff: Dictionary = battle.unit(9)["inventory"][0]
	if not battle.trade_item(0, 9, herb["id"], staff["id"])["ok"]:
		fail("Adjacent same-faction units must be able to exchange held instances")
		return
	var alm: Dictionary = battle.unit(0)
	var celica: Dictionary = battle.unit(9)
	if (
		alm["action"] != 0
		or celica["action"] != 0
		or alm["inventory"][1]["id"] != staff["id"]
		or celica["inventory"][0]["id"] != herb["id"]
	):
		fail("Trade must retain instance identity and both units' available actions")
		return
	if not battle.trade_item(0, 9, staff["id"])["ok"] or battle.unit(9)["inventory"].size() != 3:
		fail("A non-full destination must accept an item without exchanging one")
		return
	var before: Dictionary = battle.snapshot()
	if (
		battle.trade_item(0, 10, alm["inventory"][0]["id"])["ok"]
		or battle.trade_item(0, 97, alm["inventory"][0]["id"])["ok"]
		or battle.trade_item(0, 9, "foreign")["ok"]
		or battle.snapshot() != before
	):
		fail("Different faction, nonadjacent and unowned trades must fail atomically")
		return
	print(
		"PASS trade: same faction/adjacency, held instances, transfer/exchange, actions, atomic errors"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
