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
	var initialized_alm: Dictionary = (
		load("res://gameplay/battle_state.gd")
		. new(result, func(_limit: int) -> int: return 0)
		. unit(0)
	)
	for key: String in ["spriteOffsetX", "spriteOffsetY"]:
		for invalid: Variant in [null, "-24", 0.5]:
			var animation: Dictionary = result["mapAnimations"]["units"]["0"].duplicate(true)
			animation[key] = invalid
			if loader_script.new()._animation_valid(
				animation, result["entry"]["resourceDirectory"]
			):
				push_error("World actor offsets must reject missing or noninteger values: " + key)
				quit(1)
				return
	if Vector2i(alm["x"], alm["y"]) != Vector2i(8, 11) or initialized_alm["hp"] != 30:
		push_error("Alm opening state mismatch")
		quit(1)
		return
	var missing_speaker: Dictionary = result["story"].duplicate(true)
	missing_speaker["speakers"].erase("9")
	var ids: Dictionary = {}
	for unit: Dictionary in units:
		ids[int(unit["id"])] = unit
	for key: String in [
		"sourceWaitTicks",
		"sourceWaitTicksAfter",
		"sourceHoldTicksAfter",
		"holdTicksAfter",
		"instant"
	]:
		var broken_timing: Dictionary = result["story"].duplicate(true)
		broken_timing["sequences"]["opening"][0][key] = "invalid"
		if loader_script.new()._story_valid(
			broken_timing, result["entry"]["resourceDirectory"], ids, 20, 25, result["_deployments"]
		):
			push_error("Story clock metadata must reject invalid values before playback: " + key)
			quit(1)
			return
	if loader_script.new()._story_valid(
		missing_speaker, result["entry"]["resourceDirectory"], ids, 20, 25, result["_deployments"]
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
			broken_portrait,
			result["entry"]["resourceDirectory"],
			ids,
			20,
			25,
			result["_deployments"]
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
			broken_tutorial,
			result["entry"]["resourceDirectory"],
			ids,
			20,
			25,
			result["_deployments"]
		):
			push_error("First-XP tutorial must be validated before gameplay: " + defect)
			quit(1)
			return
	var entry: Dictionary = result["entry"].duplicate(true)
	var definition: Dictionary = {}
	for key: String in [
		"battleId", "map", "mapTexture", "deployments", "profiles", "stage", "scene"
	]:
		definition[key] = entry[key]
	var definition_path := temporary + ".battle.json"
	var story_path := temporary + ".story.json"
	var deployments_path := temporary + ".deployments.json"
	var map_path := temporary + ".map.json"
	definition["story"] = story_path
	_write_json(story_path, result["_storyFragment"])
	entry["battles"] = {entry["firstBattle"]: definition_path}
	_write_json(temporary, entry)
	var broken_definition: Dictionary = definition.duplicate(true)
	broken_definition["mapTexture"] = "res://missing_map.png"
	_write_json(definition_path, broken_definition)
	var bad_result: Dictionary = loader_script.new().load_chapter(temporary)
	if bad_result["ok"] or not bad_result["error"].contains("missing_map.png"):
		push_error("Missing asset must reject the chapter with its resource path")
		quit(1)
		return
	var broken_deployments: Array = result["_deployments"].duplicate(true)
	broken_deployments[1]["id"] = broken_deployments[0].get("id", broken_deployments[0]["sourceId"])
	_write_json(deployments_path, broken_deployments)
	broken_definition = definition.duplicate(true)
	broken_definition["deployments"] = deployments_path
	_write_json(definition_path, broken_definition)
	if loader_script.new().load_chapter(temporary)["ok"]:
		push_error("Duplicate chapter-scoped unit identities must be rejected")
		quit(1)
		return
	var broken_map: Dictionary = result["map"].duplicate(true)
	broken_map["movementCosts"]["0"][0][0] = -1
	_write_json(map_path, broken_map)
	broken_definition = definition.duplicate(true)
	broken_definition["map"] = map_path
	_write_json(definition_path, broken_definition)
	if loader_script.new().load_chapter(temporary)["ok"]:
		push_error("Nonpositive movement costs must be rejected before pathfinding")
		quit(1)
		return
	# Explicit empty names intentionally suppress the name plate without removing the speaker.
	var anonymous_story: Dictionary = result["_storyFragment"].duplicate(true)
	anonymous_story["speakers"]["10"] = {"id": 10, "name": "", "faction": 2}
	_write_json(definition_path, definition)
	_write_json(story_path, anonymous_story)
	if not loader_script.new().load_chapter(temporary)["ok"]:
		push_error("Content must accept an explicitly unnamed speaker without a portrait")
		quit(1)
		return
	for defect: String in ["missing_name", "null_name", "numeric_name", "invalid_portrait"]:
		var invalid_speaker: Dictionary = anonymous_story.duplicate(true)
		match defect:
			"missing_name":
				invalid_speaker["speakers"]["10"].erase("name")
			"null_name":
				invalid_speaker["speakers"]["10"]["name"] = null
			"numeric_name":
				invalid_speaker["speakers"]["10"]["name"] = 50
			"invalid_portrait":
				invalid_speaker["speakers"]["10"]["portraitId"] = 999
		_write_json(story_path, invalid_speaker)
		if loader_script.new().load_chapter(temporary)["ok"]:
			push_error("Unnamed speakers retain the name and portrait contracts: " + defect)
			quit(1)
			return
	var broken_story: Dictionary = result["_storyFragment"].duplicate(true)
	broken_story["sequences"].erase("opening")
	_write_json(story_path, broken_story)
	_write_json(definition_path, definition)
	if loader_script.new().load_chapter(temporary)["ok"]:
		push_error("Missing required opening sequence must fail at the content boundary")
		quit(1)
		return
	for fixture_path: String in [
		story_path, temporary, deployments_path, map_path, definition_path
	]:
		DirAccess.remove_absolute(fixture_path)
	print("PASS content: original map/deployment, missing asset, duplicate identity, invalid costs")
	quit(0)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
