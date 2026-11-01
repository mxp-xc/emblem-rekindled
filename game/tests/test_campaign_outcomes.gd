extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json",
		"m1",
		{
			"party":
			[{"id": 0, "sourceId": 0, "classId": 0}, {"id": 9, "sourceId": 9, "classId": 4}],
			"worldStep": 1,
			"partyOrder": [9, 0],
			"route": 0
		}
	)
	var rules: RefCounted = load("res://gameplay/battle_events.gd").new(content)
	var battle: RefCounted = load("res://gameplay/battle_state.gd").new(content)
	var units: Array = battle.snapshot()["units"]
	var indexed: Dictionary = {}
	for actor: Dictionary in units:
		indexed[int(actor["id"])] = actor
	if not rules.outcome(units).is_empty():
		fail("A concealed living Alm must not lose before the original arrival")
		return
	for id: int in [0, 6]:
		indexed[id]["hp"] = 0
		indexed[id]["visible"] = false
		if rules.outcome(units).get("unit") != id:
			fail("Both required members must independently cause defeat after death cleanup")
			return
		indexed[id]["hp"] = indexed[id]["maxHp"]
		indexed[id]["visible"] = true
	for actor: Dictionary in units:
		if actor["faction"] == 2 and actor["id"] != 81:
			actor["hp"] = 0
			actor["visible"] = false
	if not rules.outcome(units).is_empty():
		fail("Defeating the other enemies must not replace the Seg objective")
		return
	indexed[6]["hp"] = 0
	indexed[6]["visible"] = false
	for condition: String in ["dead", "hidden", "absent"]:
		indexed[81]["hp"] = 0 if condition == "dead" else indexed[81]["maxHp"]
		indexed[81]["visible"] = condition != "hidden"
		var actors: Array = units.filter(
			func(actor: Dictionary) -> bool: return condition != "absent" or actor["id"] != 81
		)
		if rules.outcome(actors).get("reason") != "boss_defeated":
			fail("Seg's death, concealment and removal must each win before required death")
			return
	units = battle.snapshot()["units"]
	var before: Array = units.duplicate(true)
	rules.prepare_enemy_phase(8, units)
	if units != before:
		fail("The enemy pursuit change must not run before round nine")
		return
	rules.prepare_enemy_phase(9, units)
	for index: int in range(units.size()):
		var actor: Dictionary = units[index]
		var expected: Dictionary = before[index].duplicate(true)
		if actor["id"] in [65, 52, 51, 81, 68]:
			expected["flags"] |= 16
			expected["policy"] &= ~2
		if actor != expected:
			fail("Only the original five enemies may change pursuit flags at round nine")
			return
	var once: Array = units.duplicate(true)
	rules.prepare_enemy_phase(9, units)
	if once != units:
		fail("Reentering the pursuit boundary must not accumulate changes")
		return
	print("PASS campaign outcomes: required deaths, Seg priority, original round-nine pursuit")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
