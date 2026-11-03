extends RefCounted

const Deployment = preload("res://app/chapter_deployment.gd")
const Summons = preload("res://gameplay/battle_summons.gd")


# The catalog is immutable source data. Each opening creates its own deployment aliases.
static func project(
	chapter: Dictionary,
	definition: Dictionary,
	library: Dictionary,
	records: Array,
	context: Dictionary
) -> Dictionary:
	if not chapter.get("library") is String or chapter.get("resourceDirectory") != "res://":
		return _failure("章内容库路径无效")
	for field: String in [
		"profiles", "stages", "scenes", "interface", "storyCommon", "texts", "mapEffects"
	]:
		if not library.get(field) is Dictionary:
			return _failure("章内容库缺少字段: " + field)
	for field: String in ["images", "speakers", "sequences"]:
		if library["storyCommon"].has(field) and not library["storyCommon"][field] is Dictionary:
			return _failure("公共剧情定义无效: " + field)
	if not definition.get("profiles") is Dictionary:
		return _failure("关卡缺少人物表现绑定")
	var stage_id: Variant = definition.get("stage")
	var scene_id: Variant = definition.get("scene")
	if (
		not stage_id is String
		or not scene_id is String
		or not library["stages"].get(stage_id) is Dictionary
		or not library["scenes"].get(scene_id) is Dictionary
	):
		return _failure("关卡舞台或场景引用无效")
	if not context.get("party", []) is Array:
		return _failure("关卡队伍来源无效")
	var bound: Dictionary = Deployment.bind(
		records,
		library["profiles"],
		definition["profiles"],
		context.get("party", []),
		context.get("bindings", {}),
		context.get("classes", {}),
		context.get("replacedIndices", []),
		context.get("_promotions", {}),
		context.get("initializationContext"),
		context.get("allowEmptySlots", false)
	)
	if not bound["ok"]:
		return bound
	var unit_order: Dictionary = _unit_order(bound["units"], context)
	if not unit_order["ok"]:
		return unit_order
	# Bind each current generation through its declared root recipe, even when
	# that root's original actor has already been recycled.
	var births: Array = context.get("cloneBindings", []).duplicate(true)
	births.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["generation"] < b["generation"]
	)
	for binding: Dictionary in births:
		var root: int = int(binding["templateDeploymentIndex"])
		var identity: int = int(binding["unitId"])
		var selected_class: int = -1
		for saved: Dictionary in context["units"]:
			if int(saved["id"]) == identity:
				selected_class = int(saved["classId"])
				break
		if selected_class < 0:
			return _failure("克隆绑定缺少单位")
		var family: Dictionary = Deployment.bind(
			[records[root]],
			library["profiles"],
			definition["profiles"],
			[],
			{},
			{0: selected_class}
		)
		if not family["ok"]:
			return family
		var unit: Dictionary = family["units"][0]
		var source_id: int = int(unit["id"])
		if unit["faction"] == 2 and source_id >= 80 and source_id <= 94:
			unit["bossInheritedStats"] = true
		unit["id"] = identity
		# A blueprint supplies static presentation; UnitRecord restores the saved
		# mutable fields. Hidden blueprints do not reserve an initial map cell.
		unit["visible"] = false
		for key: String in ["deploymentIndex", "deploymentSlot", "temporary"]:
			unit.erase(key)
		bound["units"].append(unit)
		bound["profiles"][identity] = family["profiles"][source_id]
		unit_order["ids"].append(identity)
	for binding: Dictionary in context.get("summonBindings", []):
		var family: Dictionary = Summons.blueprint(
			library.get("summons", {}), library["profiles"], binding
		)
		if not family["ok"]:
			return family
		var identity: int = int(binding["unitId"])
		bound["units"].append(family["unit"])
		bound["profiles"][identity] = family["profile"]
		unit_order["ids"].append(identity)
	# Anchors retain the interleaving of two bounded birth families without
	# granting saved array order authority over the native actor vector.
	var dynamic: Dictionary = {}
	var ordered_births: Array[Dictionary] = []
	for binding: Dictionary in births:
		dynamic[int(binding["unitId"])] = true
		ordered_births.append(
			{
				"unit": int(binding["unitId"]),
				"anchor": int(binding["generation"]),
				"kind": 0,
				"generation": 0
			}
		)
	for binding: Dictionary in context.get("summonBindings", []):
		dynamic[int(binding["unitId"])] = true
		ordered_births.append(
			{
				"unit": int(binding["unitId"]),
				"anchor": int(binding["afterCloneGeneration"]),
				"kind": 1,
				"generation": int(binding["generation"])
			}
		)
	ordered_births.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["anchor"] != b["anchor"]:
				return a["anchor"] < b["anchor"]
			if a["kind"] != b["kind"]:
				return a["kind"] < b["kind"]
			return a["generation"] < b["generation"]
	)
	var ordered: Array[int] = []
	for identity: int in unit_order["ids"]:
		if not dynamic.has(identity):
			ordered.append(identity)
	for birth: Dictionary in ordered_births:
		ordered.append(int(birth["unit"]))
	unit_order["ids"] = ordered
	var stage: Dictionary = library["stages"][stage_id].duplicate(true)
	stage["appearances"] = {}
	var art: Dictionary = library["scenes"][scene_id].duplicate(true)
	art["appearances"] = {}
	var animations: Dictionary = {"units": {}}
	var interface_data: Dictionary = library["interface"].duplicate(true)
	interface_data["portraitByUnitId"] = {}
	if not interface_data.get("textures") is Dictionary:
		return _failure("公共界面贴图定义无效")
	for unit: Dictionary in bound["units"]:
		var id: int = int(unit["id"])
		var profile: Dictionary = library["profiles"][bound["profiles"][id]]
		if (
			not profile.get("mapAnimation") is Dictionary
			or not profile.get("portrait") is Dictionary
			or not profile.get("appearances") is Dictionary
			or not profile.get("motion") is Dictionary
			or not profile["motion"].get(stage_id) is Dictionary
		):
			return _failure("人物表现不完整: " + str(id))
		animations["units"][str(id)] = profile["mapAnimation"].duplicate(true)
		var portrait: Dictionary = profile["portrait"].duplicate(true)
		if portrait.get("texture") != null:
			if not portrait["texture"] is Dictionary:
				return _failure("人物头像定义无效: " + str(id))
			var texture_id: String = "unit_portrait_%d" % id
			interface_data["textures"][texture_id] = portrait["texture"]
			portrait["texture"] = texture_id
		interface_data["portraitByUnitId"][str(id)] = portrait
		for weapon: Variant in profile["appearances"]:
			if (
				not weapon is String
				or not weapon.is_valid_int()
				or not profile["appearances"][weapon] is Dictionary
			):
				return _failure("人物武器表现引用无效: " + str(id))
			var alias: String = "%d:%s" % [id, weapon]
			if not profile["motion"][stage_id].get(weapon) is Dictionary:
				return _failure("人物缺少武器动作: " + alias)
			art["appearances"][alias] = profile["appearances"][weapon].duplicate(true)
			stage["appearances"][alias] = profile["motion"][stage_id][weapon].duplicate(true)
	var result: Dictionary = {
		"ok": true,
		"units": bound["units"],
		"unitOrder": unit_order["ids"],
		"spawns": bound["spawns"],
		"slots": bound["slots"],
		"profiles": bound["profiles"],
		"optionalIds": bound["optionalIds"],
		"referenceIds": bound.get("referenceIds", []),
		"mapAnimations": animations,
		"battleArt": art,
		"battleClips": stage,
		"interface": interface_data,
		"mapEffects": library["mapEffects"].duplicate(true),
		"storyCommon": library["storyCommon"].duplicate(true)
	}
	return result


static func _unit_order(units: Array, context: Dictionary) -> Dictionary:
	var party: Array = context.get("party", [])
	var native_order: Variant = context.get("partyOrder", [])
	if not native_order is Array or native_order.size() != party.size():
		return _failure("已有队伍遍历顺序无效")
	var expected: Dictionary = {}
	for member: Dictionary in party:
		expected[int(member["id"])] = true
	var seen: Dictionary = {}
	var deployed: Dictionary = {}
	for unit: Dictionary in units:
		deployed[int(unit["id"])] = true
	var result: Array[int] = []
	for id: Variant in native_order:
		if not _integer(id) or not expected.has(int(id)) or seen.has(int(id)):
			return _failure("已有队伍遍历顺序无效")
		seen[int(id)] = true
		if deployed.has(int(id)):
			result.append(int(id))
	for unit: Dictionary in units:
		if int(unit["id"]) not in result:
			result.append(int(unit["id"]))
	return {"ok": true, "ids": result}


static func merge_story(common: Dictionary, fragment: Dictionary) -> Dictionary:
	var result: Dictionary = common.duplicate(true)
	for key: Variant in fragment:
		if key in ["images", "speakers", "sequences"] and fragment[key] is Dictionary:
			var combined: Dictionary = result.get(key, {}).duplicate(true)
			combined.merge(fragment[key].duplicate(true), true)
			result[key] = combined
		else:
			result[key] = (
				fragment[key].duplicate(true)
				if fragment[key] is Array or fragment[key] is Dictionary
				else fragment[key]
			)
	return result


static func resolve_texts(value: Variant, texts: Dictionary, path: String = "story") -> Dictionary:
	if value is Dictionary:
		var source: Dictionary = value
		if value.has("sourceTextIndex") and not value.has("text"):
			var index: Variant = value["sourceTextIndex"]
			if not _integer(index) or index < 0:
				return _failure("剧情文本编号无效: " + path)
			var line: Variant = texts.get(str(int(index)))
			if not line is Dictionary or not line.get("text") is String or line["text"].is_empty():
				return _failure("缺少剧情文本: %s (%d)" % [path, int(index)])
			source = line.duplicate(true)
			source.merge(value, true)
		var result: Dictionary = {}
		for key: Variant in source:
			var resolved: Dictionary = resolve_texts(source[key], texts, path + "." + str(key))
			if not resolved["ok"]:
				return resolved
			result[key] = resolved["value"]
		return {"ok": true, "value": result}
	if value is Array:
		var result: Array = []
		for index: int in range(value.size()):
			var resolved: Dictionary = resolve_texts(value[index], texts, "%s[%d]" % [path, index])
			if not resolved["ok"]:
				return resolved
			result.append(resolved["value"])
		return {"ok": true, "value": result}
	return {"ok": true, "value": value}


static func resolve_story(
	story: Dictionary, units: Array, slots: Dictionary, context: Dictionary
) -> Dictionary:
	var result: Dictionary = story.duplicate(true)
	var world_step: int = int(context.get("worldStep", 0))
	result["battleNumber"] = world_step + 1
	if not result.get("turnEvents", []) is Array or not context.get("units", []) is Array:
		return _failure("剧情事件或单位上下文无效")
	if not result.get("battleName") is Dictionary or not result["battleName"].get("text") is String:
		return _failure("关卡名称定义无效")
	var actors: Dictionary = {}
	for unit: Dictionary in units:
		actors[int(unit["id"])] = unit
	for value: Variant in context.get("units", []):
		if (
			not value is Dictionary
			or not _integer(value.get("id"))
			or not _integer(value.get("x"))
			or not _integer(value.get("y"))
		):
			return _failure("剧情单位上下文无效")
		actors[int(value["id"])] = value
	var known_ids: Dictionary = {}
	for id: int in actors:
		known_ids[id] = true
	for id: int in context.get("referenceIds", []):
		known_ids[id] = true
	if not result.get("sequences") is Dictionary:
		return _failure("关卡剧情序列无效")
	for name: Variant in result["sequences"]:
		if not result["sequences"][name] is Array:
			return _failure("关卡剧情序列无效: " + str(name))
		var sequence: Array = []
		for value: Variant in result["sequences"][name]:
			if not value is Dictionary:
				return _failure("剧情步骤无效: " + str(name))
			if not _condition_valid(value):
				return _failure("剧情战序条件无效: " + str(name))
			if not _matches_step(value, world_step):
				continue
			var step: Dictionary = value.duplicate(true)
			step.erase("whenWorldStep")
			step.erase("unlessWorldStep")
			if step.get("kind") == "commanderSetup" and step.has("candidateSource"):
				if (
					step["candidateSource"] != "formalParty"
					or step.has("candidates")
					or step.has("defaultCommanderId")
					or not context.get("partyOrder") is Array
				):
					return _failure("指挥官队伍来源无效: " + str(name))
				var candidates: Array[int] = []
				var seen: Dictionary = {}
				for id: Variant in context["partyOrder"]:
					if not _integer(id) or seen.has(int(id)):
						return _failure("指挥官队伍顺序无效: " + str(name))
					seen[int(id)] = true
					var actor: Dictionary = actors.get(int(id), {})
					if (
						actor.get("formal") == true
						and actor.get("visible") == true
						and actor.get("faction") == 0
						and _integer(actor.get("sourceId"))
						and actor["sourceId"] >= 0
						and actor["sourceId"] < 10
					):
						candidates.append(int(id))
				if candidates.is_empty():
					return _failure("指挥官队伍没有可见正式成员: " + str(name))
				step["candidates"] = candidates
				step["defaultCommanderId"] = candidates[0]
				step.erase("candidateSource")
			if (
				step.get("kind") == "parallelEntrances"
				and (step.has("deploymentSlots") or step.has("unitIds"))
			):
				var selected: Dictionary = _select_units(step, slots)
				if not selected["ok"] or not _point(step.get("offset")):
					return _failure("入场部署槽位或偏移无效: " + str(name))
				if not step.get("units", []) is Array:
					return _failure("并行入场定义无效: " + str(name))
				var entrances: Array = step.get("units", []).duplicate(true)
				for id: int in selected["ids"]:
					if not actors.has(id):
						if not known_ids.has(id):
							return _failure("入场引用未知单位: " + str(id))
						continue
					var unit: Dictionary = actors[id]
					entrances.append(
						{
							"kind": "unitEntrance",
							"unitId": id,
							"from": [unit["x"] + step["offset"][0], unit["y"] + step["offset"][1]],
							"to": [unit["x"], unit["y"]]
						}
					)
				step["units"] = entrances
				step.erase("deploymentSlots")
				step.erase("unitIds")
				step.erase("offset")
				if entrances.is_empty():
					continue
			if step.get("kind") == "battleTitle" and step.get("text") is Dictionary:
				step["text"]["text"] = (
					"第%d战\n%s" % [world_step + 1, result.get("battleName", {}).get("text", "")]
				)
			sequence.append(step)
		result["sequences"][name] = sequence
	var events: Array = []
	for value: Variant in result.get("turnEvents", []):
		if not value is Dictionary:
			return _failure("回合事件无效")
		var event: Dictionary = value.duplicate(true)
		if event.has("deploymentSlots"):
			var selected: Dictionary = _select_units(event, slots)
			if not selected["ok"]:
				return selected
			event["unitIds"] = selected["ids"]
			event.erase("deploymentSlots")
		events.append(event)
	result["turnEvents"] = events
	var chosen: Array = []
	for step: Dictionary in result["sequences"].get("victory", []):
		if step.get("kind") == "routeChoice":
			if not step.get("options") is Array:
				return _failure("路线选择定义无效")
			chosen = step.get("options", []).duplicate(true)
			break
	if not chosen.is_empty():
		if result.get("encounter", false) == true:
			return _failure("遭遇战不能选择主线")
		result["routeChoices"] = chosen
	elif result.get("encounter", false) == true:
		var route_id: Variant = context.get("route")
		var world: Variant = result.get("world")
		var routes: Variant = world.get("routes") if world is Dictionary else null
		if (
			result.has("chapterEnd")
			or not _integer(route_id)
			or not routes is Array
			or route_id < 0
			or route_id >= routes.size()
			or not routes[int(route_id)] is Array
			or world_step < 6
			or world_step > routes[int(route_id)].size()
			or not _integer(routes[int(route_id)][world_step - 1])
		):
			return _failure("遭遇战路线无效")
		result["worldNode"] = int(routes[int(route_id)][world_step - 1])
		result["routeChoices"] = []
	elif result.has("chapterEnd"):
		var route_id: Variant = context.get("route")
		var routes: Variant = result.get("world", {}).get("routes")
		if (
			not _integer(route_id)
			or not routes is Array
			or route_id < 0
			or route_id >= routes.size()
			or not routes[int(route_id)] is Array
			or world_step != routes[int(route_id)].size() - 1
			or routes[int(route_id)][world_step] != result.get("worldNode")
		):
			return _failure("章终点路线无效")
		result["routeChoices"] = []
	elif context.has("route"):
		var route_id: Variant = context["route"]
		if not result.get("world") is Dictionary:
			return _failure("关卡世界定义无效")
		var routes: Variant = result.get("world", {}).get("routes")
		if (
			not _integer(route_id)
			or not routes is Array
			or route_id < 0
			or route_id >= routes.size()
			or not routes[int(route_id)] is Array
			or world_step + 1 >= routes[int(route_id)].size()
		):
			return _failure("关卡后续路线无效")
		if not _integer(routes[int(route_id)][world_step + 1]):
			return _failure("关卡后续地点编号无效")
		var next_node: int = int(routes[int(route_id)][world_step + 1])
		if (
			not result["world"].get("nodes") is Array
			or next_node < 0
			or next_node >= result["world"]["nodes"].size()
			or not result["world"]["nodes"][next_node] is Dictionary
			or not result["world"]["nodes"][next_node].get("name") is String
		):
			return _failure("关卡后续地点无效")
		var node: Dictionary = result["world"]["nodes"][next_node]
		var route: Dictionary = {
			"kind": "route", "routeIndex": int(route_id), "nodeId": next_node, "label": node["name"]
		}
		var recruit: Variant = context.get("recruitByNode", {}).get(str(next_node))
		if recruit != null:
			if not _integer(recruit) or recruit < 0 or recruit > 9:
				return _failure("后续地点人物引用无效")
			route["portraitId"] = int(recruit)
		result["routeChoices"] = [route]
	return {"ok": true, "story": result}


# Stored resources are absolute. Consumers use one project-relative coordinate system.
static func relative_resources(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = relative_resources(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(relative_resources(item))
		return result
	if value is String and value.begins_with("res://"):
		return value.trim_prefix("res://")
	return value


static func _select_units(selector: Dictionary, slots: Dictionary) -> Dictionary:
	if not selector.get("unitIds", []) is Array or not selector.get("deploymentSlots", []) is Array:
		return _failure("部署槽位选择无效")
	var result: Array[int] = []
	for id: Variant in selector.get("unitIds", []):
		if not _integer(id) or id < 0:
			return _failure("单位选择无效")
		if int(id) not in result:
			result.append(int(id))
	for slot: Variant in selector.get("deploymentSlots", []):
		if not _integer(slot) or slot < 0 or not slots.has(int(slot)):
			return _failure("部署槽位选择无效")
		if int(slots[int(slot)]) >= 0 and int(slots[int(slot)]) not in result:
			result.append(int(slots[int(slot)]))
	return {"ok": true, "ids": result}


static func _condition_valid(value: Dictionary) -> bool:
	for key: String in ["whenWorldStep", "unlessWorldStep"]:
		if value.has(key) and (not _integer(value[key]) or value[key] < 0):
			return false
	return true


static func _matches_step(value: Dictionary, world_step: int) -> bool:
	return (
		(not value.has("whenWorldStep") or value["whenWorldStep"] == world_step)
		and (not value.has("unlessWorldStep") or value["unlessWorldStep"] != world_step)
	)


static func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
	)


static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0]) and _integer(value[1])


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
