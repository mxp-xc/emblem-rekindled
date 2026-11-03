extends SceneTree

const Contract = preload("res://app/chapter_story_contract.gd")
const Content = preload("res://app/chapter_content.gd")
const ChapterProjection = preload("res://app/chapter_projection.gd")
var failed: bool = false


func _initialize() -> void:
	_visit_contract()
	_story_contract()
	if not failed:
		print("PASS m13 content contracts")
	quit(1 if failed else 0)


func _visit_contract() -> void:
	var map: Dictionary = {
		"width": 1,
		"height": 1,
		"tiles": [[58]],
		"terrain": [[6]],
		"movementCosts": {},
		"locations": []
	}
	var rules: Dictionary = {"itemTemplates": [{"id": 0}, {"id": 33}, {"id": 57}]}
	var location: Dictionary = {
		"id": "visit_0",
		"kind": "visit",
		"sourceIndex": 0,
		"position": [0, 0],
		"tileId": 58,
		"reward":
		{
			"kind": "weightedItem",
			"weightedChoices": [{"templateId": 57, "weight": 20}, {"templateId": 33, "weight": 70}]
		}
	}
	map["locations"] = [location]
	_check(
		Contract.validate_locations(map, rules, {}),
		"A visit allows ordered weights with an empty remainder"
	)
	for invalid: String in [
		"overweight",
		"negative",
		"fraction",
		"zero_template",
		"unknown",
		"conflict",
		"source",
		"terrain",
		"opened"
	]:
		var bad: Dictionary = map.duplicate(true)
		var reward: Dictionary = bad["locations"][0]["reward"]
		match invalid:
			"overweight":
				reward["weightedChoices"][1]["weight"] = 81
			"negative":
				reward["weightedChoices"][0]["weight"] = -1
			"fraction":
				reward["weightedChoices"][0]["weight"] = 0.5
			"zero_template":
				reward["weightedChoices"][0]["templateId"] = 0
			"unknown":
				reward["weightedChoices"][0]["templateId"] = 999
			"conflict":
				reward["templateId"] = 33
			"source":
				bad["locations"][0]["sourceIndex"] = 1
			"terrain":
				bad["terrain"][0][0] = 7
			"opened":
				bad["locations"][0]["openedVariant"] = "opened"
		_check(
			not Contract.validate_locations(bad, rules, {}),
			"Reject malformed visit declaration: " + invalid
		)
	for reward: Dictionary in [
		{"kind": "item", "templateId": 33}, {"kind": "goldRange", "minimum": 1, "maximum": 500}
	]:
		map["locations"][0]["reward"] = reward
		_check(
			Contract.validate_locations(map, rules, {}),
			"Fixed items and inclusive gold ranges are valid"
		)
	map["locations"][0]["reward"] = {"kind": "goldRange", "minimum": 500, "maximum": 1}
	_check(not Contract.validate_locations(map, rules, {}), "A reversed gold range rejects")


func _story_contract() -> void:
	var content: Dictionary = Content.new().load_chapter("res://content/chapter_1/chapter.json")
	_check(content["ok"], "The existing chapter remains loadable")
	if not content["ok"]:
		return
	var story: Dictionary = content["story"].duplicate(true)
	var ids: Dictionary = {}
	for unit: Dictionary in content["units"]:
		ids[int(unit["id"])] = unit
	for id: int in content.get("referenceIds", []):
		if not ids.has(id):
			ids[id] = {}
	story["commanderMode"] = "none"
	var opening: Array = []
	for step: Dictionary in story["sequences"]["opening"]:
		if step["kind"] != "commanderSetup":
			opening.append(step)
	story["sequences"]["opening"] = opening
	story["aiChanges"] = [
		{
			"beforeAutomaticPhase": {"round": 9, "faction": 1},
			"unitIds": [0],
			"flagsSet": 16,
			"policyClear": 4
		}
	]
	story["outcomeRules"]["checks"].push_front(
		{
			"kind": "defeat",
			"condition": "allUnitsRetired",
			"unitIds": [0],
			"reason": "all_npc_retired"
		}
	)
	_check(
		_valid(story, content, ids),
		"None opening, automatic phase timing and all-retired defeat are accepted"
	)
	var bad: Dictionary = story.duplicate(true)
	bad["sequences"]["newGame"].append(
		{"kind": "prologue", "text": {"text": "无图", "sourceTextIndex": 459}}
	)
	_check(not _valid(bad, content, ids), "Ordinary prologue still requires an explicit image")
	bad = story.duplicate(true)
	bad["commanderMode"] = "selection"
	_check(not _valid(bad, content, ids), "Selection still requires commander setup")
	bad = story.duplicate(true)
	bad["aiChanges"][0]["beforeEnemyPhaseOfRound"] = 9
	_check(not _valid(bad, content, ids), "AI timing declarations are mutually exclusive")
	bad = story.duplicate(true)
	bad["aiChanges"][0]["beforeAutomaticPhase"]["faction"] = 0
	_check(not _valid(bad, content, ids), "Player phase cannot be declared automatic")
	story["world"]["routes"] = [[0, 1]]
	story["worldNode"] = 1
	story["routeChoices"] = []
	story["sequences"]["victory"] = [{"kind": "focus", "unitId": 0}]
	story["chapterEnd"] = {
		"id": "chapter_1", "sequence": "chapterEnding", "itemReward": {"unitId": 0, "templateId": 9}
	}
	story["sequences"]["chapterEnding"] = [
		{"kind": "chapterParty"}, {"kind": "chapterSummary"}, {"kind": "chapterRating"}
	]
	story["sequences"]["chapterEnding"].push_front(
		{"kind": "prologue", "text": {"text": "章末", "sourceTextIndex": 459}}
	)
	story["sequences"]["chapterEnding"].append({"kind": "instruction", "text": {"text": "初章（完）"}})
	_check(
		_valid(story, content, ids), "An explicit final node accepts a finite local chapter ending"
	)
	bad = story.duplicate(true)
	bad["sequences"]["newGame"].append({"kind": "instruction", "text": {"text": "无来源"}})
	_check(
		not _valid(bad, content, ids),
		"Local ending text does not relax ordinary story source requirements"
	)
	bad = story.duplicate(true)
	bad["sequences"]["chapterEnding"].append({"kind": "dialogue", "text": {"text": "无来源对白"}})
	_check(
		not _valid(bad, content, ids), "A non-instruction ending step still requires a source index"
	)
	bad = story.duplicate(true)
	bad["sequences"]["chapterEnding"][-1]["text"]["sourceTextIndex"] = "invalid"
	_check(
		not _valid(bad, content, ids), "An explicitly supplied invalid source index still rejects"
	)
	var projected: Dictionary = ChapterProjection.resolve_story(
		story, content["units"], {}, {"route": 0, "worldStep": 1}
	)
	_check(
		projected["ok"] and projected["story"]["routeChoices"].is_empty(),
		"Terminal projection does not access a next node"
	)
	_check(
		not (
			ChapterProjection
			. resolve_story(story, content["units"], {}, {"route": 0, "worldStep": 0})["ok"]
		),
		"A terminal cannot project at an earlier route step"
	)
	bad = story.duplicate(true)
	bad["worldNode"] = 0
	_check(not _valid(bad, content, ids), "An earlier node cannot declare chapter completion")
	bad = story.duplicate(true)
	bad["chapterEnd"]["itemReward"]["unitId"] = 999
	_check(not _valid(bad, content, ids), "Chapter reward must name an existing formal member")
	bad = story.duplicate(true)
	bad["sequences"]["chapterEnding"] = []
	_check(not _valid(bad, content, ids), "Chapter ending must reference a nonempty sequence")


func _valid(story: Dictionary, content: Dictionary, ids: Dictionary) -> bool:
	return Contract.validate(
		story,
		content["entry"]["resourceDirectory"],
		ids,
		int(content["map"]["width"]),
		int(content["map"]["height"])
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
