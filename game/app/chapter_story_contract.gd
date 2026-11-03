extends RefCounted

const MapView = preload("res://features/tactical_map/map_view.gd")
const Clones = preload("res://gameplay/battle_clones.gd")


static func validate(
	story: Dictionary,
	directory: String,
	ids: Dictionary,
	width: int,
	height: int,
	records: Array = []
) -> bool:
	if not Clones.definition(story.get("periodicClones"), records)["ok"]:
		return false
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
	for sequence: String in ["boot", "newGame", "opening", "victory", "defeat"]:
		if not story["sequences"].get(sequence) is Array or story["sequences"][sequence].is_empty():
			return false
	for sequence_name: Variant in story["sequences"]:
		var sequence: Variant = story["sequences"][sequence_name]
		if not sequence is Array:
			return false
		for step: Variant in sequence:
			var local_ending: bool = (
				story.get("chapterEnd") is Dictionary
				and sequence_name == story["chapterEnd"].get("sequence")
			)
			if (
				not step is Dictionary
				or not _story_step_valid(step, ids, width, height, local_ending)
			):
				return false
			if step["kind"] == "tutorial" and not tutorials.has(int(step["tutorialId"])):
				return false
	var commander_setups: int = 0
	for step: Dictionary in story["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			commander_setups += 1
	if story.get("commanderMode", "selection") not in ["selection", "none"]:
		return false
	if commander_setups != (0 if story.get("commanderMode") == "none" else 1):
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
		or not story.get("turnEvents") is Array
		or not story.get("aiChanges") is Array
	):
		return false
	var outcome: Dictionary = story["outcomeRules"]
	if not outcome.get("checks") is Array or outcome["checks"].is_empty():
		return false
	for check: Variant in outcome["checks"]:
		if not check is Dictionary or not _outcome_check_valid(check, ids, height):
			return false
	if not story.get("locationEvents", []) is Array:
		return false
	var location_ids: Dictionary = {}
	for event: Variant in story.get("locationEvents", []):
		if (
			not event is Dictionary
			or not event.get("locationId") is String
			or event["locationId"].is_empty()
			or location_ids.has(event["locationId"])
		):
			return false
		location_ids[event["locationId"]] = true
		if not event.get("unitIds") is Array or event["unitIds"].is_empty():
			return false
		var group_ids: Dictionary = {}
		for id: Variant in event["unitIds"]:
			if not _integer(id) or not ids.has(int(id)) or group_ids.has(int(id)):
				return false
			group_ids[int(id)] = true
		if not event.get("sequence", "") is String:
			return false
		if (
			not event.get("sequence", "").is_empty()
			and (
				not story["sequences"].get(event["sequence"]) is Array
				or story["sequences"][event["sequence"]].is_empty()
			)
		):
			return false
	var event_ids: Dictionary = {}
	for event: Variant in story["turnEvents"]:
		if (
			not event is Dictionary
			or not event.get("id") is String
			or event["id"].is_empty()
			or event_ids.has(event["id"])
			or not _positive_integer(event.get("afterEnemyPhaseOfRound"))
			or not event.get("sequence", "") is String
			or not event.get("unitIds") is Array
		):
			return false
		if event.has("withdrawUnitId"):
			if (
				not _integer(event["withdrawUnitId"])
				or not ids.has(int(event["withdrawUnitId"]))
				or not event["unitIds"].is_empty()
				or event.has("arrivalMode")
				or event.get("sequence", "").is_empty()
			):
				return false
		if not event.get("sequence", "").is_empty():
			if (
				not story["sequences"].get(event["sequence"]) is Array
				or story["sequences"][event["sequence"]].is_empty()
			):
				return false
		if (
			event.has("arrivalMode")
			and (not event["arrivalMode"] is String or event["arrivalMode"] != "nativeQueue")
		):
			return false
		if event.has("arrivalMode") and event["unitIds"].is_empty():
			return false
		event_ids[event["id"]] = true
		var queued_ids: Dictionary = {}
		for id: Variant in event.get("unitIds", []):
			if not _integer(id) or not ids.has(int(id)):
				return false
			if event.has("arrivalMode") and queued_ids.has(int(id)):
				return false
			queued_ids[int(id)] = true
	for change: Variant in story["aiChanges"]:
		if (
			not change is Dictionary
			or not _ai_timing_valid(change)
			or not change.get("unitIds") is Array
			or not _integer(change.get("flagsSet"))
			or change["flagsSet"] < 0
			or change["flagsSet"] > 255
			or not _integer(change.get("policyClear"))
			or change["policyClear"] < 0
			or change["policyClear"] > 255
		):
			return false
		for id: Variant in change["unitIds"]:
			if not _integer(id) or not ids.has(int(id)):
				return false
	if not story.get("combatEvents", []) is Array:
		return false
	var combat_event_ids: Dictionary = {}
	for event: Variant in story.get("combatEvents", []):
		if (
			not event is Dictionary
			or not event.get("id") is String
			or event["id"].is_empty()
			or combat_event_ids.has(event["id"])
			or event.get("trigger") not in ["firstCombat", "unitDeath"]
			or not _integer(event.get("unitId"))
			or not ids.has(int(event["unitId"]))
		):
			return false
		var sequence_keys: Array[String] = ["sequence"]
		if event["trigger"] == "unitDeath":
			if (
				event.has("sequence")
				or (
					not event.has("beforeRetirement")
					and not event.has("afterRetirement")
					and not event.has("revealUnitIds")
				)
			):
				return false
			sequence_keys = []
			for phase: String in ["beforeRetirement", "afterRetirement"]:
				if event.has(phase):
					sequence_keys.append(phase)
		elif (
			event.has("beforeRetirement")
			or event.has("afterRetirement")
			or event.has("revealUnitIds")
		):
			return false
		for key: String in sequence_keys:
			if (
				not event.get(key) is String
				or event[key].is_empty()
				or not story["sequences"].get(event[key]) is Array
				or story["sequences"][event[key]].is_empty()
			):
				return false
		if event.has("revealUnitIds"):
			if not event["revealUnitIds"] is Array or event["revealUnitIds"].is_empty():
				return false
			var declared: Array[int] = []
			for id: Variant in event["revealUnitIds"]:
				if (
					not _integer(id)
					or not ids.has(int(id))
					or int(id) in declared
					or int(id) == int(event["unitId"])
				):
					return false
				declared.append(int(id))
		combat_event_ids[event["id"]] = true
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
	var terminal: bool = story.has("chapterEnd")
	if story.has("encounter") and not story["encounter"] is bool:
		return false
	var encounter: bool = story.get("encounter", false)
	if terminal and encounter:
		return false
	if terminal:
		var ending: Variant = story["chapterEnd"]
		if (
			not ending is Dictionary
			or ending.size() not in [2, 3]
			or not ending.get("id") is String
			or ending["id"].is_empty()
			or not ending.get("sequence") is String
			or not story["sequences"].get(ending["sequence"]) is Array
			or story["sequences"][ending["sequence"]].is_empty()
		):
			return false
		if ending.size() == 3 and not ending.has("itemReward"):
			return false
		if ending.has("itemReward"):
			var reward: Variant = ending["itemReward"]
			if (
				not reward is Dictionary
				or reward.size() != 2
				or not _integer(reward.get("unitId"))
				or not ids.has(int(reward["unitId"]))
				or ids[int(reward["unitId"])].get("formal") != true
				or ids[int(reward["unitId"])].get("faction") != 0
				or not _positive_integer(reward.get("templateId"))
			):
				return false
	if (
		not story.get("routeChoices") is Array
		or (not terminal and not encounter and story["routeChoices"].is_empty())
	):
		return false
	if (terminal or encounter) and not story["routeChoices"].is_empty():
		return false
	var routes: Dictionary = {}
	var interactive_routes: bool = false
	for step: Dictionary in story["sequences"]["victory"]:
		if step.get("kind") == "routeChoice":
			if terminal or encounter:
				return false
			interactive_routes = true
	for route: Variant in story["routeChoices"]:
		if (
			not route is Dictionary
			or not _integer(route.get("routeIndex"))
			or routes.has(int(route["routeIndex"]))
			or not route.get("label") is String
		):
			return false
		if interactive_routes or route.has("portraitId"):
			if (
				not _integer(route.get("portraitId"))
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
			if step["kind"] in ["chapterParty", "chapterSummary", "chapterRating"]:
				if not terminal or sequence != story["chapterEnd"]["sequence"]:
					return false
			if terminal and step["kind"] == "routeChoice":
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
			if step["kind"] == "prologue":
				if not step.has("image"):
					if not terminal or sequence != story["chapterEnd"]["sequence"]:
						return false
				elif not step["image"] is String or not story["images"].has(step["image"]):
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
		or not _integer(world.get("tileSize"))
		or world["tileSize"] != MapView.TILE_PIXELS
		or not world.get("nodes") is Array
		or world["nodes"].is_empty()
		or not world.get("routes") is Array
		or world["routes"].is_empty()
		or not _integer(story.get("worldNode"))
		or story["worldNode"] < 0
		or story["worldNode"] >= world["nodes"].size()
		or not _positive_integer(story.get("battleNumber"))
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
			or not node.get("entryNarration") is Dictionary
			or not _story_text_valid(node["entryNarration"])
			or not _integer(node.get("markerId"))
			or int(node["markerId"]) not in [-1, 0, 1]
			or not _story_cell_valid(
				node.get("position"), int(world["width"]), int(world["height"])
			)
		):
			return false
	for path: Variant in world["routes"]:
		if not path is Array or path.size() < 2 or path[0] != 0:
			return false
		for node: Variant in path:
			if not _integer(node) or node < 0 or node >= world["nodes"].size():
				return false
	if terminal:
		var terminal_path: bool = false
		for path: Array in world["routes"]:
			var current: int = path.find(story["worldNode"])
			if current >= 0:
				if current != path.size() - 1:
					return false
				terminal_path = true
		if not terminal_path:
			return false
	for sequence: Array in story["sequences"].values():
		for step: Dictionary in sequence:
			if step["kind"] == "worldMarker" and step["nodeId"] >= world["nodes"].size():
				return false
	for route: Dictionary in story["routeChoices"]:
		if (
			not _integer(route.get("nodeId"))
			or route["nodeId"] <= 0
			or route["nodeId"] >= world["nodes"].size()
			or route["routeIndex"] < 0
			or route["routeIndex"] >= world["routes"].size()
		):
			return false
		var path: Array = world["routes"][int(route["routeIndex"])]
		var current: int = path.find(story["worldNode"])
		if current < 0 or current + 1 >= path.size() or path[current + 1] != route["nodeId"]:
			return false
	return true


static func validate_locations(map: Dictionary, rules: Dictionary, story: Dictionary) -> bool:
	if (
		not map.get("locations", []) is Array
		or not map.get("tileVariants", {}) is Dictionary
		or not map.get("movementCosts") is Dictionary
	):
		return false
	var templates: Dictionary = {}
	for item: Dictionary in rules["itemTemplates"]:
		templates[int(item["id"])] = true
	if story.get("chapterEnd") is Dictionary and story["chapterEnd"].has("itemReward"):
		var reward: Variant = story["chapterEnd"]["itemReward"]
		if not reward is Dictionary or not _positive_integer(reward.get("templateId")):
			return false
		if not templates.has(int(reward["templateId"])):
			return false
	var variants: Dictionary = map.get("tileVariants", {})
	for key: Variant in variants:
		var value: Variant = variants[key]
		if not key is String or key.is_empty() or not value is Dictionary:
			return false
		if not _integer(value.get("tileId")) or value["tileId"] < 0 or value["tileId"] > 99:
			return false
		if not _integer(value.get("terrain")) or value["terrain"] < 0 or value["terrain"] > 10:
			return false
		if (
			not value.get("texture") is String
			or not ResourceLoader.exists(value["texture"], "Texture2D")
		):
			return false
		var texture: Texture2D = load(value["texture"])
		if texture.get_size() != Vector2(24, 24) or not value.get("movementCosts") is Dictionary:
			return false
		if value["movementCosts"].size() != 11:
			return false
		for group: int in range(11):
			var cost: Variant = value["movementCosts"].get(str(group))
			if (
				not _integer(cost)
				or cost < 1
				or cost > 10000
				or not map["movementCosts"].has(str(group))
			):
				return false
	var ids: Dictionary = {}
	var positions: Dictionary = {}
	for value: Variant in map.get("locations", []):
		if not value is Dictionary or not value.get("id") is String or value["id"].is_empty():
			return false
		if (
			ids.has(value["id"])
			or value.get("kind") not in ["chest", "visit", "waitPickup"]
			or not _integer(value.get("sourceIndex"))
			or value["sourceIndex"] < 0
		):
			return false
		var position: Variant = value.get("position")
		if (
			not position is Array
			or position.size() != 2
			or not _integer(position[0])
			or not _integer(position[1])
			or position[0] < 0
			or position[1] < 0
			or position[0] >= map["width"]
			or position[1] >= map["height"]
		):
			return false
		var cell := Vector2i(int(position[0]), int(position[1]))
		if (
			cell.x < 0
			or cell.y < 0
			or cell.x >= map["width"]
			or cell.y >= map["height"]
			or positions.has(cell)
		):
			return false
		if not _integer(value.get("tileId")) or value["tileId"] != map["tiles"][cell.y][cell.x]:
			return false
		if value["kind"] == "waitPickup":
			if (
				value.size() != 6
				or value["sourceIndex"] != ids.size()
				or (map["terrain"][cell.y][cell.x] != 3 and map["terrain"][cell.y][cell.x] != 4)
				or not value.get("reward") is Dictionary
				or value["reward"].get("kind") not in ["item", "weightedItem"]
				or not _visit_reward_valid(value["reward"], templates)
			):
				return false
		elif value["kind"] == "visit":
			if (
				value["sourceIndex"] != ids.size()
				or map["terrain"][cell.y][cell.x] != 6
				or value.has("openedVariant")
				or value.has("weightedChoices")
				or not _visit_reward_valid(value.get("reward"), templates)
			):
				return false
		else:
			if (
				map["terrain"][cell.y][cell.x] != 7
				or not value.get("openedVariant") is String
				or not variants.has(value["openedVariant"])
				or value.has("reward") == value.has("weightedChoices")
			):
				return false
			if value.has("reward"):
				if (
					not value["reward"] is Dictionary
					or value.has("emptyWeight")
					or value["reward"].get("kind") not in ["item", "goldRange"]
					or not _visit_reward_valid(value["reward"], templates)
				):
					return false
				ids[value["id"]] = true
				positions[cell] = true
				continue
			if not value["weightedChoices"] is Array or value["weightedChoices"].is_empty():
				return false
			var total: int = 0
			for choice: Variant in value["weightedChoices"]:
				if (
					not choice is Dictionary
					or not _integer(choice.get("templateId"))
					or not templates.has(int(choice["templateId"]))
					or not _positive_integer(choice.get("weight"))
					or choice["weight"] > 2147483647
				):
					return false
				total += int(choice["weight"])
				if total > 2147483647:
					return false
			if (
				value.has("emptyWeight")
				and (
					not _positive_integer(value["emptyWeight"])
					or value["emptyWeight"] >= 100
					or total + int(value["emptyWeight"]) != 100
				)
			):
				return false
		ids[value["id"]] = true
		positions[cell] = true
	if not story.get("locationEvents", []) is Array:
		return false
	var events: Dictionary = {}
	for event: Variant in story.get("locationEvents", []):
		if (
			not event is Dictionary
			or not event.get("locationId") is String
			or not ids.has(event["locationId"])
			or events.has(event["locationId"])
		):
			return false
		events[event["locationId"]] = true
	return true


static func _visit_reward_valid(value: Variant, templates: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	match value.get("kind"):
		"item":
			return (
				value.size() == 2
				and _positive_integer(value.get("templateId"))
				and templates.has(int(value["templateId"]))
			)
		"gold":
			return (
				value.size() == 2
				and _positive_integer(value.get("amount"))
				and value["amount"] <= 9999999
			)
		"goldRange":
			return (
				value.size() == 3
				and _positive_integer(value.get("minimum"))
				and _positive_integer(value.get("maximum"))
				and value["minimum"] <= value["maximum"]
				and value["maximum"] <= 9999999
			)
		"weightedItem":
			if (
				value.size() != 2
				or not value.get("weightedChoices") is Array
				or value["weightedChoices"].is_empty()
			):
				return false
			var total: int = 0
			for choice: Variant in value["weightedChoices"]:
				if (
					not choice is Dictionary
					or choice.size() != 2
					or not _positive_integer(choice.get("templateId"))
					or not templates.has(int(choice["templateId"]))
					or not _positive_integer(choice.get("weight"))
					or choice["weight"] > 100
				):
					return false
				total += int(choice["weight"])
				if total > 100:
					return false
			return true
	return false


static func _ai_timing_valid(change: Dictionary) -> bool:
	if change.has("beforeAutomaticPhase"):
		var timing: Variant = change["beforeAutomaticPhase"]
		return (
			not change.has("beforeEnemyPhaseOfRound")
			and timing is Dictionary
			and timing.size() == 2
			and _positive_integer(timing.get("round"))
			and _integer(timing.get("faction"))
			and int(timing["faction"]) in [1, 2]
		)
	return _positive_integer(change.get("beforeEnemyPhaseOfRound"))


static func _outcome_check_valid(check: Dictionary, ids: Dictionary, height: int) -> bool:
	if check.has("reason") and (not check["reason"] is String or check["reason"].is_empty()):
		return false
	if check.get("condition") == "requiredUnitFallen":
		if (
			check.get("kind") != "defeat"
			or not check.get("unitIds") is Array
			or check["unitIds"].is_empty()
		):
			return false
		for id: Variant in check["unitIds"]:
			if not _integer(id) or not ids.has(int(id)):
				return false
		return true
	if (
		check.get("kind") != "victory"
		and not (
			check.get("kind") == "defeat"
			and check.get("condition") in ["allUnitsRetired", "noVisibleFaction"]
		)
	):
		return false
	match check.get("condition"):
		"unitRetired":
			return _integer(check.get("unitId")) and ids.has(int(check["unitId"]))
		"allUnitsRetired":
			if not check.get("unitIds") is Array or check["unitIds"].is_empty():
				return false
			var selected: Dictionary = {}
			for id: Variant in check["unitIds"]:
				if not _integer(id) or not ids.has(int(id)) or selected.has(int(id)):
					return false
				selected[int(id)] = true
			return true
		"allEnemiesDefeated", "noVisibleEnemies", "noVisibleFaction":
			return (
				_integer(check.get("faction")) and check["faction"] >= 0 and check["faction"] <= 2
			)
		"escaped":
			return (
				_integer(check.get("unitId"))
				and ids.has(int(check["unitId"]))
				and _integer(check.get("row"))
				and check["row"] >= 0
				and check["row"] < height
			)
		"roundAfter":
			return _positive_integer(check.get("round"))
	return false


static func _story_step_valid(
	step: Dictionary, ids: Dictionary, width: int, height: int, local_ending: bool = false
) -> bool:
	for timing: String in [
		"sourceWaitTicks", "sourceWaitTicksAfter", "sourceHoldTicksAfter", "holdTicksAfter"
	]:
		if step.has(timing) and (not _integer(step[timing]) or step[timing] < 0):
			return false
	if step.has("instant") and not step["instant"] is bool:
		return false
	if step.has("sourceMaxFocusPixels"):
		if step.get("kind") != "focus" or not _positive_integer(step["sourceMaxFocusPixels"]):
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
			"gameOver",
			"battleTitle"
		]
	):
		return (
			step.get("text") is Dictionary
			and _story_text_valid(step["text"], local_ending and step["kind"] == "instruction")
			and (
				step.get("kind") != "missionComplete"
				or (_integer(step.get("goldReward")) and step["goldReward"] >= 0)
			)
			and (
				step["kind"] != "battleTitle" or _positive_integer(step.get("sourceDurationUnits"))
			)
		)
	match step.get("kind"):
		"chapterParty", "chapterSummary", "chapterRating":
			return step.size() == 1
		"focus":
			return (
				_integer(step.get("unitId")) and ids.has(int(step["unitId"]))
				if step.has("unitId")
				else _story_cell_valid(step.get("cell"), width, height)
			)
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
		"revealUnits":
			if step.size() != 2 or not step.get("unitIds") is Array or step["unitIds"].is_empty():
				return false
			var revealed: Dictionary = {}
			for id: Variant in step["unitIds"]:
				if not _integer(id) or revealed.has(int(id)) or not ids.has(int(id)):
					return false
				revealed[int(id)] = true
			return true
		"revealFaction":
			return _integer(step.get("faction")) and step["faction"] >= 0 and step["faction"] <= 2
		"commanderSetup":
			if (
				step.has("candidateSource")
				or not step.get("candidates") is Array
				or step["candidates"].is_empty()
				or not _integer(step.get("defaultCommanderId"))
			):
				return false
			var candidates: Dictionary = {}
			for id: Variant in step["candidates"]:
				if not _integer(id) or candidates.has(int(id)) or not ids.has(int(id)):
					return false
				var candidate: Dictionary = ids[int(id)]
				if candidate.get("formal") != true or candidate.get("faction") != 0:
					return false
				candidates[int(id)] = true
			return candidates.has(int(step["defaultCommanderId"]))
		"tutorial":
			return _integer(step.get("tutorialId")) and step["tutorialId"] >= 0
		"worldMarker":
			return _integer(step.get("nodeId")) and step["nodeId"] >= 0
		"enterBattle":
			return step.get("battleId") is String and not step["battleId"].is_empty()
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


static func _story_cell_valid(
	cell: Variant, width: int, height: int, offscreen: bool = false
) -> bool:
	return (
		cell is Array
		and cell.size() == 2
		and _integer(cell[0])
		and _integer(cell[1])
		and (offscreen or (cell[0] >= 0 and cell[0] < width and cell[1] >= 0 and cell[1] < height))
	)


static func _story_text_valid(line: Dictionary, allow_local: bool = false) -> bool:
	return (
		line.get("text") is String
		and not line["text"].is_empty()
		and (
			_integer(line.get("sourceTextIndex"))
			or (allow_local and not line.has("sourceTextIndex"))
		)
		and (line.get("speakerId") == null or _integer(line["speakerId"]))
	)


static func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
	)


static func _positive_integer(value: Variant) -> bool:
	return _integer(value) and value > 0
