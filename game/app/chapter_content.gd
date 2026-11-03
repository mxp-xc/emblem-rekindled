extends RefCounted

const Promotions = preload("res://app/chapter_promotions.gd")
const BattleClips = preload("res://app/battle_clip_library.gd")
const MapView = preload("res://features/tactical_map/map_view.gd")
const ContentProjection = preload("res://app/chapter_projection.gd")
const Deployment = preload("res://app/chapter_deployment.gd")
const Clones = preload("res://gameplay/battle_clones.gd")
const Summons = preload("res://gameplay/battle_summons.gd")
const StoryContract = preload("res://app/chapter_story_contract.gd")
const MapAttacks = preload("res://gameplay/map_attack_rules.gd")
const TextureOverrides = preload("res://app/chapter_texture_overrides.gd")
const RetirementPlayer = preload("res://features/battle/retirement_player.gd")
const JsonDocument = preload("res://app/json_document.gd")


# Content is validated once at the app boundary, before a scene receives it.
func load_chapter(
	path: String,
	battle_id: String = "",
	context: Dictionary = {},
	documents: Dictionary = {},
	prepare_promotions: bool = true
) -> Dictionary:
	var entry: Variant = _read_json(path, documents)
	if not entry is Dictionary:
		return _failure("章入口无法读取: " + path)
	if not entry.get("firstBattle") is String:
		return _failure("章入口缺少首个关卡")
	if battle_id.is_empty():
		battle_id = entry["firstBattle"]
	var catalog: Variant = entry.get("battles")
	if not catalog is Dictionary or not catalog.get(battle_id) is String:
		return _failure("关卡尚未接入: " + battle_id)
	if (
		battle_id != entry["firstBattle"]
		and (not context.has("party") or not context.has("partyOrder"))
	):
		return _failure("进入关卡缺少队伍来源: " + battle_id)
	var definition: Variant = _read_json(catalog[battle_id], documents)
	if not definition is Dictionary or definition.get("battleId") != battle_id:
		return _failure("关卡入口身份无效: " + battle_id)
	if definition.has("textureOverrides"):
		return _failure("图片替换表只在章入口声明")
	for key: String in ["library", "rules", "controls"]:
		if not entry.get(key) is String or entry[key].is_empty():
			return _failure("章入口缺少字段: " + key)
	for key: String in ["map", "mapTexture", "deployments", "story"]:
		if not definition.get(key) is String or definition[key].is_empty():
			return _failure("关卡入口缺少字段: " + key)
	var library: Variant = _read_json(entry["library"], documents)
	var records: Variant = _read_json(definition["deployments"], documents)
	var fragment: Variant = _read_json(definition["story"], documents)
	if not library is Dictionary or not records is Array or not fragment is Dictionary:
		return _failure("章内容库、部署或剧情无法读取: " + battle_id)
	var texture_plan: Dictionary = TextureOverrides.read_plan(entry, library, _read_json)
	if not texture_plan["ok"]:
		return texture_plan
	var chapter_id: Variant = entry.get("id")
	entry = entry.duplicate(true)
	entry.merge(definition, true)
	entry["id"] = chapter_id
	entry["battleId"] = battle_id
	entry["chapterPath"] = path
	return _resolve(
		entry, library, records, fragment, context, texture_plan["overrides"], prepare_promotions
	)


# Rebind after random placement or restore, without rereading or mutating the catalog.
func resolve_loaded(content: Dictionary, context: Dictionary) -> Dictionary:
	for key: String in [
		"_library", "_deployments", "_storyFragment", "_baseEntry", "_textureOverrides"
	]:
		if not content.has(key):
			return _failure("缺少已读取的关卡定义: " + key)
	return _resolve(
		content["_baseEntry"].duplicate(true),
		content["_library"],
		content["_deployments"],
		content["_storyFragment"],
		context,
		content["_textureOverrides"]
	)


func reproject(
	content: Dictionary, units: Array, clone_state: Dictionary = {}, summon_state: Dictionary = {}
) -> Dictionary:
	var context: Dictionary = content.get("_context", {}).duplicate(true)
	context["units"] = units
	context["cloneState"] = clone_state
	context["summonState"] = summon_state
	var projected: Dictionary = resolve_loaded(content, context)
	if projected.get("ok", false) and content.has("inheritedParty"):
		projected["inheritedParty"] = content["inheritedParty"].duplicate(true)
	return projected


func _resolve(
	entry: Dictionary,
	library: Dictionary,
	records: Array,
	fragment: Dictionary,
	context: Dictionary,
	texture_overrides: Dictionary,
	prepare_promotions: bool = true
) -> Dictionary:
	var base_entry: Dictionary = entry.duplicate(true)
	if (
		not _integer(context.get("worldStep", 0))
		or context.get("worldStep", 0) < 0
		or not context.get("bindings", {}) is Dictionary
		or not context.get("classes", {}) is Dictionary
		or not context.get("units", []) is Array
	):
		return _failure("关卡来源上下文无效")
	var clones: Dictionary = Clones.definition(fragment.get("periodicClones"), records)
	if not clones["ok"]:
		return clones
	context = context.duplicate(true)
	context["allowEmptySlots"] = fragment.get("encounter", false) == true
	var rules: Variant = _read_json(entry["rules"])
	if not rules is Dictionary or not library.get("profiles") is Dictionary:
		return _failure("章规则无法读取")
	var promotions: Dictionary = Promotions.context(rules, library["profiles"])
	if not promotions["ok"]:
		return promotions
	context["_promotions"] = promotions
	context.erase("cloneBindings")
	context.erase("summonBindings")
	context.erase("replacedIndices")
	if context.has("units"):
		var summons: Dictionary = Summons.current_bindings(
			library.get("summons", {}), records, context["units"], context.get("summonState", {})
		)
		if not summons["ok"]:
			return summons
		var current: Dictionary = Clones.current_bindings(
			fragment.get("periodicClones"),
			records,
			summons["staticUnits"],
			context.get("cloneState", {})
		)
		if not current["ok"]:
			return current
		for binding: Dictionary in summons["bindings"]:
			if int(binding["afterCloneGeneration"]) >= int(current["nextGeneration"]):
				return _failure("INVALID_SUMMON_CLONE_ANCHOR")
		var bound: Dictionary = Deployment.infer_bindings(
			records,
			context.get("party", []),
			current["staticUnits"],
			current["replacedIndices"] + summons["replacedIndices"],
			promotions,
			context["allowEmptySlots"]
		)
		if not bound["ok"]:
			return bound
		context["bindings"] = bound["bindings"]
		context["classes"] = bound["classes"]
		context["cloneBindings"] = current["bindings"]
		context["replacedIndices"] = current["replacedIndices"] + summons["replacedIndices"]
		context["summonBindings"] = summons["bindings"]
	entry["resourceDirectory"] = "res://"
	var projected: Dictionary = ContentProjection.project(entry, entry, library, records, context)
	if not projected["ok"]:
		return projected
	for key: String in ["mapAnimations", "battleArt", "battleClips", "interface"]:
		entry[key] = entry["library"]
	entry["spriteDirectory"] = ""
	var story: Dictionary = ContentProjection.merge_story(projected["storyCommon"], fragment)
	story["battleId"] = entry["battleId"]
	var resolved_texts: Dictionary = ContentProjection.resolve_texts(story, library["texts"])
	if not resolved_texts["ok"]:
		return resolved_texts
	story = resolved_texts["value"]
	var story_context: Dictionary = context.duplicate(true)
	story_context["recruitByNode"] = entry.get("recruitByNode", {})
	story_context["referenceIds"] = projected["referenceIds"]
	var story_slots: Dictionary = projected["slots"].duplicate()
	for record: Dictionary in records:
		if record.has("deploymentSlot") and not story_slots.has(int(record["deploymentSlot"])):
			story_slots[int(record["deploymentSlot"])] = -1
	var resolved_story: Dictionary = ContentProjection.resolve_story(
		story, projected["units"], story_slots, story_context
	)
	if not resolved_story["ok"]:
		return resolved_story
	for sequence: Array in resolved_story["story"]["sequences"].values():
		for step: Dictionary in sequence:
			if step.get("kind") == "enterBattle" and not entry["battles"].has(step.get("battleId")):
				return _failure("剧情引用未接入关卡: " + str(step.get("battleId")))
	projected["story"] = resolved_story["story"]
	projected["_deployments"] = records
	projected["entry"] = entry
	projected["map"] = _read_json(entry["map"])
	projected["rules"] = rules
	projected["controls"] = _read_json(entry["controls"])
	projected = TextureOverrides.apply(projected, texture_overrides)
	for key: String in [
		"mapAnimations", "battleArt", "battleClips", "interface", "mapEffects", "story"
	]:
		projected[key] = ContentProjection.relative_resources(projected[key])
	var result: Dictionary = _validate(projected)
	if result["ok"]:
		result["_library"] = library
		result["_deployments"] = records
		result["_storyFragment"] = fragment
		result["_context"] = context.duplicate(true)
		result["_baseEntry"] = base_entry
		result["_textureOverrides"] = texture_overrides
		if prepare_promotions:
			_prepare_promotion_targets(result)
	return result


# Optional future art is checked before a command may consume the emblem or RNG.
# A missing future family does not prevent opening an unrelated old battle.
func _prepare_promotion_targets(content: Dictionary) -> void:
	content["promotionTargets"] = {}
	content["promotionErrors"] = {}
	var promotions: Dictionary = content["_context"]["_promotions"]
	for actor: Dictionary in content["units"]:
		if not actor.has("promotionBaseClassId"):
			continue
		var base: int = int(actor["promotionBaseClassId"])
		if actor["classId"] != base:
			continue
		var identity: int = int(actor["id"])
		var target: int = int(promotions["pairs"][base])
		var context: Dictionary = content["_context"].duplicate(true)
		context["classes"] = context.get("classes", {}).duplicate()
		for member: Dictionary in context.get("party", []):
			if member["id"] == identity:
				member["classId"] = target
		context["classes"][int(actor["deploymentIndex"])] = target
		for saved: Dictionary in context.get("units", []):
			if saved["id"] == identity:
				saved["classId"] = target
		var future: Dictionary = _resolve(
			content["_baseEntry"].duplicate(true),
			content["_library"],
			content["_deployments"],
			content["_storyFragment"],
			context,
			content["_textureOverrides"],
			false
		)
		if not future["ok"]:
			content["promotionErrors"][identity] = future.get(
				"error", "MISSING_PROMOTION_PRESENTATION"
			)
			continue
		for candidate: Dictionary in future["units"]:
			if candidate["id"] == identity:
				content["promotionTargets"][identity] = candidate.duplicate(true)
				break


func _validate(content: Dictionary) -> Dictionary:
	var entry: Dictionary = content["entry"]
	for key: String in [
		"id",
		"firstBattle",
		"map",
		"rules",
		"mapAnimations",
		"battleArt",
		"battleClips",
		"battleMusic",
		"mapTexture",
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
	var map: Variant = content["map"]
	var units: Variant = content["units"]
	var rules: Variant = content["rules"]
	var spawns: Variant = content["spawns"]
	var map_animations: Variant = content["mapAnimations"]
	var battle_art: Variant = content["battleArt"]
	var battle_clips: Variant = content["battleClips"]
	var story: Variant = content["story"]
	var controls: Variant = content["controls"]
	var interface_data: Variant = content["interface"]
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
	var spawn_items: Dictionary = _spawn_references_valid(spawns, rules)
	if not spawn_items["ok"]:
		return spawn_items
	if not _map_effects_valid(content.get("mapEffects"), entry["resourceDirectory"]):
		return _failure("地图技能表现定义或资源引用无效")
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
		or not _integer(map.get("tileSize"))
		or map["tileSize"] != MapView.TILE_PIXELS
	):
		return _failure("地图尺寸无效")
	var width: int = int(map["width"])
	var height: int = int(map["height"])
	if (
		not _grid_valid(map.get("tiles"), width, height, 0, 99)
		or not _grid_valid(map.get("terrain"), width, height, 0, 10)
	):
		return _failure("地形引用或地图尺寸无效")
	if not StoryContract.validate_locations(map, rules, story):
		return _failure("地图地点、奖励或开启图块定义无效")
	var reachable_terrain: Array = map["terrain"].duplicate(true)
	for variant: Dictionary in map.get("tileVariants", {}).values():
		reachable_terrain.append([int(variant["terrain"])])
	if not BattleClips.validate_art(battle_art, entry["resourceDirectory"], reachable_terrain):
		return _failure("独立战斗画面定义或资源引用无效")
	if not RetirementPlayer.validate_definition(battle_art, entry["resourceDirectory"]):
		return _failure("地图退场表现定义或资源引用无效")
	if not BattleClips.validate_catalog(battle_clips, entry["resourceDirectory"], battle_art):
		return _failure("独立战斗动作定义或资源引用无效")
	if not _action_presentations_valid(rules, battle_clips, content["mapEffects"]):
		return _failure("物品行动方式与人物动作或地图技能表现不匹配")
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
		if unit["id"] < 0:
			return _failure("单位身份无效: " + str(unit["id"]))
		if ids.has(int(unit["id"])):
			return _failure("重复单位身份: " + str(unit["id"]))
		ids[int(unit["id"])] = unit
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
			or not _animation_valid(animation, entry["resourceDirectory"])
		):
			return _failure("缺少单位动画或动画引用无效: " + str(unit["id"]))
		var cell := Vector2i(unit["x"], unit["y"])
		if unit["visible"] and occupied.has(cell):
			return _failure("可见单位位置重叠: " + str(cell))
		if unit["visible"]:
			occupied[cell] = true
	var item_ids: Array[int] = []
	for item: Dictionary in rules["itemTemplates"]:
		if item["id"] > 0:
			item_ids.append(int(item["id"]))
	if not _interface_valid(interface_data, entry["resourceDirectory"], ids.keys(), item_ids):
		return _failure("人物信息、物品说明或窗口资源无效")
	for id: int in content.get("referenceIds", []):
		if not ids.has(id):
			ids[id] = {}
	if (
		story.get("battleId") != entry["battleId"]
		or not _story_valid(
			story, entry["resourceDirectory"], ids, width, height, content["_deployments"]
		)
	):
		return _failure("剧情序列或资源引用无效")
	if rules["nodeShopStockIndices"].size() < story["world"]["nodes"].size():
		return _failure("世界商店地点引用无效")
	for text: Variant in controls["opening"]:
		if not text is String or text.is_empty():
			return _failure("触控教学文本无效")
	return content


func _spawn_references_valid(spawns: Array, rules: Dictionary) -> Dictionary:
	var declared: Dictionary = {}
	for item: Dictionary in rules["itemTemplates"]:
		declared[int(item["id"])] = true
	var bases: Dictionary = {}
	var growth: Dictionary = {}
	for row: Dictionary in rules["baseStats"]:
		bases[int(row["id"])] = true
	for row: Dictionary in rules["growthRates"]:
		growth[int(row["id"])] = true
	var jobs: Dictionary = {}
	for job: Dictionary in rules["jobTemplates"]:
		jobs[int(job["id"])] = int(job["classGroup"])
	for index: int in range(spawns.size()):
		var spawn: Variant = spawns[index]
		if not spawn is Dictionary or not spawn.get("itemChoices") is Array:
			return _failure("部署物品定义无效: " + str(index))
		var references: Array = spawn["itemChoices"].duplicate()
		references.append(spawn.get("dropTemplateId"))
		for id: Variant in references:
			if not _integer(id) or id < 0:
				return _failure("部署物品编号无效: " + str(index))
			if id != 0 and not declared.has(int(id)):
				return _failure("部署%d引用未声明物品: %d" % [index, int(id)])
		var unused_element_growth: bool = (
			spawn.has("explicitStats")
			and spawn.get("faction") == 2
			and spawn.get("level") == 20
			and jobs.get(int(spawn["classId"]), -1) == 10
			and spawn.get("growthTemplateId") == 20
		)
		if (
			not _integer(spawn.get("growthTemplateId"))
			or (not growth.has(int(spawn["growthTemplateId"])) and not unused_element_growth)
		):
			return _failure("部署%d引用未声明成长模板" % index)
		if not spawn.has("explicitStats"):
			if (
				not _integer(spawn.get("baseTemplateId"))
				or not bases.has(int(spawn["baseTemplateId"]))
			):
				return _failure("部署%d引用未声明基础属性模板" % index)
			if (
				not _integer(spawn.get("initialGrowthTemplateId"))
				or not growth.has(int(spawn["initialGrowthTemplateId"]))
			):
				return _failure("部署%d引用未声明初始成长模板" % index)
	return {"ok": true}


func _map_effects_valid(value: Variant, directory: String) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		var effect: Variant = value[key]
		if (
			not key is String
			or key.is_empty()
			or not effect is Dictionary
			or not effect.get("source") is String
			or effect["source"].is_empty()
			or effect.get("logicalTickUnits") != 50
		):
			return false
		match effect.get("kind"):
			"shake":
				if (
					not _positive_integer(effect.get("durationUnits"))
					or int(effect["durationUnits"]) % 50 != 0
					or not _point_valid(effect.get("shakeModuli"))
					or effect["shakeModuli"][0] <= 0
					or effect["shakeModuli"][1] <= 0
					or not _integer(effect.get("flashUpdates"))
					or effect["flashUpdates"] < 0
					or effect["flashUpdates"] * 50 > effect["durationUnits"]
					or not _integer(effect.get("flashColor"))
					or effect["flashColor"] < 0
					or effect["flashColor"] > 16777215
					or not effect.get("flashOnEven") is bool
				):
					return false
			"sprite":
				if (
					not effect.get("sprite") is Dictionary
					or effect.get("anchor") != "bottomCenter"
					or not _point_valid(effect.get("unitOffset"))
					or not _positive_integer(effect.get("cycles"))
					or not _positive_integer(effect.get("stepUnits"))
					or int(effect["stepUnits"]) % 50 != 0
					or not _integer(effect.get("shakeUpdates"))
					or effect["shakeUpdates"] < 0
					or not _point_valid(effect.get("jitterRangeX"))
					or effect["jitterRangeX"][0] > effect["jitterRangeX"][1]
					or not _point_valid(effect.get("jitterRangeY"))
					or effect["jitterRangeY"][0] > effect["jitterRangeY"][1]
				):
					return false
				var sprite: Dictionary = effect["sprite"]
				if (
					not _positive_integer(sprite.get("virtualWidth"))
					or not _positive_integer(sprite.get("virtualHeight"))
					or not sprite.get("frames") is Array
					or sprite["frames"].is_empty()
					or not effect.get("sequence") is Array
					or effect["sequence"].is_empty()
				):
					return false
				for frame: Variant in sprite["frames"]:
					if (
						not frame is Dictionary
						or not frame.get("texture") is String
						or not ResourceLoader.exists(directory.path_join(frame["texture"]))
						or not _integer(frame.get("offsetX"))
						or not _integer(frame.get("offsetY"))
						or not _positive_integer(frame.get("width"))
						or not _positive_integer(frame.get("height"))
						or not frame.get("empty") is bool
					):
						return false
				for index: Variant in effect["sequence"]:
					if not _integer(index) or index < 0 or index >= sprite["frames"].size():
						return false
			_:
				return false
	return true


func _action_presentations_valid(
	rules: Dictionary, clips: Dictionary, map_effects: Dictionary
) -> bool:
	var items: Dictionary = {}
	for item: Dictionary in rules["itemTemplates"]:
		items[int(item["id"])] = item
		if item.get("actionMode") == "map_attack" and not map_effects.has(item["mapEffect"]):
			return false
	for key: String in clips["appearances"]:
		var weapon: int = key.get_slice(":", 1).to_int()
		if not items.has(weapon):
			return false
		var item: Dictionary = items[weapon]
		if item["damageKind"] not in ["physical", "magic"]:
			continue
		var can_attack: bool = clips["appearances"][key]["canAttack"]
		if (
			(item["actionMode"] == "map_attack" and can_attack)
			or (item["actionMode"] == "battle_clip" and not can_attack)
		):
			return false
	return true


func _interface_valid(value: Variant, directory: String, unit_ids: Array, item_ids: Array) -> bool:
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
	for id: int in item_ids:
		var item: Variant = value["items"].get(str(id))
		if (
			not item is Dictionary
			or not item.get("name") is Dictionary
			or not item["name"].get("text") is String
			or item["name"]["text"].is_empty()
			or not item.get("description") is Dictionary
			or not item["description"].get("text") is String
			or (
				item.get("detailAttributes")
				not in [["durability"], ["attack", "hit", "critical", "range", "durability"]]
			)
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
		or not animation.get("completedUsesActiveCycle", false) is bool
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
		if item["damageKind"] in ["physical", "magic"]:
			if item.get("actionMode") not in ["battle_clip", "map_attack"]:
				return false
			if item["actionMode"] == "map_attack" and not MapAttacks.valid_definition(item):
				return false
		elif item.has("actionMode"):
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


func _read_json(path: String, documents: Dictionary = {}) -> Variant:
	# Reuse definitions within this open only; validation still follows the same path.
	if documents.has(path):
		return documents[path]
	return JsonDocument.read(path)


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
	story: Dictionary, directory: String, ids: Dictionary, width: int, height: int, records: Array
) -> bool:
	return StoryContract.validate(story, directory, ids, width, height, records)
