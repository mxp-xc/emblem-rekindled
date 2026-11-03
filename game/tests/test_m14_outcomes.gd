extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const M10 = preload("res://tests/test_m10_content.gd")
const Events = preload("res://gameplay/battle_events.gd")
const CHAPTER = "res://content/chapter_1/chapter.json"


func _initialize() -> void:
	var opened: Dictionary = prepare(1, _zero)
	if not _expect(opened["ok"], "Open m14 through actual m10 settlement: " + str(opened)):
		return
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var checks: Array = content["story"]["outcomeRules"]["checks"]
	if not _expect(
		checks.size() == 2 and checks[0]["kind"] == "defeat" and checks[1]["unitId"] == 92,
		"m14 declares Alm defeat before elemental victory"
	):
		return
	var units: Array = battle.snapshot()["units"]
	for unit: Dictionary in units:
		if unit["faction"] == 1:
			unit["visible"] = false
			unit["hp"] = 0
	var rules := Events.new(content)
	if not _expect(
		rules.outcome(units).is_empty(), "All allied NPC retirements alone do not end m14"
	):
		return
	for unit: Dictionary in units:
		if unit["id"] == 92:
			unit["visible"] = false
			unit["hp"] = 0
	if not _expect(
		rules.outcome(units).get("kind") == "victory",
		"Retired element92 wins even with all allied NPCs retired"
	):
		return
	for unit: Dictionary in units:
		if unit["id"] == 0:
			unit["visible"] = false
			unit["hp"] = 0
	if not _expect(
		rules.outcome(units).get("kind") == "defeat",
		"Alm retirement takes priority over elemental victory"
	):
		return
	var victory: Array = content["story"]["sequences"]["victory"]
	if not _expect(
		(
			victory.size() == 4
			and victory[0]["text"]["sourceTextIndex"] == 616
			and victory[1]["text"]["sourceTextIndex"] == 617
			and victory[2]["text"]["sourceTextIndex"] == 618
			and victory[3]["goldReward"] == 1000
			and not content["story"]["chapterEnd"].has("itemReward")
		),
		"m14 victory declares 616–618 and 1000 gold with no terminal item"
	):
		return
	for gold: int in [7000, 9999499]:
		var state: Dictionary = battle.snapshot()
		state["gold"] = gold
		state["chapterStats"] = {"rounds": 13, "playerRetirements": 1, "allyRetirements": 2}
		if not _expect(
			battle.restore_snapshot(state)["ok"], "Restore stable m14 completion boundary"
		):
			return
		var before: Dictionary = battle.snapshot()
		if not _expect(battle.win_with_assistance()["ok"], "Commit assisted victory"):
			return
		var finish: Dictionary = battle.complete_victory(1)
		if not _expect(finish["ok"], "Settle m14 chapter completion"):
			return
		var progress: Dictionary = finish["progress"]
		if not _expect(
			(
				progress["gold"] == mini(gold + 1000, 9999999)
				and progress["chapterResult"]["chapterStats"] == before["chapterStats"]
			),
			"m14 applies exactly 1000 capped gold and records the actual statistics"
		):
			return
		var expected: Array = []
		for actor: Dictionary in before["units"]:
			if actor["formal"]:
				expected.append(actor)
		if not _expect(
			progress["party"].size() == expected.size(), "Completion retains only the formal party"
		):
			return
		for actor: Dictionary in expected:
			var found: bool = false
			for saved: Dictionary in progress["party"]:
				if saved["id"] == actor["id"]:
					found = saved["inventory"] == actor["inventory"]
			if not _expect(found, "m14 does not add an item9 or change formal inventories"):
				return
		# Each scenario starts from a fresh battle; completed battle cannot be reopened in place.
		opened = prepare(1, _zero)
		if not _expect(opened["ok"], "Open a fresh m14 for next completion case"):
			return
		battle = opened["battle"]
	print("PASS actual m14 outcomes and chapter completion")
	quit(0)


static func prepare(route: int, roll: Callable) -> Dictionary:
	var context: Dictionary = M10.CONTEXTS[1 if route == 1 else 2]
	var prepared: Dictionary = M10.prepare(context, roll)
	if not prepared["ok"]:
		return prepared
	var prior: Dictionary = Session.new().open(CHAPTER, "m10", prepared["source"], roll)
	if not prior["ok"]:
		return prior
	var won: Dictionary = prior["battle"].win_with_assistance()
	if not won["ok"]:
		return won
	var completed: Dictionary = prior["battle"].complete_victory(route)
	if not completed["ok"]:
		return completed
	var opened: Dictionary = Session.new().open(
		CHAPTER, "m14", {"progress": completed["progress"]}, roll
	)
	if opened["ok"]:
		opened["previousContent"] = prior["content"]
	return opened


func _zero(_limit: int) -> int:
	return 0


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
