extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var script: Script = load("res://gameplay/battle_state.gd")
	var battle: RefCounted = script.new(content, func(_limit: int) -> int: return 0)
	var store_script: Script = load("res://persistence/battle_store.gd")
	if store_script == null:
		fail("Battle persistence boundary is missing")
		return
	var path := "user://test_battle_%d.json" % Time.get_ticks_usec()
	var store: RefCounted = store_script.new(content, path)
	battle.move_unit(0, Vector2i(8, 15))
	if store.encode(battle)["ok"]:
		fail("A pending move is not a stable save point")
		return
	battle.wait_unit(0)
	var saved: Dictionary = store.encode(battle)
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(saved["record"]))
	var loaded: Dictionary = store.decode(serialized, func(limit: int) -> int: return limit - 1)
	if not loaded["ok"] or loaded["battle"].snapshot() != battle.snapshot():
		fail("The JSON save record must restore all business state, not new-game random draws")
		return
	var restored: RefCounted = loaded["battle"]
	var invalid: Dictionary = serialized.duplicate(true)
	invalid["state"]["units"][1]["id"] = invalid["state"]["units"][0]["id"]
	var before: Dictionary = restored.snapshot()
	if store.decode(invalid)["ok"] or restored.snapshot() != before:
		fail("Corrupt identities must be rejected without partially restoring state")
		return
	invalid = serialized.duplicate(true)
	invalid["state"]["units"][0]["inventory"][0]["templateId"] = 999
	if store.decode(invalid)["ok"]:
		fail("Unknown item references must be rejected")
		return
	var presentation_free: Dictionary = serialized.duplicate(true)
	presentation_free["state"]["units"][0].erase("name")
	presentation_free["state"]["units"][0]["spriteOffsetX"] = "broken"
	var presentation_id: int = int(presentation_free["state"]["units"][0]["id"])
	var canonical: Dictionary = store.decode(presentation_free)
	if (
		not canonical["ok"]
		or not canonical["battle"].unit(presentation_id).has("name")
		or canonical["battle"].unit(presentation_id)["name"] != battle.unit(presentation_id)["name"]
		or (
			canonical["battle"].unit(presentation_id)["spriteOffsetX"]
			!= battle.unit(presentation_id)["spriteOffsetX"]
		)
	):
		fail("Static presentation must come from chapter content, never an unchecked save")
		return
	if not store.write(battle)["ok"]:
		fail("Stable battle must be written successfully")
		return
	var disk: Dictionary = store_script.new(content, path).read()
	if not disk["ok"] or disk["battle"].snapshot() != battle.snapshot():
		fail("A new persistence instance must restore position, action and inventory from disk")
		return
	battle.move_unit(9, Vector2i(9, 12))
	if store.write(battle)["ok"] or store.read()["battle"].snapshot() != disk["battle"].snapshot():
		fail("An unstable save request must preserve the last valid file")
		return
	var corrupted := FileAccess.open(path, FileAccess.WRITE)
	corrupted.store_string("broken")
	corrupted.close()
	if store.read()["ok"]:
		fail("A damaged battle file must not silently become a new battle")
		return
	DirAccess.remove_absolute(path)
	print("PASS battle record: stable boundary, JSON restore, atomic validation, item references")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
