extends RefCounted

const BattleClips = preload("res://app/battle_clip_library.gd")


# Content is validated once at the app boundary, before a scene receives it.
func load_chapter(path: String) -> Dictionary:
	var entry: Variant = _read_json(path)
	if not entry is Dictionary:
		return _failure("章入口无法读取: " + path)
	for key: String in [
		"id",
		"firstBattle",
		"map",
		"units",
		"rules",
		"spawns",
		"mapAnimations",
		"battleArt",
		"battleClips",
		"battleMusic",
		"mapTexture",
		"spriteDirectory",
		"music",
		"story",
		"titleMusic",
		"worldMusic",
		"victoryMusic",
		"defeatMusic",
		"controls",
		"interface"
	]:
		if not entry.get(key) is String or entry[key].is_empty():
			return _failure("章入口缺少字段: " + key)
	var map: Variant = _read_json(entry["map"])
	var units: Variant = _read_json(entry["units"])
	var rules: Variant = _read_json(entry["rules"])
	var spawns: Variant = _read_json(entry["spawns"])
	var map_animations: Variant = _read_json(entry["mapAnimations"])
	var battle_art: Variant = _read_json(entry["battleArt"])
	var battle_clips: Variant = _read_json(entry["battleClips"])
	var story: Variant = _read_json(entry["story"])
	var controls: Variant = _read_json(entry["controls"])
	var interface_data: Variant = _read_json(entry["interface"])
	if (
		not story is Dictionary
		or not story.get("sequences") is Dictionary
		or not controls is Dictionary
		or not controls.get("opening") is Array
		or controls["opening"].is_empty()
	):
		return _failure("剧情或触控教学定义无效")
	if (
		not map is Dictionary
		or not units is Array
		or not rules is Dictionary
		or not spawns is Array
	):
		return _failure("地图、单位或规则数据无法读取")
	if not _rules_valid(rules):
		return _failure("物品、职业或属性模板无效")
	if (
		not map_animations is Dictionary
		or not map_animations.get("units") is Dictionary
		or not battle_art is Dictionary
		or not battle_art.get("appearances") is Dictionary
	):
		return _failure("角色动画定义无效")
	if (
		not _positive_integer(map.get("width"))
		or not _positive_integer(map.get("height"))
		or not _positive_integer(map.get("tileSize"))
	):
		return _failure("地图尺寸无效")
	var width: int = int(map["width"])
	var height: int = int(map["height"])
	if (
		not _grid_valid(map.get("tiles"), width, height, 0, 99)
		or not _grid_valid(map.get("terrain"), width, height, 0, 10)
	):
		return _failure("地形引用或地图尺寸无效")
	if not BattleClips.validate_art(battle_art, entry["battleArt"].get_base_dir(), map["terrain"]):
		return _failure("独立战斗画面定义或资源引用无效")
	if not BattleClips.validate_catalog(
		battle_clips, entry["battleClips"].get_base_dir(), battle_art
	):
		return _failure("独立战斗动作定义或资源引用无效")
	if not map.get("movementCosts") is Dictionary:
		return _failure("缺少职业移动消耗")
	for costs: Variant in map["movementCosts"].values():
		if not _grid_valid(costs, width, height, 1, 10000):
			return _failure("移动消耗无效")
	for resource_path: String in [
		entry["mapTexture"],
		entry["music"],
		entry["battleMusic"],
		entry["titleMusic"],
		entry["worldMusic"],
		entry["victoryMusic"],
		entry["defeatMusic"]
	]:
		if not ResourceLoader.exists(resource_path):
			return _failure("缺少随包资源: " + resource_path)
	var ids: Dictionary = {}
	var occupied: Dictionary = {}
	for unit: Variant in units:
		if not unit is Dictionary:
			return _failure("单位记录无效")
		for key: String in [
			"id",
			"faction",
			"x",
			"y",
			"classId",
			"classGroup",
			"move",
			"level",
			"hp",
			"maxHp",
			"spriteOffsetX",
			"spriteOffsetY"
		]:
			if not _integer(unit.get(key)):
				return _failure("单位字段无效: " + key)
		if ids.has(int(unit["id"])):
			return _failure("重复单位身份: " + str(unit["id"]))
		ids[int(unit["id"])] = true
		if unit["move"] < 0 or not map["movementCosts"].has(str(int(unit["classGroup"]))):
			return _failure("单位职业移动定义无效")
		if (
			not unit.get("visible") is bool
			or not unit.get("name") is String
			or not unit.get("sprite") is String
		):
			return _failure("单位显示定义无效")
		if (
			unit["x"] < 0
			or unit["x"] >= map["width"]
			or unit["y"] < 0
			or unit["y"] >= map["height"]
		):
			return _failure("单位坐标越界: " + str(unit["id"]))
		if (
			unit["faction"] < 0
			or unit["faction"] > 2
			or unit["maxHp"] < 1
			or unit["hp"] < 0
			or unit["hp"] > unit["maxHp"]
			or unit["level"] < 1
		):
			return _failure("单位状态无效: " + str(unit["id"]))
		if not ResourceLoader.exists(entry["spriteDirectory"] + unit["sprite"]):
			return _failure("缺少单位贴图: " + unit["sprite"])
		var animation: Variant = map_animations["units"].get(str(int(unit["id"])))
		if (
			not animation is Dictionary
			or not _animation_valid(animation, entry["mapAnimations"].get_base_dir())
		):
			return _failure("缺少单位动画或动画引用无效: " + str(unit["id"]))
		var cell := Vector2i(unit["x"], unit["y"])
		if unit["visible"] and occupied.has(cell):
			return _failure("可见单位位置重叠: " + str(cell))
		if unit["visible"]:
			occupied[cell] = true
	if not _interface_valid(interface_data, entry["interface"].get_base_dir(), ids.keys()):
		return _failure("人物信息、物品说明或窗口资源无效")
	if not _story_valid(story, entry["story"].get_base_dir(), ids, width, height):
		return _failure("剧情序列或资源引用无效")
	if rules["nodeShopStockIndices"].size() < story["world"]["nodes"].size():
		return _failure("世界商店地点引用无效")
	for text: Variant in controls["opening"]:
		if not text is String or text.is_empty():
			return _failure("触控教学文本无效")
	return {
		"ok": true,
		"entry": entry,
		"map": map,
		"units": units,
		"rules": rules,
		"spawns": spawns,
		"mapAnimations": map_animations,
		"battleArt": battle_art,
		"battleClips": battle_clips,
		"story": story,
		"controls": controls,
		"interface": interface_data
	}


func _interface_valid(value: Variant, directory: String, unit_ids: Array = []) -> bool:
	if (
		not value is Dictionary
		or not value.get("items") is Dictionary
		or not value.get("textures") is Dictionary
		or not value.get("labels") is Dictionary
		or not value.get("unitInformation") is Dictionary
		or not value["unitInformation"].get("pages") is Array
		or value["unitInformation"]["pages"].size() != 3
		or not value.get("equipMaskIcons") is Dictionary
	):
		return false
	for id: int in range(1, 88):
		var item: Variant = value["items"].get(str(id))
		if (
			not item is Dictionary
			or not item.get("name") is Dictionary
			or not item["name"].get("text") is String
			or item["name"]["text"].is_empty()
			or not item.get("description") is Dictionary
			or not item["description"].get("text") is String
		):
			return false
		var icon: Variant = item.get("icon")
		if icon != null and (not icon is String or not value["textures"].has(icon)):
			return false
	for id: String in [
		"window_frame",
		"content_frame",
		"item_detail_sample",
		"button_0",
		"button_1",
		"button_2",
		"side_arrow_0",
		"side_arrow_1",
		"header_sample",
		"experience",
		"attribute_13",
		"finger",
		"map_hud_background",
		"map_hud_enemy_background",
		"map_hud_hp_empty",
		"map_hud_hp_full"
	]:
		if not value["textures"].has(id):
			return false
	for texture: Variant in value["textures"].values():
		if (
			not texture is Dictionary
			or not texture.get("texture") is String
			or not ResourceLoader.exists(directory.path_join(texture["texture"]))
		):
			return false
	if (
		not value.get("mapHud") is Dictionary
		or not value["mapHud"].get("icons") is Dictionary
		or not value.get("portraitByUnitId") is Dictionary
	):
		return false
	for role: String in ["menu", "back", "hp", "level", "evasion", "defense"]:
		var reference: Variant = value["mapHud"]["icons"].get(role)
		if not reference is String or not value["textures"].has(reference):
			return false
	for mask: String in ["1", "2", "4", "8", "16", "32"]:
		var reference: Variant = value["equipMaskIcons"].get(mask)
		if not reference is String or not value["textures"].has(reference):
			return false
	var attributes: Array = [
		["attack", "critical", "hit", "evasion", "range"],
		["strength", "skill", "speed", "resistance", "defense", "luck", "movement"]
	]
	for index: int in range(3):
		var page: Variant = value["unitInformation"]["pages"][index]
		if not page is Dictionary or not page.get("title") is String or page["title"].is_empty():
			return false
		if index < 2:
			if page.get("attributes") != attributes[index]:
				return false
			for stat: String in attributes[index]:
				var label: Variant = value["labels"].get(stat)
				if not label is Dictionary or not label.get("text") is String:
					return false
	for id: Variant in unit_ids + [0, 9]:
		var portrait: Variant = value["portraitByUnitId"].get(str(int(id)))
		if (
			not portrait is Dictionary
			or not portrait.get("usesCommanderPortrait") is bool
			or not portrait.has("texture")
		):
			return false
		var reference: Variant = portrait["texture"]
		if reference != null and (not reference is String or not value["textures"].has(reference)):
			return false
	return _battle_hud_valid(value.get("battleHud"), value["textures"])


func _battle_hud_valid(hud: Variant, textures: Dictionary) -> bool:
	if not hud is Dictionary:
		return false
	for key: String in [
		"nativeReferenceLayout",
		"numberFont",
		"currentHp",
		"predictionRow",
		"segmentedHpBar",
		"forecast"
	]:
		if not hud.get(key) is Dictionary:
			return false
	for key: String in [
		"battle_hud_top",
		"battle_hud_bottom",
		"forecast_hud_top",
		"forecast_hud_bottom",
		"battle_hp_full",
		"battle_hp_empty",
		"corner_0",
		"corner_1",
		"corner_2",
		"corner_3"
	]:
		if not textures.has(key):
			return false
	if not hud["forecast"].get("nativeReferenceLayout") is Dictionary:
		return false
	for layout: Dictionary in [
		hud["nativeReferenceLayout"], hud["forecast"]["nativeReferenceLayout"]
	]:
		for key: String in ["topRect", "bottomRect"]:
			if not layout.get(key) is Array or layout[key].size() != 4:
				return false
			for coordinate: Variant in layout[key]:
				if not _integer(coordinate):
					return false
			if layout[key][2] <= 0 or layout[key][3] <= 0:
				return false
	var font: Dictionary = hud["numberFont"]
	if (
		not font.get("glyphs") is Dictionary
		or not _positive_integer(font.get("advance"))
		or not _positive_integer(font.get("height"))
	):
		return false
	for character: String in "0123456789/*-+":
		if not textures.has(font["glyphs"].get(character)):
			return false
	if not hud.get("forecastColumns") is Array or hud["forecastColumns"].size() != 3:
		return false
	for column: Variant in hud["forecastColumns"]:
		if (
			not column is Dictionary
			or column.get("id") not in ["attack", "hit", "critical"]
			or not textures.has(column.get("icon"))
			or not _integer(column.get("nativeX"))
		):
			return false
	for key: String in ["topY", "bottomY"]:
		if not _integer(hud["predictionRow"].get(key)):
			return false
	for key: String in ["textOriginTop", "textOriginBottom"]:
		if not _point_valid(hud["currentHp"].get(key)):
			return false
	var bars: Dictionary = hud["segmentedHpBar"]
	for key: String in ["topOrigin", "bottomOrigin"]:
		if not _point_valid(bars.get(key)):
			return false
	for key: String in ["pixelsPerHp", "segmentWidth", "segmentHeight"]:
		if not _positive_integer(bars.get(key)):
			return false
	if (
		not _integer(bars.get("firstSegmentClipLeftPixels"))
		or bars["firstSegmentClipLeftPixels"] < 0
		or bars["firstSegmentClipLeftPixels"] >= bars["segmentWidth"]
	):
		return false
	for key: String in ["fullTexture", "emptyTexture"]:
		if not textures.has(bars.get(key)):
			return false
	for key: String in ["advantageUp", "advantageDown", "targetArrow"]:
		if not textures.has(hud["forecast"].get(key)):
			return false
	return true


func _point_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1])


func _animation_valid(animation: Dictionary, directory: String) -> bool:
	if (
		not animation.get("frames") is Array
		or animation["frames"].is_empty()
		or not animation.get("completedFrame") is Dictionary
		or not _integer(animation.get("spriteOffsetX"))
		or not _integer(animation.get("spriteOffsetY"))
	):
		return false
	var frames: Array = animation["frames"].duplicate()
	frames.append(animation["completedFrame"])
	for frame: Variant in frames:
		if (
			not frame is Dictionary
			or not frame.get("texture") is String
			or not ResourceLoader.exists(directory.path_join(frame["texture"]))
		):
			return false
	for mode: String in ["idle", "walk"]:
		var step: Variant = animation.get(mode + "StepSeconds")
		if not (step is int or step is float) or not is_finite(float(step)) or step <= 0:
			return false
		if not animation.get(mode + "Sequence") is Array or animation[mode + "Sequence"].is_empty():
			return false
		for index: Variant in animation[mode + "Sequence"]:
			if not _integer(index) or index < 0 or index >= animation["frames"].size():
				return false
	return true


func _rules_valid(rules: Dictionary) -> bool:
	for key: String in [
		"itemTemplates",
		"jobTemplates",
		"baseStats",
		"growthRates",
		"terrainDefense",
		"terrainEvasion",
		"alliances",
		"baseMovementCosts",
		"aiClassOrder",
		"shopStocks",
		"nodeShopStockIndices"
	]:
		if not rules.get(key) is Array or rules[key].is_empty():
			return false
	if (
		not _integer(rules.get("initialGold"))
		or rules["initialGold"] < 0
		or rules["initialGold"] > 9999999
		or rules["baseMovementCosts"].size() < 11
		or rules["aiClassOrder"].size() < 12
	):
		return false
	if not rules.get("statCaps") is Dictionary:
		return false
	for key: String in ["itemTemplates", "jobTemplates", "baseStats", "growthRates"]:
		var ids: Dictionary = {}
		for row: Variant in rules[key]:
			if (
				not row is Dictionary
				or not _integer(row.get("id"))
				or row["id"] < 0
				or ids.has(row["id"])
			):
				return false
			ids[row["id"]] = true
	for item: Dictionary in rules["itemTemplates"]:
		if (
			not item.get("name") is String
			or item.get("damageKind") not in ["physical", "magic", "healing", "none"]
		):
			return false
		for key: String in [
			"categoryMask",
			"power",
			"hit",
			"critical",
			"minRange",
			"maxRange",
			"weight",
			"defaultDurability",
			"price"
		]:
			if not _integer(item.get(key)):
				return false
		if (
			item["minRange"] < 0
			or item["maxRange"] < item["minRange"]
			or item["defaultDurability"] < 0
			or item["price"] < 0
		):
			return false
		if (
			not item.get("doubleStrike") is bool
			or not item.get("drainsHp") is bool
			or not item.get("ignoresDefense") is bool
			or not item.get("effectiveGroups") is Array
		):
			return false
	var item_ids: Dictionary = {}
	for item: Dictionary in rules["itemTemplates"]:
		item_ids[int(item["id"])] = true
	for stock: Variant in rules["shopStocks"]:
		if not stock is Array or stock.is_empty():
			return false
		for id: Variant in stock:
			if not _positive_integer(id) or not item_ids.has(int(id)):
				return false
	for index: Variant in rules["nodeShopStockIndices"]:
		if not _integer(index) or index < 0 or index >= rules["shopStocks"].size():
			return false
	for table: String in ["baseStats", "growthRates"]:
		for row: Dictionary in rules[table]:
			for key: String in [
				"strength", "skill", "speed", "defense", "magic", "luck", "maxHp", "move"
			]:
				if not _integer(row.get(key)) or row[key] < 0:
					return false
	for key: String in [
		"terrainDefense", "terrainEvasion", "alliances", "baseMovementCosts", "aiClassOrder"
	]:
		for value: Variant in rules[key]:
			if not _integer(value) or value < 0:
				return false
	return true


func _grid_valid(grid: Variant, width: int, height: int, minimum: int, maximum: int) -> bool:
	if not grid is Array or grid.size() != height:
		return false
	for row: Variant in grid:
		if not row is Array or row.size() != width:
			return false
		for value: Variant in row:
			if not _integer(value) or value < minimum or value > maximum:
				return false
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data


func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
	)


func _positive_integer(value: Variant) -> bool:
	return _integer(value) and value > 0


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _story_valid(
	story: Dictionary, directory: String, ids: Dictionary, width: int, height: int
) -> bool:
	if not story.get("tutorials") is Array:
		return false
	var tutorials: Dictionary = {}
	for tutorial: Variant in story["tutorials"]:
		if (
			not tutorial is Dictionary
			or not _integer(tutorial.get("id"))
			or tutorials.has(int(tutorial["id"]))
		):
			return false
		tutorials[int(tutorial["id"])] = tutorial
	if (
		not tutorials.has(6)
		or not tutorials[6].get("text") is String
		or tutorials[6]["text"].is_empty()
	):
		return false
	for sequence: String in ["boot", "newGame", "opening", "reinforcements", "victory", "defeat"]:
		if not story["sequences"].get(sequence) is Array or story["sequences"][sequence].is_empty():
			return false
		for step: Variant in story["sequences"][sequence]:
			if not step is Dictionary or not _story_step_valid(step, ids, width, height):
				return false
	var boot: Array = story["sequences"]["boot"]
	if boot.size() != 1 or boot[0]["kind"] != "prologue" or boot[0].get("image") != "intro0":
		return false
	if (
		not story.get("images") is Dictionary
		or not story.get("world") is Dictionary
		or not story.get("speakers") is Dictionary
		or not story.get("initialBattlePresentation") is Dictionary
	):
		return false
	if (
		not story.get("outcomeRules") is Dictionary
		or not story.get("reinforcementTrigger") is Dictionary
	):
		return false
	var outcome: Dictionary = story["outcomeRules"]
	if (
		not _integer(outcome.get("enemyFaction"))
		or outcome["enemyFaction"] < 0
		or outcome["enemyFaction"] > 2
		or not _integer(outcome.get("escapeUnitId"))
		or not ids.has(int(outcome["escapeUnitId"]))
		or not _integer(outcome.get("escapeRow"))
		or outcome["escapeRow"] < 0
		or outcome["escapeRow"] >= height
		or not outcome.get("requiredUnitIds") is Array
		or outcome["requiredUnitIds"].is_empty()
	):
		return false
	for id: Variant in outcome["requiredUnitIds"]:
		if not _integer(id) or not ids.has(int(id)):
			return false
	var reinforcement: Dictionary = story["reinforcementTrigger"]
	if (
		not _positive_integer(reinforcement.get("afterEnemyPhaseOfRound"))
		or reinforcement.get("once") != true
	):
		return false
	for image_id: String in [
		"splash",
		"intro0",
		"scene0",
		"scene1",
		"scene2",
		"title_00",
		"title_01",
		"b0",
		"b1",
		"portraits_00",
		"portraits_09"
	]:
		if not story["images"].has(image_id):
			return false
	if not story.get("routeChoices") is Array or story["routeChoices"].is_empty():
		return false
	var routes: Dictionary = {}
	for route: Variant in story["routeChoices"]:
		if (
			not route is Dictionary
			or not _integer(route.get("routeIndex"))
			or routes.has(int(route["routeIndex"]))
			or not route.get("label") is String
			or not _integer(route.get("portraitId"))
			or not story["images"].has("portraits_%02d" % int(route["portraitId"]))
		):
			return false
		routes[int(route["routeIndex"])] = true
	var images: Array = story["images"].values()
	images.append(story["world"])
	for image: Variant in images:
		if (
			not image is Dictionary
			or not image.get("texture") is String
			or not ResourceLoader.exists(directory.path_join(image["texture"]))
		):
			return false
	for id: Variant in story["speakers"]:
		var speaker: Variant = story["speakers"][id]
		if (
			not id is String
			or not id.is_valid_int()
			or not speaker is Dictionary
			or not speaker.get("name") is String
			or speaker["name"].is_empty()
		):
			return false
		var portrait_id: Variant = speaker.get("portraitId")
		if (
			portrait_id != null
			and (
				not _integer(portrait_id)
				or not story["images"].has("portraits_%02d" % int(portrait_id))
			)
		):
			return false
	for id: String in ["0", "9"]:
		if not story["speakers"].has(id):
			return false
	for sequence: Variant in story["sequences"]:
		if not sequence is String or not story["sequences"][sequence] is Array:
			return false
		for step: Variant in story["sequences"][sequence]:
			if not step is Dictionary:
				return false
			if step.has("text") and step["text"].get("speakerId") != null:
				var speaker_id: String = str(int(step["text"]["speakerId"]))
				if not story["speakers"].has(speaker_id):
					return false
			var portrait_id: Variant = step.get("text", {}).get("portraitId")
			if (
				portrait_id != null
				and (
					not _integer(portrait_id)
					or not story["images"].has("portraits_%02d" % int(portrait_id))
				)
			):
				return false
			if (
				step["kind"] == "prologue"
				and (not step.get("image") is String or not story["images"].has(step["image"]))
			):
				return false
	if (
		not story.get("battleName") is Dictionary
		or not _story_text_valid(story["battleName"])
		or not story.get("labels") is Dictionary
		or not story["labels"].get("newGame") is Dictionary
		or not _story_text_valid(story["labels"]["newGame"])
	):
		return false
	var initial: Dictionary = story["initialBattlePresentation"]
	if (
		not initial.get("hiddenUnitIds") is Array
		or not initial.get("hiddenFactions") is Array
		or not initial.get("unitPositionOverrides") is Dictionary
	):
		return false
	for id: Variant in initial["hiddenUnitIds"]:
		if not _integer(id) or not ids.has(int(id)):
			return false
	for faction: Variant in initial["hiddenFactions"]:
		if not _integer(faction) or faction < 0 or faction > 2:
			return false
	for id: Variant in initial["unitPositionOverrides"]:
		if (
			not id is String
			or not id.is_valid_int()
			or not ids.has(int(id))
			or not _story_cell_valid(initial["unitPositionOverrides"][id], width, height)
		):
			return false
	var world: Dictionary = story["world"]
	if (
		not _positive_integer(world.get("width"))
		or not _positive_integer(world.get("height"))
		or not world.get("nodes") is Array
		or world["nodes"].is_empty()
	):
		return false
	for index: int in range(world["nodes"].size()):
		var node: Variant = world["nodes"][index]
		if (
			not node is Dictionary
			or not _integer(node.get("id"))
			or node["id"] != index
			or not node.get("name") is String
			or node["name"].is_empty()
			or not _integer(node.get("markerId"))
			or int(node["markerId"]) not in [-1, 0, 1]
			or not _story_cell_valid(
				node.get("position"), int(world["width"]), int(world["height"])
			)
		):
			return false
	for route: Dictionary in story["routeChoices"]:
		if (
			not _integer(route.get("nodeId"))
			or route["nodeId"] <= 0
			or route["nodeId"] >= world["nodes"].size()
		):
			return false
	return true


func _story_step_valid(step: Dictionary, ids: Dictionary, width: int, height: int) -> bool:
	for timing: String in ["sourceWaitTicks", "sourceWaitTicksAfter", "sourceHoldTicksAfter"]:
		if step.has(timing) and (not _integer(step[timing]) or step[timing] < 0):
			return false
	if step.has("instant") and not step["instant"] is bool:
		return false
	if (
		step.get("kind")
		in [
			"prologue",
			"worldNarration",
			"dialogue",
			"objective",
			"instruction",
			"missionComplete",
			"gameOver"
		]
	):
		return (
			step.get("text") is Dictionary
			and _story_text_valid(step["text"])
			and (
				step.get("kind") != "missionComplete"
				or (_integer(step.get("goldReward")) and step["goldReward"] >= 0)
			)
		)
	match step.get("kind"):
		"focus":
			return _story_cell_valid(step.get("cell"), width, height)
		"unitEntrance":
			return (
				_integer(step.get("unitId"))
				and ids.has(int(step["unitId"]))
				and _story_cell_valid(step.get("from"), width, height, true)
				and _story_cell_valid(step.get("to"), width, height)
			)
		"parallelEntrances":
			if (
				not _story_cell_valid(step.get("focus"), width, height)
				or not step.get("units") is Array
				or step["units"].is_empty()
			):
				return false
			for entrance: Variant in step["units"]:
				if (
					not entrance is Dictionary
					or entrance.get("kind") != "unitEntrance"
					or not _story_step_valid(entrance, ids, width, height)
				):
					return false
			return true
		"revealFaction":
			return _integer(step.get("faction")) and step["faction"] >= 0 and step["faction"] <= 2
		"commanderSetup":
			return (
				step.get("candidates") is Array
				and step["candidates"].size() == 2
				and step["candidates"][0] == 9
				and step["candidates"][1] == 0
				and step.get("defaultCommanderId") in step["candidates"]
			)
		"tutorial":
			return step.get("tutorialId") == 0
		"worldMarker":
			return step.get("nodeId") == 0
		"enterBattle":
			return step.get("battleId") == "m0"
		"routeChoice":
			if not step.get("options") is Array or step["options"].is_empty():
				return false
			for route: Variant in step["options"]:
				if (
					not route is Dictionary
					or not route.get("label") is String
					or not _integer(route.get("routeIndex"))
				):
					return false
			return true
	return false


func _story_cell_valid(cell: Variant, width: int, height: int, offscreen: bool = false) -> bool:
	return (
		cell is Array
		and cell.size() == 2
		and _integer(cell[0])
		and _integer(cell[1])
		and (offscreen or (cell[0] >= 0 and cell[0] < width and cell[1] >= 0 and cell[1] < height))
	)


func _story_text_valid(line: Dictionary) -> bool:
	return (
		line.get("text") is String
		and not line["text"].is_empty()
		and _integer(line.get("sourceTextIndex"))
		and (line.get("speakerId") == null or _integer(line["speakerId"]))
	)
