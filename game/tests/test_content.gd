extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var loader_script: Script = load("res://app/chapter_content.gd")
	if loader_script == null:
		push_error("Content loader is missing")
		quit(1)
		return
	var result: Dictionary = loader_script.new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not result.get("ok", false):
		push_error(str(result))
		quit(1)
		return
	var units: Array = result["units"]
	for defect: String in ["missing", "unknown_item", "invalid_index", "fractional_index"]:
		var broken_shop: Dictionary = result["rules"].duplicate(true)
		match defect:
			"missing":
				broken_shop.erase("shopStocks")
			"unknown_item":
				broken_shop["shopStocks"][0][0] = 999
			"invalid_index":
				broken_shop["nodeShopStockIndices"][0] = 99
			"fractional_index":
				broken_shop["nodeShopStockIndices"][0] = 1.5
		if loader_script.new()._rules_valid(broken_shop):
			push_error("World shop stock references must be validated before opening: " + defect)
			quit(1)
			return
	var visible: Array = units.filter(func(unit: Dictionary) -> bool: return unit["visible"])
	if (
		result["map"]["width"] != 20
		or result["map"]["height"] != 25
		or units.size() != 32
		or visible.size() != 29
	):
		push_error("Original m0/p0 deployment mismatch")
		quit(1)
		return
	var alm: Dictionary = units.filter(func(unit: Dictionary) -> bool: return unit["id"] == 0)[0]
	for key: String in ["spriteOffsetX", "spriteOffsetY"]:
		for invalid: Variant in [null, "-24", 0.5]:
			var animation: Dictionary = result["mapAnimations"]["units"]["0"].duplicate(true)
			animation[key] = invalid
			if loader_script.new()._animation_valid(
				animation, result["entry"]["mapAnimations"].get_base_dir()
			):
				push_error("World actor offsets must reject missing or noninteger values: " + key)
				quit(1)
				return
	if Vector2i(alm["x"], alm["y"]) != Vector2i(8, 11) or alm["hp"] != 30:
		push_error("Alm opening state mismatch")
		quit(1)
		return
	var missing_speaker: Dictionary = result["story"].duplicate(true)
	missing_speaker["speakers"].erase("9")
	var ids: Dictionary = {}
	for unit: Dictionary in units:
		ids[int(unit["id"])] = true
	for key: String in [
		"sourceWaitTicks", "sourceWaitTicksAfter", "sourceHoldTicksAfter", "instant"
	]:
		var broken_timing: Dictionary = result["story"].duplicate(true)
		broken_timing["sequences"]["opening"][0][key] = "invalid"
		if loader_script.new()._story_valid(
			broken_timing, result["entry"]["story"].get_base_dir(), ids, 20, 25
		):
			push_error("Story clock metadata must reject invalid values before playback: " + key)
			quit(1)
			return
	if loader_script.new()._story_valid(
		missing_speaker, result["entry"]["story"].get_base_dir(), ids, 20, 25
	):
		push_error("Commander speaker references must be validated before the story starts")
		quit(1)
		return
	for defect: String in [
		"missing_portrait",
		"invalid_portrait",
		"missing_title_frame",
		"missing_scene_layer",
		"missing_route_portrait",
		"invalid_route_portrait",
		"wrong_boot_kind",
		"multiple_boot_steps",
		"wrong_boot_image",
		"missing_world_name",
		"empty_world_name",
		"invalid_world_name",
		"missing_world_marker",
		"missing_next_name",
		"invalid_world_node_id",
		"invalid_world_marker",
		"invalid_route_node"
	]:
		var broken_portrait: Dictionary = result["story"].duplicate(true)
		match defect:
			"missing_portrait":
				broken_portrait["images"].erase("portraits_10")
			"invalid_portrait":
				broken_portrait["sequences"]["newGame"][0]["text"]["portraitId"] = "10"
			"missing_title_frame":
				broken_portrait["images"].erase("title_01")
			"missing_scene_layer":
				broken_portrait["images"].erase("scene1")
			"missing_route_portrait":
				broken_portrait["routeChoices"][0].erase("portraitId")
			"invalid_route_portrait":
				broken_portrait["routeChoices"][0]["portraitId"] = -1
			"wrong_boot_kind":
				broken_portrait["sequences"]["boot"] = [{"kind": "focus", "cell": [8, 11]}]
			"multiple_boot_steps":
				broken_portrait["sequences"]["boot"].append(
					broken_portrait["sequences"]["boot"][0].duplicate(true)
				)
			"wrong_boot_image":
				broken_portrait["sequences"]["boot"][0]["image"] = "splash"
			"missing_world_name":
				broken_portrait["world"]["nodes"][0].erase("name")
			"empty_world_name":
				broken_portrait["world"]["nodes"][0]["name"] = ""
			"invalid_world_name":
				broken_portrait["world"]["nodes"][0]["name"] = 139
			"missing_world_marker":
				broken_portrait["images"].erase("b1")
			"missing_next_name":
				broken_portrait["world"]["nodes"][1].erase("name")
			"invalid_world_node_id":
				broken_portrait["world"]["nodes"][1]["id"] = 0
			"invalid_world_marker":
				broken_portrait["world"]["nodes"][1]["markerId"] = 2
			"invalid_route_node":
				broken_portrait["routeChoices"][0]["nodeId"] = 100
		if loader_script.new()._story_valid(
			broken_portrait, result["entry"]["story"].get_base_dir(), ids, 20, 25
		):
			push_error("Story/title asset references must fail at content entry: " + defect)
			quit(1)
			return
	var temporary := "user://test_chapter_%s.json" % str(Time.get_ticks_usec())
	for defect: String in ["missing", "empty", "duplicate", "invalid_text"]:
		var broken_tutorial: Dictionary = result["story"].duplicate(true)
		match defect:
			"missing":
				broken_tutorial.erase("tutorials")
			"empty":
				broken_tutorial["tutorials"] = []
			"duplicate":
				broken_tutorial["tutorials"].append(broken_tutorial["tutorials"][6].duplicate(true))
			"invalid_text":
				broken_tutorial["tutorials"][6]["text"] = null
		if loader_script.new()._story_valid(
			broken_tutorial, result["entry"]["story"].get_base_dir(), ids, 20, 25
		):
			push_error("First-XP tutorial must be validated before gameplay: " + defect)
			quit(1)
			return
	var entry: Dictionary = result["entry"].duplicate(true)
	entry["mapTexture"] = "res://missing_map.png"
	_write_json(temporary, entry)
	var bad_result: Dictionary = loader_script.new().load_chapter(temporary)
	if bad_result["ok"] or not bad_result["error"].contains("missing_map.png"):
		push_error("Missing asset must reject the chapter with its resource path")
		quit(1)
		return
	entry = result["entry"].duplicate(true)
	var broken_units: Array = units.duplicate(true)
	broken_units[1]["id"] = broken_units[0]["id"]
	var units_path := temporary + ".units.json"
	_write_json(units_path, broken_units)
	entry["units"] = units_path
	_write_json(temporary, entry)
	if loader_script.new().load_chapter(temporary)["ok"]:
		push_error("Duplicate chapter-scoped unit identities must be rejected")
		quit(1)
		return
	entry = result["entry"].duplicate(true)
	var map_path := temporary + ".map.json"
	var broken_map: Dictionary = result["map"].duplicate(true)
	broken_map["movementCosts"]["0"][0][0] = -1
	_write_json(map_path, broken_map)
	entry["map"] = map_path
	_write_json(temporary, entry)
	if loader_script.new().load_chapter(temporary)["ok"]:
		push_error("Nonpositive movement costs must be rejected before pathfinding")
		quit(1)
		return
	var story_path := temporary + ".story.json"
	var broken_story: Dictionary = result["story"].duplicate(true)
	broken_story["sequences"].erase("opening")
	_write_json(story_path, broken_story)
	entry = result["entry"].duplicate(true)
	entry["story"] = story_path
	_write_json(temporary, entry)
	if loader_script.new().load_chapter(temporary)["ok"]:
		push_error("Missing required opening sequence must fail at the content boundary")
		quit(1)
		return
	DirAccess.remove_absolute(story_path)
	DirAccess.remove_absolute(temporary)
	DirAccess.remove_absolute(units_path)
	DirAccess.remove_absolute(map_path)
	print("PASS content: original map/deployment, missing asset, duplicate identity, invalid costs")
	quit(0)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
