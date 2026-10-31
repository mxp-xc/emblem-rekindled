extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://features/battle/reward_timeline.gd")
	if not script.has_method("sequence"):
		fail("Committed rewards must produce the original ordered presentation queue")
		return
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	var actors: Array = battle.snapshot()["units"]
	var result: Dictionary = {
		"participants": [battle.unit(0), battle.unit(59)],
		"brokenItems":
		[
			{"unit": 0, "templateId": 9},
			{"unit": 59, "templateId": 13},
			{"unit": 0, "templateId": 65}
		],
		"rewards":
		{
			"loot": [{"unit": 0, "item": {"templateId": 1}, "destination": "inventory"}],
			"experience":
			{
				"unit": 0,
				"amount": 12,
				"before": 99,
				"after": 11,
				"level": 2,
				"growth": {"maxHp": 1, "luck": 1}
			}
		}
	}
	var before: Dictionary = result.duplicate(true)
	var queue: Array = script.sequence(result, actors, content["interface"], false)
	var kinds: Array = queue.map(func(step: Dictionary) -> String: return step["kind"])
	if kinds != ["message", "message", "experience", "tutorial", "message", "growth"]:
		fail(
			"Only C0 weapon break precedes loot/XP/tutorial/level/growth; enemy and shield stay silent"
		)
		return
	if queue[0]["text"] != "圣天剑消失" or queue[1]["text"] != "获得":
		fail("Source break and loot wording must retain the original item name")
		return
	if queue[5]["increments"] != [1, 0, 0, 0, 0, 0, 1, 0]:
		fail("Growth presentation order must be HP/strength/skill/speed/magic/defense/luck/move")
		return
	queue = script.sequence(result, actors, content["interface"], true)
	if queue.size() != 5 or result != before:
		fail("Read tutorial must not repeat and constructing the queue must not modify settlement")
		return
	result["rewards"]["experience"]["growth"] = {}
	queue = script.sequence(result, actors, content["interface"], false)
	if queue[-1]["kind"] != "tutorial":
		fail("The first player-phase XP must trigger the source tutorial even without a level-up")
		return
	queue = script.sequence(result, actors, content["interface"], false, false)
	if queue[-1]["kind"] != "experience":
		fail("The tutorial must wait until a player-phase XP window, not interrupt an enemy phase")
		return
	if not script.sequence({"kind": "wait"}, actors, content["interface"], false).is_empty():
		fail("No rewards must produce no artificial confirmation")
		return
	var expired: Dictionary = {"actor": 0, "expiredItem": {"templateId": 60}}
	queue = script.sequence(expired, actors, content["interface"], true)
	if queue.size() != 1 or queue[0]["text"] != "药草消失":
		fail("The last healing consumable needs its own expiry notice outside combat's <60 filter")
		return
	expired = {
		"actor": 9,
		"expiredItem": {"templateId": 53},
		"rewards": {"experience": {"unit": 9, "before": 0, "amount": 12, "growth": {}}, "loot": []}
	}
	queue = script.sequence(expired, actors, content["interface"], true)
	if queue.size() != 2 or queue[0]["kind"] != "experience" or queue[1]["text"] != "治疗之杖消失":
		fail("The final staff charge must display XP before its automatic expiry notice")
		return
	result["rewards"]["loot"][0]["destination"] = "warehouse"
	queue = script.sequence(result, actors, content["interface"], true)
	if queue[1].get("warehouseNotice") != "人物携带已满存入仓库":
		fail("A full inventory must show the source warehouse destination in its loot strip")
		return
	print(
		"PASS reward sequence: filtered breaks, source order, tutorial once, growth order, immutable"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
