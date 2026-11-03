extends SceneTree

const Campaign = preload("res://gameplay/campaign_rules.gd")


func _initialize() -> void:
	var base: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for node: int in [13, 14, 15, 16]:
		for bag_size: int in [5, 6]:
			for warehouse_size: int in [0, 40]:
				var content: Dictionary = base.duplicate(true)
				content["entry"]["battleId"] = "m%d" % node
				content["entry"]["initialParty"] = [0, 9]
				content["entry"]["recruitByNode"] = {}
				content["story"]["worldNode"] = node
				content["story"]["world"]["routes"] = [[node]]
				content["story"]["chapterEnd"] = {
					"id": "chapter_1",
					"sequence": "chapterEnding",
					"itemReward": {"unitId": 0, "templateId": 9}
				}
				content["story"]["sequences"]["victory"][-1]["goldReward"] = 1000
				var state: Dictionary = load("res://gameplay/battle_state.gd").new(base).snapshot()
				state["gold"] = 9999499
				state["chapterStats"] = {"rounds": 13, "playerRetirements": 0, "allyRetirements": 2}
				state["warehouse"] = []
				for index: int in range(warehouse_size):
					state["warehouse"].append(
						{"id": "full_%d" % index, "templateId": 1, "durability": 15}
					)
				for actor: Dictionary in state["units"]:
					if actor["id"] != 0:
						continue
					actor["inventory"] = []
					actor["equippedInstanceId"] = ""
					for index: int in range(bag_size):
						actor["inventory"].append(
							{"id": "bag_%d" % index, "templateId": 1, "durability": 15}
						)
				var before: Dictionary = state.duplicate(true)
				var campaign: RefCounted = Campaign.new(content, null, 9999999)
				var settled: Dictionary = campaign.complete(state, 0)
				if not settled["ok"] or state != before:
					fail("Chapter completion creates a candidate without changing the battle")
					return
				var progress: Dictionary = settled["progress"]
				if (
					not progress.get("chapterCompleted", false)
					or progress["worldStep"] != 1
					or progress["gold"] != 9999999
				):
					fail("Every declared terminal produces a completed world and capped reward")
					return
				if (
					progress["warehouse"] != state["warehouse"]
					or settled["party"][0]["inventory"].size() != 6
				):
					fail("The terminal item is personal-only and skips a full bag")
					return
				if bag_size == 5 and settled["party"][0]["inventory"][-1]["templateId"] != 9:
					fail("A personal free slot receives the declared terminal item")
					return
				if bag_size == 5 and settled["party"][0]["inventory"][-1]["durability"] != 15:
					fail("The terminal sword receives its default fifteen durability")
					return
				var result: Dictionary = progress.get("chapterResult", {})
				if (
					result.get("chapterStats") != state["chapterStats"]
					or result.get("party", []).size() != 2
				):
					fail("Committed results retain completion-time statistics and formal party")
					return
	print(
		"PASS chapter completion: four terminal contracts, pure candidates, personal reward, results"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
