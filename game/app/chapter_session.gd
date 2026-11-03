extends RefCounted

const Promotions = preload("res://app/chapter_promotions.gd")
const Content = preload("res://app/chapter_content.gd")
const Deployment = preload("res://app/chapter_deployment.gd")
const Clones = preload("res://gameplay/battle_clones.gd")
const Summons = preload("res://gameplay/battle_summons.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const DeploymentContext = preload("res://gameplay/deployment_context.gd")
const JsonDocument = preload("res://app/json_document.gd")


# The only entry that combines source validation, content binding and a live battle.
func open(
	chapter_path: String,
	battle_id: String = "",
	source: Dictionary = {"new": true},
	random_source: Callable = Callable(),
	initialization_context: Variant = null
) -> Dictionary:
	if source.size() != 1 or source.keys()[0] not in ["new", "progress", "encounter", "snapshot"]:
		return _failure("INVALID_CHAPTER_SOURCE")
	if not source.has("snapshot") and not DeploymentContext.is_valid(initialization_context):
		return _failure("INVALID_DEPLOYMENT_CONTEXT")
	if source.has("progress") and source["progress"] is Dictionary:
		var completed_flag: Variant = source["progress"].get("chapterCompleted", false)
		if completed_flag is bool and completed_flag:
			var completed: Dictionary = completed_content(chapter_path, source["progress"])
			return _failure("CHAPTER_ALREADY_COMPLETED") if completed["ok"] else completed
	var resolved: Dictionary = _resolve(
		chapter_path, battle_id, source, null if source.has("snapshot") else initialization_context
	)
	if not resolved["ok"]:
		return resolved
	var content: Dictionary = resolved["content"]
	var restored: bool = source.has("snapshot")
	var battle: RefCounted = Battle.new(
		content, random_source, not restored, null if restored else initialization_context
	)
	if restored:
		var result: Dictionary = battle.restore_snapshot(source["snapshot"])
		if not result["ok"]:
			return result
	else:
		var snapshot: Dictionary = battle.snapshot()
		var projected: Dictionary = Content.new().reproject(
			content,
			snapshot["units"],
			snapshot.get("cloneState", {}),
			snapshot.get("summonState", {})
		)
		if not projected["ok"]:
			return projected
		content = projected
		battle.adopt_content(content)
		if source.has("progress") or source.has("encounter"):
			var entered: Dictionary = battle.begin_from_progress(
				source["encounter" if source.has("encounter") else "progress"]
			)
			if not entered["ok"]:
				return entered
	return {"ok": true, "content": content, "battle": battle}


# Completed world records describe the map just finished, one step before the next entry.
func completed_content(chapter_path: String, progress: Dictionary) -> Dictionary:
	return _resolve(chapter_path, str(progress.get("completedBattle", "")), {"completed": progress})


func _resolve(
	chapter_path: String,
	battle_id: String,
	source: Dictionary,
	initialization_context: Variant = null
) -> Dictionary:
	if (
		source.size() != 1
		or source.keys()[0] not in ["new", "progress", "encounter", "snapshot", "completed"]
	):
		return _failure("INVALID_CHAPTER_SOURCE")
	var chapter: Variant = _json(chapter_path)
	if (
		not chapter is Dictionary
		or not chapter.get("id") is String
		or not chapter.get("firstBattle") is String
		or not chapter.get("battles") is Dictionary
		or not chapter.get("library") is String
		or not chapter.get("initialParty") is Array
		or not chapter.get("recruitByNode") is Dictionary
	):
		return _failure("INVALID_CHAPTER_ENTRY")
	if battle_id.is_empty():
		battle_id = chapter["firstBattle"]
	if not chapter["battles"].get(battle_id) is String:
		return _failure("BATTLE_NOT_AVAILABLE")
	var definition: Variant = _json(chapter["battles"][battle_id])
	var library: Variant = _json(chapter["library"])
	if (
		not definition is Dictionary
		or definition.get("battleId") != battle_id
		or not definition.get("deployments") is String
		or not library is Dictionary
		or not library.get("storyCommon") is Dictionary
		or not library["storyCommon"].get("world") is Dictionary
		or not library["storyCommon"]["world"].get("routes") is Array
	):
		return _failure("INVALID_BATTLE_DEFINITION")
	var records: Variant = _json(definition["deployments"])
	var story: Variant = _json(definition.get("story", ""))
	if not records is Array or not story is Dictionary:
		return _failure("INVALID_DEPLOYMENTS")
	if (
		not source.has("snapshot")
		and (source.has("encounter") != (story.get("encounter", false) == true))
	):
		return _failure("INVALID_CHAPTER_SOURCE")
	var clones: Dictionary = Clones.definition(story.get("periodicClones"), records)
	if not clones["ok"]:
		return clones
	var promotion_rules: Variant = _json(chapter.get("rules", ""))
	if not promotion_rules is Dictionary or not library.get("profiles") is Dictionary:
		return _failure("INVALID_PROMOTION_RULES")
	var promotions: Dictionary = Promotions.context(promotion_rules, library["profiles"])
	if not promotions["ok"]:
		return promotions
	var context: Dictionary
	if source.has("new"):
		if not source["new"] is bool or not source["new"] or battle_id != chapter["firstBattle"]:
			return _failure("INVALID_NEW_GAME_ENTRY")
		context = {"ok": true, "party": [], "worldStep": 0, "route": -1}
	elif source.has("snapshot"):
		context = _snapshot_context(
			chapter,
			library,
			battle_id,
			records,
			source["snapshot"],
			story.get("periodicClones"),
			promotions,
			story.get("encounter", false) == true
		)
	else:
		var completed: bool = source.has("completed")
		var encounter: bool = source.has("encounter")
		context = _world_context(
			chapter,
			library,
			battle_id,
			records,
			story,
			source["completed" if completed else ("encounter" if encounter else "progress")],
			completed,
			encounter
		)
	if not context["ok"]:
		return context
	var ordering: Dictionary = _party_order(chapter, library, context["party"])
	if not ordering["ok"]:
		return ordering
	context["partyOrder"] = ordering["ids"]
	if initialization_context != null:
		context["initializationContext"] = initialization_context.duplicate(true)
	var documents: Dictionary = {
		chapter_path: chapter,
		chapter["battles"][battle_id]: definition,
		chapter["library"]: library,
		definition["deployments"]: records,
		definition["story"]: story
	}
	# New battles are rebound after deployment; validate promotion targets on that final roster.
	var prepare_promotions: bool = source.has("snapshot") or source.has("completed")
	var loaded: Dictionary = Content.new().load_chapter(
		chapter_path, battle_id, context, documents, prepare_promotions
	)
	if not loaded["ok"]:
		return loaded
	loaded["inheritedParty"] = context["party"].duplicate(true)
	return {"ok": true, "content": loaded}


# Existing objects stay at the front of the native battle vector. Deployment
# slots use recruit order, while this order starts with the first map's records.
func _party_order(chapter: Dictionary, library: Dictionary, party: Array) -> Dictionary:
	var result: Array[int] = []
	if party.is_empty():
		return {"ok": true, "ids": result}
	var first: Variant = _json(chapter["battles"][chapter["firstBattle"]])
	if not first is Dictionary or not first.get("deployments") is String:
		return _failure("INVALID_FIRST_BATTLE_DEPLOYMENTS")
	var records: Variant = _json(first["deployments"])
	if not records is Array or not first.get("profiles") is Dictionary:
		return _failure("INVALID_FIRST_BATTLE_DEPLOYMENTS")
	var bound: Dictionary = Deployment.bind(records, library["profiles"], first["profiles"], [])
	if not bound["ok"]:
		return bound
	var remaining: Dictionary = {}
	for actor: Dictionary in party:
		remaining[int(actor["id"])] = true
	for actor: Dictionary in bound["units"]:
		var id: int = int(actor["id"])
		if actor["formal"] and remaining.has(id):
			result.append(id)
			remaining.erase(id)
	for actor: Dictionary in party:
		var id: int = int(actor["id"])
		if remaining.has(id):
			result.append(id)
			remaining.erase(id)
	return {"ok": true, "ids": result}


func _world_context(
	chapter: Dictionary,
	library: Dictionary,
	battle_id: String,
	records: Array,
	story: Dictionary,
	value: Variant,
	completed: bool,
	encounter: bool = false
) -> Dictionary:
	if (
		not value is Dictionary
		or value.get("chapterId") != chapter["id"]
		or not value.get("party") is Array
		or not _integer(value.get("route"))
		or not _integer(
			value.get(
				"worldStep", 1 if value.get("completedBattle") == chapter["firstBattle"] else null
			)
		)
	):
		return _failure("INVALID_CAMPAIGN_ENTRY")
	var route_index: int = int(value["route"])
	var routes: Array = library["storyCommon"]["world"]["routes"]
	if route_index < 0 or route_index >= routes.size() or not routes[route_index] is Array:
		return _failure("INVALID_CAMPAIGN_ROUTE")
	var route: Array = routes[route_index]
	var next_step: int = int(value.get("worldStep", 1))
	if next_step < 1:
		return _failure("INVALID_CAMPAIGN_WORLD_STEP")
	if value.has("chapterCompleted") and not value["chapterCompleted"] is bool:
		return _failure("INVALID_CAMPAIGN_WORLD_STEP")
	var chapter_completed: bool = value.get("chapterCompleted", false)
	if chapter_completed:
		if (
			(not completed and not encounter)
			or next_step != route.size()
			or (not encounter and not story.get("chapterEnd") is Dictionary)
			or (not encounter and story["chapterEnd"].get("id") != chapter["id"])
		):
			return _failure("INVALID_CAMPAIGN_WORLD_STEP")
	elif next_step < 1 or next_step >= route.size():
		return _failure("INVALID_CAMPAIGN_WORLD_STEP")
	if (
		value.get("worldNode") != route[next_step - 1]
		or value.get("completedBattle") != "m%d" % int(route[next_step - 1])
		or (
			not encounter
			and battle_id != "m%d" % int(route[next_step - 1 if completed else next_step])
		)
	):
		return _failure("INVALID_CAMPAIGN_LOCATION")
	if encounter:
		var location: Variant = value.get("worldLocation", value["worldNode"])
		if (
			next_step < 6
			or not _integer(location)
			or not route.slice(0, next_step).any(
				func(node: Variant) -> bool: return node == location
			)
		):
			return _failure("INVALID_CAMPAIGN_LOCATION")
	var step: int = next_step - 1 if completed else next_step
	var expected: Array[int] = Deployment.recruit_order(
		route, chapter["recruitByNode"], next_step, chapter["initialParty"]
	)
	var ordered: Dictionary = _ordered_party(value["party"], expected, true)
	if not ordered["ok"]:
		return ordered
	var inherited_order: Array[int] = []
	if step > 0:
		inherited_order = Deployment.recruit_order(
			route, chapter["recruitByNode"], step, chapter["initialParty"]
		)
	var inherited: Dictionary = _ordered_party(value["party"], inherited_order, false)
	if not inherited["ok"]:
		return inherited
	var classes: Dictionary = {}
	if completed:
		var by_id: Dictionary = {}
		for actor: Dictionary in ordered["party"]:
			by_id[int(actor["id"])] = actor
		for index: int in range(records.size()):
			var raw: Variant = records[index]
			if not raw is Dictionary:
				return _failure("INVALID_DEPLOYMENTS")
			if raw.get("faction") == 0 and not raw.has("deploymentSlot"):
				var id: int = int(raw.get("id", raw.get("sourceId", -1)))
				if by_id.has(id):
					classes[index] = int(by_id[id]["classId"])
	return {
		"ok": true,
		"party": inherited["party"],
		"worldStep": step,
		"route": route_index,
		"classes": classes
	}


func _snapshot_context(
	chapter: Dictionary,
	library: Dictionary,
	battle_id: String,
	records: Array,
	value: Variant,
	clone_policy: Variant,
	promotions: Dictionary,
	allow_empty_slots: bool = false
) -> Dictionary:
	if not value is Dictionary or not value.get("units") is Array:
		return _failure("INVALID_SAVE_STATE")
	var party: Array = []
	var step: int = 0
	var route_index: int = -1
	var campaign: Variant = value.get("campaign", {})
	if battle_id == chapter["firstBattle"]:
		if not campaign is Dictionary or not campaign.is_empty():
			return _failure("INVALID_SAVE_CAMPAIGN")
	else:
		if (
			not campaign is Dictionary
			or not _integer(campaign.get("route"))
			or not _integer(campaign.get("worldStep"))
		):
			return _failure("INVALID_SAVE_CAMPAIGN")
		route_index = int(campaign["route"])
		step = int(campaign["worldStep"])
		var routes: Array = library["storyCommon"]["world"]["routes"]
		if route_index < 0 or route_index >= routes.size() or not routes[route_index] is Array:
			return _failure("INVALID_SAVE_CAMPAIGN")
		var route: Array = routes[route_index]
		if (
			(allow_empty_slots and (step < 6 or step > route.size()))
			or (not allow_empty_slots and (step < 1 or step >= route.size()))
		):
			return _failure("INVALID_SAVE_CAMPAIGN")
		if not allow_empty_slots and battle_id != "m%d" % int(route[step]):
			return _failure("INVALID_SAVE_CAMPAIGN")
		var expected: Array[int] = Deployment.recruit_order(
			route, chapter["recruitByNode"], step, chapter["initialParty"]
		)
		var inherited: Dictionary = _ordered_party(value["units"], expected, false)
		if not inherited["ok"]:
			return inherited
		party = inherited["party"]
	var summons: Dictionary = Summons.saved_bindings(library.get("summons", {}), records, value)
	if not summons["ok"]:
		return summons
	var clone_source: Dictionary = value.duplicate()
	clone_source["units"] = summons["staticUnits"]
	var clones: Dictionary = Clones.saved_bindings(clone_policy, records, clone_source)
	if not clones["ok"]:
		return clones
	var inferred: Dictionary = Deployment.infer_bindings(
		records,
		party,
		clones["staticUnits"],
		clones["replacedIndices"] + summons["replacedIndices"],
		promotions,
		allow_empty_slots
	)
	if not inferred["ok"]:
		return inferred
	return {
		"ok": true,
		"party": party,
		"worldStep": step,
		"route": route_index,
		"bindings": inferred["bindings"],
		"classes": inferred["classes"],
		"units": value["units"].duplicate(true),
		"cloneState": value.get("cloneState", {}).duplicate(true),
		"summonState": value.get("summonState", {}).duplicate(true)
	}


func _ordered_party(values: Array, expected: Array[int], exact: bool) -> Dictionary:
	var by_id: Dictionary = {}
	for value: Variant in values:
		if not value is Dictionary or not _integer(value.get("id")):
			return _failure("INVALID_CAMPAIGN_PARTY")
		var id: int = int(value["id"])
		if id not in expected:
			if exact:
				return _failure("INVALID_CAMPAIGN_PARTY")
			continue
		if (
			by_id.has(id)
			or not _integer(value.get("classId"))
			or value["classId"] < 0
			or value["classId"] > 40
		):
			return _failure("INVALID_CAMPAIGN_PARTY")
		by_id[id] = value
	var party: Array = []
	for id: int in expected:
		if not by_id.has(id):
			return _failure("INVALID_CAMPAIGN_PARTY")
		party.append(by_id[id].duplicate(true))
	return {"ok": true, "party": party}


func _json(path: String) -> Variant:
	return JsonDocument.read(path)


func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
	)


func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": code}
