extends SceneTree

const CHAPTER_PATH: String = "res://content/chapter_1/chapter.json"


class ContentFixture:
	extends "res://app/chapter_content.gd"

	var documents: Dictionary = {}

	func _validate(content: Dictionary) -> Dictionary:
		var candidate: Dictionary = content.duplicate(true)
		for field: String in documents:
			candidate[field] = documents[field].duplicate(true)
		return super._validate(candidate)


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(CHAPTER_PATH)
	if not content["ok"]:
		fail("Content contracts require a valid original chapter")
		return
	var invalid_units: Array = content["units"].duplicate(true)
	invalid_units[0]["id"] = -1
	var invalid_identity: Dictionary = _load_documents(content, {"units": invalid_units})
	if invalid_identity["ok"] or not invalid_identity["error"].contains("单位身份无效"):
		fail("Unit identities must reject negative integers at chapter loading")
		return
	for invalid: Variant in [0, -1, 32, 24.5, "24", null]:
		for field: String in ["map", "story"]:
			var document: Dictionary = content[field].duplicate(true)
			if field == "map":
				document["tileSize"] = invalid
			else:
				document["world"]["tileSize"] = invalid
			if _load_documents(content, {field: document})["ok"]:
				fail("Both maps must reject unsupported logical tile sizes: " + field)
				return
	for invalid: Variant in [
		null, [], "durability", ["unknown"], ["durability", "durability"], ["durability", "attack"]
	]:
		var interface_data: Dictionary = content["interface"].duplicate(true)
		interface_data["items"]["9"]["detailAttributes"] = invalid
		if _load_documents(content, {"interface": interface_data})["ok"]:
			fail("Unsupported item detail layouts must fail before opening the chapter")
			return
	var missing_layout: Dictionary = content["interface"].duplicate(true)
	missing_layout["items"]["9"].erase("detailAttributes")
	if _load_documents(content, {"interface": missing_layout})["ok"]:
		fail("An item without a detail layout must fail content loading")
		return
	var rules: Dictionary = content["rules"].duplicate(true)
	rules["itemTemplates"] = rules["itemTemplates"].filter(
		func(item: Dictionary) -> bool: return item["id"] != 87
	)
	var subset_interface: Dictionary = content["interface"].duplicate(true)
	subset_interface["items"].erase("87")
	if not _load_documents(content, {"rules": rules, "interface": subset_interface})["ok"]:
		fail("Only declared item templates require display metadata; template zero is a sentinel")
		return
	var extra_item: Dictionary = rules["itemTemplates"][-1].duplicate(true)
	extra_item["id"] = 288
	rules["itemTemplates"].append(extra_item)
	if _load_documents(content, {"rules": rules, "interface": subset_interface})["ok"]:
		fail("A declared high-numbered item must require its own display metadata")
		return
	subset_interface["items"]["288"] = content["interface"]["items"]["87"].duplicate(true)
	subset_interface["items"]["288"]["id"] = 288
	if not _load_documents(content, {"rules": rules, "interface": subset_interface})["ok"]:
		fail("A declared high-numbered item with valid metadata must pass chapter loading")
		return
	subset_interface["items"]["288"]["detailAttributes"] = ["unknown"]
	if _load_documents(content, {"rules": rules, "interface": subset_interface})["ok"]:
		fail("High-numbered item layouts must pass the same content validation")
		return
	for defect: String in ["mode", "map_round"]:
		var broken_rules: Dictionary = content["rules"].duplicate(true)
		for item: Dictionary in broken_rules["itemTemplates"]:
			if defect == "mode" and item["damageKind"] == "physical":
				item.erase("actionMode")
				break
			if defect == "map_round" and int(item["id"]) == 46:
				item["roundRule"]["period"] = 1.5
				break
		if _load_documents(content, {"rules": broken_rules})["ok"]:
			fail("Action modes and map rules must be validated on item templates: " + defect)
			return
	for field: String in ["itemChoices", "dropTemplateId"]:
		var invalid_spawns: Array = content["spawns"].duplicate(true)
		if field == "itemChoices":
			invalid_spawns[0][field] = [0, 999, 0]
		else:
			invalid_spawns[0][field] = 999
		if _load_documents(content, {"spawns": invalid_spawns})["ok"]:
			fail("Both equipment and drop references must exist in declared item templates")
			return
	var derived: int = -1
	for index: int in range(content["spawns"].size()):
		if not content["spawns"][index].has("explicitStats"):
			derived = index
			break
	if derived < 0:
		fail("The content fixture must contain an initialized-stat deployment")
		return
	for field: String in ["baseTemplateId", "initialGrowthTemplateId", "growthTemplateId"]:
		var broken_spawns: Array = content["spawns"].duplicate(true)
		broken_spawns[derived][field] = 999
		if _load_documents(content, {"spawns": broken_spawns})["ok"]:
			fail("Spawn stat references must reject before live initialization: " + field)
			return
	var opening: Array = content["story"]["sequences"]["opening"]
	var setup_index: int = -1
	for index: int in range(opening.size()):
		if opening[index]["kind"] == "commanderSetup":
			setup_index = index
	if setup_index < 0:
		fail("The original opening must declare its commander setup")
		return
	for defect: String in [
		"missing", "multiple", "empty", "duplicate", "unknown", "fractional", "temporary", "default"
	]:
		var story: Dictionary = content["story"].duplicate(true)
		var setup: Dictionary = story["sequences"]["opening"][setup_index]
		match defect:
			"missing":
				story["sequences"]["opening"].remove_at(setup_index)
			"multiple":
				story["sequences"]["opening"].append(setup.duplicate(true))
			"empty":
				setup["candidates"] = []
			"duplicate":
				setup["candidates"] = [9, 9]
			"unknown":
				setup["candidates"] = [9, 9999]
			"fractional":
				setup["candidates"] = [9, 0.5]
			"temporary":
				setup["candidates"] = [9, 10]
			"default":
				setup["defaultCommanderId"] = 9999
		if _load_documents(content, {"story": story})["ok"]:
			fail("Invalid opening commander configuration must fail content loading: " + defect)
			return
	for candidates: Array in [[0, 9], [9]]:
		var story: Dictionary = content["story"].duplicate(true)
		var setup: Dictionary = story["sequences"]["opening"][setup_index]
		setup["candidates"] = candidates
		setup["defaultCommanderId"] = candidates[0]
		var loaded: Dictionary = _load_documents(content, {"story": story})
		if (
			not loaded["ok"]
			or loaded["story"]["sequences"]["opening"][setup_index]["candidates"] != candidates
		):
			fail("Valid commander order and subsets must come from the declared opening")
			return
	var mixed_story: Dictionary = content["story"].duplicate(true)
	mixed_story["sequences"]["opening"][setup_index]["candidates"] = [9]
	mixed_story["sequences"]["opening"][setup_index]["defaultCommanderId"] = 9.0
	for numeric_story: Dictionary in [mixed_story, JSON.parse_string(JSON.stringify(mixed_story))]:
		if not _load_documents(content, {"story": numeric_story})["ok"]:
			fail("Integral commander references must accept mixed numeric types and JSON roundtrip")
			return
	print("PASS content contracts: item layouts/identities, commander setup, fixed logical pixels")
	quit(0)


func _load_documents(_content: Dictionary, documents: Dictionary) -> Dictionary:
	var loader := ContentFixture.new()
	loader.documents = documents
	return loader.load_chapter(CHAPTER_PATH)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
