extends SceneTree

const CHAPTER: String = "res://content/chapter_1/chapter.json"
const Content = preload("res://app/chapter_content.gd")

var _fixture_paths: Array[String] = []


func _initialize() -> void:
	var original: Dictionary = Content.new().load_chapter(CHAPTER)
	if not original["ok"]:
		fail("Identity contract requires valid chapter content: " + str(original))
		return
	var prefix: String = "user://identity_fixture_%d" % Time.get_ticks_usec()
	var chapter_path: String = prefix + ".chapter.json"
	var library_path: String = prefix + ".library.json"
	var rules_path: String = prefix + ".rules.json"
	var story_path: String = prefix + ".story.json"
	var deployments_path: String = prefix + ".deployments.json"
	var battle_path: String = prefix + ".battle.json"
	_fixture_paths = [
		chapter_path, library_path, rules_path, story_path, deployments_path, battle_path
	]
	var entry: Dictionary = original["entry"].duplicate(true)
	entry["id"] = "chapter_identity_fixture"
	entry["initialParty"] = [0, 300]
	entry["library"] = library_path
	entry["rules"] = rules_path
	entry["battles"] = {"m0": battle_path}
	var definition: Dictionary = {}
	for key: String in ["battleId", "map", "mapTexture", "profiles", "stage", "scene"]:
		definition[key] = entry[key]
	definition["story"] = story_path
	definition["deployments"] = deployments_path
	var deployments: Array = original["_deployments"].duplicate(true)
	var spawn: Dictionary = {}
	for row: Dictionary in deployments:
		if row["sourceId"] == 9 and not row.has("deploymentSlot"):
			spawn = row.duplicate(true)
			break
	if spawn.is_empty():
		fail("Identity fixture requires the original formal source template")
		return
	spawn["id"] = 300
	spawn["formal"] = true
	spawn["position"] = [0, 0]
	spawn["itemChoices"] = [200, 60, 0]
	spawn["dropTemplateId"] = 300
	spawn["growthTemplateId"] = 9
	spawn["baseTemplateId"] = 9
	spawn["initialGrowthTemplateId"] = 9
	deployments.append(spawn)
	var rules: Dictionary = original["rules"].duplicate(true)
	var template: Dictionary = rules["itemTemplates"][9].duplicate(true)
	template["id"] = 200
	rules["itemTemplates"].append(template)
	var drop_template: Dictionary = rules["itemTemplates"][9].duplicate(true)
	drop_template["id"] = 300
	rules["itemTemplates"].append(drop_template)
	var library: Dictionary = original["_library"].duplicate(true)
	library["interface"]["items"]["200"] = library["interface"]["items"]["9"].duplicate(true)
	library["interface"]["items"]["200"]["id"] = 200
	library["interface"]["items"]["300"] = library["interface"]["items"]["9"].duplicate(true)
	library["interface"]["items"]["300"]["id"] = 300
	var story: Dictionary = original["_storyFragment"].duplicate(true)
	for step: Dictionary in story["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			step["candidates"] = [300, 0]
			step["defaultCommanderId"] = 300
	_write_json(chapter_path, entry)
	_write_json(library_path, library)
	_write_json(rules_path, rules)
	_write_json(story_path, story)
	_write_json(deployments_path, deployments)
	_write_json(battle_path, definition)
	var loader: RefCounted = Content.new()
	var content: Dictionary = loader.load_chapter(chapter_path)
	if not content["ok"]:
		fail("Declared high identities must pass real chapter validation: " + str(content))
		return
	if (
		content["entry"]["library"] != library_path
		or content["entry"]["story"] != story_path
		or content["entry"]["resourceDirectory"] != "res://"
	):
		fail("Fixture source documents and bundled resource coordinates must remain independent")
		return
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
		content, func(_limit: int) -> int: return 0
	)
	var store: RefCounted = load("res://persistence/battle_store.gd").new(content)
	var saved: Dictionary = store.encode(battle)
	if not saved["ok"]:
		fail("Declared high identities must be encodable: " + str(saved))
		return
	if battle.unit(300)["dropTemplateId"] != 300:
		fail("Declared high drop templates must retain their item identity")
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
		var metadata: Dictionary = library["interface"]["items"]["200"].duplicate(true)
		if malformed == "missing":
			library["interface"]["items"].erase("200")
		else:
			library["interface"]["items"]["200"]["detailAttributes"] = ["attack"]
		_write_json(library_path, library)
		if loader.load_chapter(chapter_path)["ok"]:
			fail("High item identities must satisfy the same display metadata contract")
			return
		library["interface"]["items"]["200"] = metadata
	print(
		"PASS content identity: validated high IDs, JSON restore, commander scope and chapter prefix"
	)
	_cleanup()
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _cleanup() -> void:
	for path: String in _fixture_paths:
		DirAccess.remove_absolute(path)
