extends SceneTree

const ContentProjection = preload("res://app/chapter_projection.gd")
const Content = preload("res://app/chapter_content.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var root: String = "res://content/chapter_1/generated/"
	var bank: Dictionary = _bank(root)
	var before: Dictionary = bank.duplicate(true)
	var definition: Dictionary = {
		"profiles":
		{
			"source_0_job_0_faction_0": "hero",
			"slot_0_job_8_faction_0": "temporary",
			"source_9_job_8_faction_0": "inherited"
		},
		"stage": "stage_0",
		"scene": "scene_0"
	}
	var records: Array = [_record(0, 0, [2, 3]), _record(0, 8, [4, 5])]
	records[1]["deploymentSlot"] = 0
	records[1]["policy"] = 32
	var chapter: Dictionary = {
		"library": root + "library/catalog.json", "resourceDirectory": "res://"
	}
	var empty: Dictionary = ContentProjection.project(chapter, definition, bank, records, {})
	var inherited: Dictionary = ContentProjection.project(
		chapter, definition, bank, records, {"party": [{"id": 9, "classId": 8}], "partyOrder": [9]}
	)
	var user_catalog: Dictionary = ContentProjection.project(
		{"library": "user://fixture/catalog.json", "resourceDirectory": "res://"},
		definition,
		bank,
		records,
		{}
	)
	if not empty["ok"] or not inherited["ok"]:
		_fail("Distinct party projections must bind successfully: " + str([empty, inherited]))
		return
	if (
		empty["slots"][0] != 95
		or inherited["slots"][0] != 9
		or not empty["battleArt"]["appearances"].has("95:0")
		or not inherited["battleClips"]["appearances"].has("9:0")
		or inherited["battleArt"]["appearances"].has("95:0")
		or inherited["unitOrder"] != [9, 0]
		or empty["unitOrder"] != [0, 95]
		or bank != before
		or user_catalog != empty
	):
		_fail("Catalog reuse must not leak one party's aliases into another")
		return
	for wrong_order: Variant in [[], [9, 9], [0], [9.5], "invalid"]:
		if (
			ContentProjection
			. project(
				chapter,
				definition,
				bank,
				records,
				{"party": [{"id": 9, "classId": 8}], "partyOrder": wrong_order}
			)["ok"]
		):
			_fail("The existing-party traversal prefix must contain every member exactly once")
			return
	if (
		empty["units"][0]["sprite"] != root + "shared/hero.png"
		or (
			empty["mapAnimations"]["units"]["0"]["frames"][0]["texture"] != root + "shared/hero.png"
		)
		or (empty["battleClips"]["clips"]["pair/0/hit"] != root + "library/clips/pair.json")
	):
		_fail("Projection must keep absolute resources until the composed view is rebased")
		return
	empty["mapAnimations"]["units"]["0"]["frames"][0]["texture"] = "changed.png"
	if (
		bank != before
		or (
			inherited["mapAnimations"]["units"]["0"]["frames"][0]["texture"]
			!= root + "shared/hero.png"
		)
	):
		_fail("Projected map animations must not mutate the shared catalog or another view")
		return
	var missing: Dictionary = definition.duplicate(true)
	missing["profiles"].erase("source_9_job_8_faction_0")
	if (
		ContentProjection
		. project(
			chapter, missing, bank, records, {"party": [{"id": 9, "classId": 8}], "partyOrder": [9]}
		)["ok"]
	):
		_fail("Missing current-class presentation must reject entry")
		return
	var malformed_bank: Dictionary = bank.duplicate(true)
	malformed_bank["profiles"]["hero"]["appearances"]["0"] = "invalid"
	if ContentProjection.project(chapter, definition, malformed_bank, records, {})["ok"]:
		_fail("Malformed appearance payloads must return a content failure")
		return
	malformed_bank = bank.duplicate(true)
	malformed_bank["profiles"]["hero"]["mapAnimation"] = "missing"
	if ContentProjection.project(chapter, definition, malformed_bank, records, {})["ok"]:
		_fail("Missing map animation references must return a content failure")
		return
	malformed_bank = bank.duplicate(true)
	malformed_bank["storyCommon"]["images"] = "invalid"
	if ContentProjection.project(chapter, definition, malformed_bank, records, {})["ok"]:
		_fail("Malformed common story fields must fail before merging")
		return
	var common: Dictionary = {
		"images": {"common": {"texture": "common.png"}},
		"speakers": {"0": {"name": "Hero"}},
		"sequences": {"boot": [{"kind": "prologue"}]}
	}
	var fragment: Dictionary = {
		"battleName": {"text": "森林"},
		"images": {"local": {"texture": "local.png"}},
		"sequences":
		{
			"opening": [{"kind": "battleTitle", "text": {"text": "旧战序"}}],
			"arrival":
			[
				{
					"kind": "parallelEntrances",
					"deploymentSlots": [0],
					"offset": [-3, 0],
					"focus": [4, 5]
				}
			],
			"victory":
			[
				{"kind": "dialogue", "whenWorldStep": 2, "text": {"text": "早期"}},
				{"kind": "dialogue", "unlessWorldStep": 2, "text": {"text": "后期"}}
			]
		},
		"turnEvents": [{"id": "arrive", "deploymentSlots": [0], "unitIds": [0]}]
	}
	var merged: Dictionary = ContentProjection.merge_story(common, fragment)
	var story: Dictionary = ContentProjection.resolve_story(
		merged,
		inherited["units"],
		inherited["slots"],
		{"worldStep": 2, "units": [{"id": 9, "x": 8, "y": 10}]}
	)
	if not story["ok"]:
		_fail("Story selectors must resolve: " + str(story))
		return
	var resolved: Dictionary = story["story"]
	var entrance: Dictionary = resolved["sequences"]["arrival"][0]["units"][0]
	if (
		not merged["sequences"].has("boot")
		or not merged["images"].has("common")
		or entrance["unitId"] != 9
		or entrance["from"] != [5, 10]
		or entrance["to"] != [8, 10]
		or resolved["turnEvents"][0]["unitIds"] != [0, 9]
		or resolved["sequences"]["victory"].size() != 1
		or resolved["sequences"]["victory"][0]["text"]["text"] != "早期"
		or resolved["sequences"]["opening"][0]["text"]["text"] != "第3战\n森林"
		or common["sequences"].has("opening")
	):
		_fail(
			"Story must resolve current deployment, battle number and conditions without mutating source"
		)
		return
	fragment["sequences"]["arrival"][0]["deploymentSlots"] = [0.5]
	if ContentProjection.resolve_story(fragment, inherited["units"], inherited["slots"], {})["ok"]:
		_fail("Fractional deployment selectors must be rejected")
		return
	for defect: String in ["battleName", "world", "options"]:
		var malformed_story: Dictionary = merged.duplicate(true)
		var malformed_context: Dictionary = {}
		match defect:
			"battleName":
				malformed_story["battleName"] = "invalid"
			"world":
				malformed_story["world"] = "invalid"
				malformed_context["route"] = 0
			"options":
				malformed_story["sequences"]["victory"] = [
					{"kind": "routeChoice", "options": "invalid"}
				]
		if (
			ContentProjection
			. resolve_story(
				malformed_story, inherited["units"], inherited["slots"], malformed_context
			)["ok"]
		):
			_fail("Malformed story fields must return a content failure: " + defect)
			return
	var text_table: Dictionary = {
		"499": {"sourceTextIndex": 499, "text": "首领对白", "paragraphs": ["首领对白"], "speakerId": null}
	}
	var text_ref: Dictionary = {"line": {"sourceTextIndex": 499.0, "speakerId": 82}}
	var compiled_text: Dictionary = ContentProjection.resolve_texts(text_ref, text_table)
	if (
		not compiled_text["ok"]
		or compiled_text["value"]["line"]["text"] != "首领对白"
		or compiled_text["value"]["line"]["speakerId"] != 82
		or compiled_text["value"]["line"]["paragraphs"] != ["首领对白"]
		or text_ref["line"].has("text")
	):
		_fail("Text references must preserve shared line metadata and local speaker overrides")
		return
	if ContentProjection.resolve_texts({"line": {"sourceTextIndex": 500}}, text_table)["ok"]:
		_fail("Missing shared text must reject the story before entry")
		return
	var fixed_entrance: Dictionary = merged.duplicate(true)
	fixed_entrance["sequences"]["arrival"][0].erase("deploymentSlots")
	fixed_entrance["sequences"]["arrival"][0]["unitIds"] = [0]
	var fixed_story: Dictionary = ContentProjection.resolve_story(
		fixed_entrance, inherited["units"], inherited["slots"], {}
	)
	if (
		not fixed_story["ok"]
		or fixed_story["story"]["sequences"]["arrival"][0]["units"][0]["unitId"] != 0
	):
		_fail("Fixed-unit entrances must use the same actual-position projection as slots")
		return
	var route_story: Dictionary = merged.duplicate(true)
	route_story["world"] = {"routes": [[0, 1, 2, 3, 4, 10, 5, 6, 11, 15]], "nodes": []}
	for id: int in range(16):
		route_story["world"]["nodes"].append({"id": id, "name": "地点%d" % id})
	route_story["routeChoices"] = [{"routeIndex": 0, "nodeId": 1, "label": "旧地点", "portraitId": 9}]
	for step: int in [2, 7]:
		var projected_route: Dictionary = ContentProjection.resolve_story(
			route_story,
			inherited["units"],
			inherited["slots"],
			{"route": 0, "worldStep": step, "recruitByNode": {"3": 3}}
		)
		if not projected_route["ok"]:
			_fail("Keeping a route must resolve its actual next node")
			return
		var option: Dictionary = projected_route["story"]["routeChoices"][0]
		var next_node: int = 3 if step == 2 else 11
		if (
			option["routeIndex"] != 0
			or option["nodeId"] != next_node
			or option["label"] != "地点%d" % next_node
			or (step == 2 and option.get("portraitId") != 3)
			or (step == 7 and option.has("portraitId"))
		):
			_fail("Keeping route metadata must not retain an earlier map's next node or portrait")
			return
	var encounter_story: Dictionary = route_story.duplicate(true)
	encounter_story["encounter"] = true
	for step: int in [6, 10]:
		var encounter: Dictionary = ContentProjection.resolve_story(
			encounter_story, inherited["units"], inherited["slots"], {"route": 0, "worldStep": step}
		)
		if (
			not encounter["ok"]
			or encounter["story"]["worldNode"] != route_story["world"]["routes"][0][step - 1]
			or not encounter["story"]["routeChoices"].is_empty()
		):
			_fail(
				"Encounters must retain the completed route frontier, including after chapter end"
			)
			return
	for step: int in [5, 11]:
		if (
			ContentProjection
			. resolve_story(
				encounter_story,
				inherited["units"],
				inherited["slots"],
				{"route": 0, "worldStep": step}
			)["ok"]
		):
			_fail("Encounters outside the original progress range must be rejected")
			return
	var broken_encounter: Dictionary = encounter_story.duplicate(true)
	broken_encounter["world"] = "invalid"
	if (
		ContentProjection
		. resolve_story(
			broken_encounter, inherited["units"], inherited["slots"], {"route": 0, "worldStep": 6}
		)["ok"]
	):
		_fail("Invalid encounter world definitions must fail without crashing")
		return
	print("PASS chapter projection: shared catalog, profiles, resource paths and story selectors")
	quit(0)


func _record(source: int, job: int, point: Array) -> Dictionary:
	return {
		"kind": 1,
		"sourceId": source,
		"classId": job,
		"faction": 0,
		"level": 1,
		"flags": 0,
		"policy": 0,
		"position": point,
		"randomEquipment": false,
		"itemChoices": [0, 0, 0],
		"dropTemplateId": 0
	}


func _bank(root: String) -> Dictionary:
	var bank: Dictionary = {
		"profiles": {},
		"appearancePool": {"hero": {"frames": [{"texture": root + "shared/hero.png"}]}},
		"mapAnimationPool": {"hero": {"frames": [{"texture": root + "shared/hero.png"}]}},
		"stages": {"stage_0": {"clips": {"pair/0/hit": root + "library/clips/pair.json"}}},
		"scenes": {"scene_0": {}},
		"interface": {"textures": {}},
		"storyCommon": {},
		"texts": {},
		"mapEffects": {}
	}
	for definition: Array in [["hero", 0], ["temporary", 8], ["inherited", 8]]:
		bank["profiles"][definition[0]] = {
			"unit": {"classId": definition[1], "sprite": root + "shared/hero.png"},
			"mapAnimation": "hero",
			"portrait": {"texture": null, "usesCommanderPortrait": true},
			"appearances": {"0": "hero"},
			"motion": {"stage_0": {"0": {"canAttack": false, "defenseGroup": "standing"}}}
		}
	return bank


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
