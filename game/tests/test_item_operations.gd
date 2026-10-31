extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var script: Script = load("res://gameplay/battle_state.gd")
	var battle: RefCounted = script.new(content, func(_limit: int) -> int: return 0)
	if not battle.has_method("item_options") or not battle.has_method("discard_item"):
		fail("Original item operations must be available through the authoritative battle")
		return
	var before: Dictionary = battle.snapshot()
	var options: Dictionary = battle.item_options(0)
	if options["use"].size() != 2 or options["equip"].size() != 1 or options["discard"].size() != 2:
		fail("Original operation candidates must include equipped holy sword and full-HP herb")
		return
	options["discard"].clear()
	if battle.snapshot() != before or not battle.unit_information(-1).is_empty():
		fail("Inventory queries must not expose mutable authority or fail for an absent unit")
		return
	var sword: Dictionary = battle.unit(0)["inventory"][0]
	if not battle.move_unit(0, Vector2i(8, 12))["ok"]:
		fail("Controlled movement before discard must succeed")
		return
	if not battle.discard_item(0, sword["id"])["ok"] or battle.unit(0)["action"] != 0:
		fail("Discard removes the held item without consuming the action")
		return
	if (
		not battle.cancel_move()["ok"]
		or battle.unit(0)["y"] != 11
		or battle.unit(0)["inventory"].size() != 1
	):
		fail("Original discard allows undoing the move while retaining the discarded inventory")
		return
	var herb: Dictionary = battle.unit(0)["inventory"][0]
	if not battle.discard_item(0, herb["id"])["ok"] or not battle.item_options(0).is_empty():
		fail("Discarding the final item leaves an available unit without item operations")
		return
	before = battle.snapshot()
	if battle.discard_item(0, "foreign")["ok"] or battle.snapshot() != before:
		fail("Discard must reject an unowned item atomically")
		return
	var protected_state: Dictionary = battle.snapshot()
	for actor: Dictionary in protected_state["units"]:
		if actor["id"] == 0:
			actor["inventory"] = [{"id": "protected", "templateId": 50, "durability": 1}]
	if not battle.restore_snapshot(protected_state)["ok"]:
		fail("A held protected spell must be valid inventory regardless of equipment capability")
		return
	before = battle.snapshot()
	if battle.discard_item(0, "protected")["ok"] or battle.snapshot() != before:
		fail("The original protected item50 must reject discard atomically")
		return
	print(
		"PASS item operations: source order candidates, full HP, equipped weapon, discard and move undo"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
