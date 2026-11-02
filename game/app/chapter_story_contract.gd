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
	for sequence: Variant in story["sequences"].values():
		if not sequence is Array:
			return false
		for step: Variant in sequence:
			if not step is Dictionary or not _story_step_valid(step, ids, width, height):
				return false
			if step["kind"] == "tutorial" and not tutorials.has(int(step["tutorialId"])):
				return false
	var commander_setups: int = 0
	for step: Dictionary in story["sequences"]["opening"]:
		if step["kind"] == "commanderSetup":
			commander_setups += 1
	if commander_setups != 1:
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
		if not event.get("sequence", "").is_empty():
			if (
				not story["sequences"].get(event["sequence"]) is Array
				or story["sequences"][event["sequence"]].is_empty()
			):
				return false
		event_ids[event["id"]] = true
		for id: Variant in event["unitIds"]:
			if not _integer(id) or not ids.has(int(id)):
				return false
	for change: Variant in story["aiChanges"]:
		if (
			not change is Dictionary
			or not _positive_integer(change.get("beforeEnemyPhaseOfRound"))
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
				or (not event.has("beforeRetirement") and not event.has("afterRetirement"))
			):
				return false
			sequence_keys = []
			for phase: String in ["beforeRetirement", "afterRetirement"]:
				if event.has(phase):
					sequence_keys.append(phase)
		elif event.has("beforeRetirement") or event.has("afterRetirement"):
			return false
		for key: String in sequence_keys:
			if (
				not event.get(key) is String
				or event[key].is_empty()
				or not story["sequences"].get(event[key]) is Array
				or story["sequences"][event[key]].is_empty()
			):
				return false
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
	if not story.get("routeChoices") is Array or story["routeChoices"].is_empty():
		return false
	var routes: Dictionary = {}
	var interactive_routes: bool = false
	for step: Dictionary in story["sequences"]["victory"]:
		if step.get("kind") == "routeChoice":
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
	if check.get("kind") != "victory":
		return false
	match check.get("condition"):
		"unitRetired":
			return _integer(check.get("unitId")) and ids.has(int(check["unitId"]))
		"allEnemiesDefeated", "noVisibleEnemies":
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


static func _story_step_valid(step: Dictionary, ids: Dictionary, width: int, height: int) -> bool:
	for timing: String in [
		"sourceWaitTicks", "sourceWaitTicksAfter", "sourceHoldTicksAfter", "holdTicksAfter"
	]:
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
			"gameOver",
			"battleTitle"
		]
	):
		return (
			step.get("text") is Dictionary
			and _story_text_valid(step["text"])
			and (
				step.get("kind") != "missionComplete"
				or (_integer(step.get("goldReward")) and step["goldReward"] >= 0)
			)
			and (
				step["kind"] != "battleTitle" or _positive_integer(step.get("sourceDurationUnits"))
			)
		)
	match step.get("kind"):
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
				not step.get("candidates") is Array
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


static func _story_text_valid(line: Dictionary) -> bool:
	return (
		line.get("text") is String
		and not line["text"].is_empty()
		and _integer(line.get("sourceTextIndex"))
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
