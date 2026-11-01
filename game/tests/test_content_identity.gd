extends SceneTree

const CHAPTER: String = "res://content/chapter_1/chapter.json"


class FixtureLoader:
	extends "res://app/chapter_content.gd"
	var records: Dictionary = {}

	func _read_json(path: String) -> Variant:
		if records.has(path):
			return records[path].duplicate(true)
		return super._read_json(path)


func _initialize() -> void:
	var original: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(CHAPTER)
	var loader := FixtureLoader.new()
	var entry: Dictionary = original["entry"].duplicate(true)
	entry["id"] = "chapter_identity_fixture"
	loader.records[CHAPTER] = entry
	for key: String in ["units", "spawns", "rules", "mapAnimations", "interface", "story"]:
		loader.records[entry[key]] = original[key].duplicate(true)
	var unit: Dictionary = (
		original["units"]
		. filter(func(row: Dictionary) -> bool: return row["id"] == 9)[0]
		. duplicate(true)
	)
	unit["id"] = 300
	unit["x"] = 0
	unit["y"] = 0
	loader.records[entry["units"]].append(unit)
	var spawn: Dictionary = (
		original["spawns"]
		. filter(func(row: Dictionary) -> bool: return row["id"] == 9)[0]
		. duplicate(true)
	)
	spawn["id"] = 300
	spawn["position"] = [0, 0]
	spawn["itemChoices"] = [200, 60, 0]
	loader.records[entry["spawns"]].append(spawn)
	var template: Dictionary = original["rules"]["itemTemplates"][9].duplicate(true)
	template["id"] = 200
	loader.records[entry["rules"]]["itemTemplates"].append(template)
	loader.records[entry["mapAnimations"]]["units"]["300"] = (
		original["mapAnimations"]["units"]["9"].duplicate(true)
	)
	loader.records[entry["interface"]]["portraitByUnitId"]["300"] = (
		original["interface"]["portraitByUnitId"]["9"].duplicate(true)
	)
	loader.records[entry["interface"]]["items"]["200"] = (
		original["interface"]["items"]["9"].duplicate(true)
	)
	for step: Dictionary in loader.records[entry["story"]]["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			step["candidates"] = [300, 0]
			step["defaultCommanderId"] = 300
	var content: Dictionary = loader.load_chapter(CHAPTER)
	if not content["ok"]:
		fail("Declared high identities must pass real chapter validation: " + str(content))
		return
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(_limit: int) -> int: return 0
	)
	var store: RefCounted = load("res://persistence/battle_store.gd").new(content)
	var saved: Dictionary = store.encode(battle)
	if not saved["ok"]:
		fail("Declared high identities must be encodable: " + str(saved))
		return
	var decoded: Dictionary = store.decode(JSON.parse_string(JSON.stringify(saved["record"])))
	if not decoded["ok"] or decoded["battle"].snapshot() != battle.snapshot():
		fail("Declared unit >255 and item >87 must survive JSON encode/decode: " + str(decoded))
		return
	if battle.commander_id != 300 or battle.command_configuration()["candidates"][0]["id"] != 300:
		fail("Opening commander order and default must come from the loaded chapter")
		return
	if not battle.unit(300)["inventory"][0]["id"].begins_with("chapter_identity_fixture:"):
		fail("Initial held identities must use their loaded chapter prefix")
		return
	if (
		battle.configure_commander(9, false, false)["ok"]
		or not battle.configure_commander(0, false, false)["ok"]
	):
		fail("Opening selection must use declared candidates only")
		return
	var state: Dictionary = battle.snapshot()
	state["commander"] = 9
	if not battle.restore_snapshot(state)["ok"]:
		fail("Restoring a formal living commander must not require opening candidacy")
		return
	for bad: Variant in [-2, 301, 300.5, "300", INF, NAN]:
		state = battle.snapshot()
		state["commander"] = bad
		if battle.restore_snapshot(state)["ok"]:
			fail("Undeclared or malformed commander identity must reject")
			return
	for key: String in ["id", "templateId"]:
		for bad: Variant in [-1, 999, 1.5, "300", INF, NAN]:
			var invalid: Dictionary = saved["record"].duplicate(true)
			if key == "id":
				invalid["state"]["units"][-1]["id"] = bad
			else:
				invalid["state"]["units"][-1]["inventory"][0]["templateId"] = bad
			if store.decode(invalid)["ok"]:
				fail("Undeclared or malformed unit/item identity must reject")
				return
	for sample: Array in [["flags", 256], ["level", 21], ["experience", 100], ["sourceId", 256]]:
		var invalid: Dictionary = saved["record"].duplicate(true)
		invalid["state"]["units"][-1][sample[0]] = sample[1]
		if store.decode(invalid)["ok"]:
			fail("Identity expansion must not widen existing unit rule/protocol ranges")
			return
	var invalid_durability: Dictionary = saved["record"].duplicate(true)
	invalid_durability["state"]["units"][-1]["inventory"][0]["durability"] = 128
	if store.decode(invalid_durability)["ok"]:
		fail("Held durability must retain the original 127 upper bound")
		return
	state = battle.snapshot()
	state["commander"] = -1
	if not battle.restore_snapshot(state)["ok"]:
		fail("No-commander sentinel must remain a valid battle record")
		return
	state["commander"] = 9
	var legacy_item: Dictionary = state["units"][-1]["inventory"][0]
	legacy_item["id"] = "legacy_chapter:original_held_id"
	if (
		not battle.restore_snapshot(state)["ok"]
		or battle.unit(300)["inventory"][0]["id"] != legacy_item["id"]
	):
		fail(
			"Restoring held identities must preserve old IDs without regenerating a chapter prefix"
		)
		return
	battle.win_with_assistance()
	var progress: Dictionary = battle.complete_victory(0)["progress"]
	var world_record: Dictionary = store.encode_progress(progress)
	if (
		not world_record["ok"]
		or not store.decode(JSON.parse_string(JSON.stringify(world_record["record"])))["ok"]
	):
		fail("World records must retain high IDs and formal commanders outside opening candidates")
		return
	for malformed: String in ["missing", "layout"]:
		var metadata: Dictionary = loader.records[entry["interface"]]["items"]["200"].duplicate(
			true
		)
		if malformed == "missing":
			loader.records[entry["interface"]]["items"].erase("200")
		else:
			loader.records[entry["interface"]]["items"]["200"]["detailAttributes"] = ["attack"]
		if loader.load_chapter(CHAPTER)["ok"]:
			fail("High item identities must satisfy the same display metadata contract")
			return
		loader.records[entry["interface"]]["items"]["200"] = metadata
	print(
		"PASS content identity: validated high IDs, JSON restore, commander scope and chapter prefix"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
