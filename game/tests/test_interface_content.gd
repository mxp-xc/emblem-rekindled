extends SceneTree


func _initialize() -> void:
	var loader: RefCounted = load("res://app/chapter_content.gd").new()
	var content: Dictionary = loader.load_chapter("res://content/chapter_1/chapter.json")
	if not content["ok"]:
		fail("The original interface content must remain valid")
		return
	var directory: String = content["entry"]["interface"].get_base_dir()
	var ids: Array = []
	for unit: Dictionary in content["units"]:
		ids.append(unit["id"])
	var item_ids: Array[int] = []
	for item: Dictionary in content["rules"]["itemTemplates"]:
		if item["id"] > 0:
			item_ids.append(int(item["id"]))
	var cases: Array[Dictionary] = []
	var broken: Dictionary = content["interface"].duplicate(true)
	broken["textures"].erase("button_1")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken.erase("unitInformation")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["mapHud"]["icons"]["hp"] = "missing_texture"
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["portraitByUnitId"].erase("0")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["portraitByUnitId"]["9"]["texture"] = "missing_texture"
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["unitInformation"]["pages"][1]["attributes"].append("unknown_stat")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["labels"].erase("strength")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["equipMaskIcons"]["1"] = "missing_texture"
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["textures"].erase("item_detail_sample")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["items"]["9"].erase("name")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken.erase("battleHud")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["battleHud"]["numberFont"]["glyphs"].erase("/")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["battleHud"]["numberFont"]["glyphs"].erase("+")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["textures"].erase("attribute_13")
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["battleHud"]["forecastColumns"][0]["icon"] = "missing_texture"
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["battleHud"]["segmentedHpBar"]["segmentWidth"] = 0
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["battleHud"]["forecast"]["advantageUp"] = "missing_texture"
	cases.append(broken)
	broken = content["interface"].duplicate(true)
	broken["battleHud"]["nativeReferenceLayout"]["bottomRect"] = [0, 1, 240]
	cases.append(broken)
	for index: int in range(cases.size()):
		if loader._interface_valid(cases[index], directory, ids, item_ids):
			fail("Invalid interface references must fail at content loading, case " + str(index))
			return
	print(
		"PASS interface content: required textures/pages/labels, HUD icons, portraits, item icons"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
