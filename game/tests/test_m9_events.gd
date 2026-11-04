extends SceneTree

const Matrix = preload("res://tests/test_m9_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Events = preload("res://gameplay/battle_events.gd")
const Rounds = preload("res://tests/support/phase_driver.gd")
const Store = preload("res://persistence/battle_store.gd")
var _draws: Array[int] = []
var _owned: String


func _initialize() -> void:
	_run_contexts(Matrix.CONTEXTS.slice(0, 1))


func _run_contexts(contexts: Array) -> void:
	_owned = "user://m9_events_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("m9 events require a fresh owned directory")
		return
	for context: Dictionary in contexts:
		var prepared: Dictionary = Matrix.prepare(context, _roll)
		if not _expect(prepared["ok"], "Prepare m9 context"):
			return
		var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m9", prepared["source"], _roll)
		if not _expect(opened["ok"], "Open m9 context: " + str(opened.get("error"))):
			return
		if (
			not _opening(opened, context)
			or not _cycles(opened)
			or not _coexist(opened)
			or not _outcomes(opened)
			or not _settlement(opened, context)
		):
			return
	_cleanup()
	print(
		"PASS m9 events contexts: ",
		contexts.map(func(context: Dictionary) -> int: return context["route"])
	)
	quit(0)


func _opening(opened: Dictionary, context: Dictionary) -> bool:
	var story: Dictionary = opened["content"]["story"]
	var focuses: Array[Vector2i] = []
	var commander: Dictionary = {}
	for step: Dictionary in story["sequences"]["opening"]:
		if step["kind"] == "focus":
			focuses.append(Vector2i(int(step["cell"][0]), int(step["cell"][1])))
		elif step["kind"] == "commanderSetup":
			commander = step
		elif step["kind"] == "dialogue":
			return _expect(false, "m9 opening has no dialogue")
	var expected: Array = context["party"].duplicate()
	expected[0] = 9
	expected[1] = 0
	return _expect(
		(
			focuses == [Vector2i(9, 1), Vector2i(1, 9), Vector2i(9, 18), Vector2i(19, 9)]
			and _ints(commander["candidates"]) == expected
			and commander["defaultCommanderId"] == 9
			and opened["battle"].commander_id == 9
			and story.get("combatEvents", []).is_empty()
		),
		"Four-point opening uses actual formal party order with default9 and no boss hooks"
	)


func _cycles(opened: Dictionary) -> bool:
	var content: Dictionary = opened["content"]
	var state: Dictionary = opened["battle"].snapshot()
	var fresh: Dictionary = Session.new().open(Matrix.CHAPTER, "m9", {"snapshot": state}, _roll)
	if not _expect(fresh["ok"], "Fork real m9 cycle source"):
		return false
	var battle: RefCounted = fresh["battle"]
	for previous: int in [1, 2, 3]:
		_draws.clear()
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(advanced["ok"], "Advance m9 actual wait phases"):
			return false
		var births: Array = []
		for event: Dictionary in advanced["events"]:
			if event["kind"] == "clones":
				births.append_array(event["births"])
		if not _expect(
			(
				births.size() == (0 if previous == 1 else 2)
				and _draws == ([] if previous == 1 else [8, 8])
			),
			"Round1 is quiet; every later round draws two sources with replacement"
		):
			return false
		for born: Dictionary in births:
			var actor: Dictionary = battle.unit(int(born["unit"]))
			if not _expect(
				(
					actor["classId"] == battle.unit(107)["classId"]
					and actor["sourceId"] == battle.unit(107)["sourceId"]
				),
				"Two zero draws copy the current107 family"
			):
				return false
		var projected: Dictionary = preload("res://app/chapter_content.gd").new().reproject(
			content,
			battle.snapshot()["units"],
			battle.snapshot().get("cloneState", {}),
			battle.snapshot().get("summonState", {})
		)
		if not _expect(projected["ok"], "Bind periodic births before cold storage"):
			return false
		battle.adopt_content(projected)
		content = projected
		var store: RefCounted = Store.new(content, _owned.path_join("cycles.json"))
		if not _expect(store.write(battle)["ok"], "Write owned m9 clone state"):
			return false
		_draws.clear()
		var restored: Dictionary = store.decode(
			JSON.parse_string(FileAccess.get_file_as_string(store.path)), _roll
		)
		if not _expect(
			(
				restored["ok"]
				and _draws.is_empty()
				and restored["battle"].snapshot() == battle.snapshot()
			),
			"Cold clone restore preserves generated results and one-time rounds with zero RNG"
		):
			return false
		battle = restored["battle"]
	return true


func _coexist(opened: Dictionary) -> bool:
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if int(actor["id"]) == 31:
			actor["inventory"] = actor["inventory"].filter(
				func(item: Dictionary) -> bool: return int(item["templateId"]) == 59
			)
			actor["equippedInstanceId"] = ""
			actor["move"] = 0
	var fresh: Dictionary = Session.new().open(Matrix.CHAPTER, "m9", {"snapshot": state}, _roll)
	if not _expect(fresh["ok"], "Restore actual enemy31 staff-only boundary"):
		return false
	var battle: RefCounted = fresh["battle"]
	if not _expect(
		Rounds.advance(battle)["ok"] and battle.round_number == 2,
		"Reach second round before coexistence"
	):
		return false
	if not _expect(battle.end_phase()["ok"], "Start controlled second-round automatic phases"):
		return false
	var summoned: bool = false
	while battle.phase != 0:
		while battle.automatic_actor() >= 0:
			var actor: int = battle.automatic_actor()
			if actor == 31:
				var began: Dictionary = battle.begin_automatic_action(actor)
				if not _expect(
					began["ok"] and began["plan"].get("actionMode") == "summon",
					"Actual31 AI chooses59 before clone phase"
				):
					return false
				if not _expect(
					battle.summon_unit(actor, began["plan"]["summonItem"])["ok"],
					"Actual31 summons through common command"
				):
					return false
				summoned = true
			elif not _expect(battle.wait_unit(actor)["ok"], "Wait other actual automatic actors"):
				return false
		if not _expect(battle.end_phase()["ok"], "Finish shared summon/clone phase"):
			return false
	state = JSON.parse_string(JSON.stringify(battle.snapshot()))
	_draws.clear()
	var restored: Dictionary = Session.new().open(Matrix.CHAPTER, "m9", {"snapshot": state}, _roll)
	return _expect(
		(
			summoned
			and restored["ok"]
			and _draws.is_empty()
			and restored["battle"].snapshot()["summonState"]["bindings"].size() == 1
			and restored["battle"].snapshot()["cloneState"]["bindings"].size() == 2
			and restored["content"]["unitOrder"].slice(-3) == [70, 105, 106]
		),
		"Both dynamic pools cold-read without RNG and retain summon-before-two-clones ordering"
	)


func _outcomes(opened: Dictionary) -> bool:
	var rules: RefCounted = Events.new(opened["content"])
	var original: Array = opened["battle"].snapshot()["units"]
	for mode: String in ["one", "dead", "hidden", "absent", "priority"]:
		var units: Array = original.duplicate(true)
		for actor: Dictionary in units:
			if int(actor["id"]) == 31 or mode != "one" and int(actor["id"]) == 32:
				actor["hp"] = actor["maxHp"] if mode == "hidden" else 0
				actor["visible"] = mode == "dead"
			if mode == "priority" and int(actor["id"]) == 0:
				actor["hp"] = 0
				actor["visible"] = false
		if mode == "absent":
			units = units.filter(
				func(actor: Dictionary) -> bool: return int(actor["id"]) not in [31, 32]
			)
		var outcome: Dictionary = rules.outcome(units, 2)
		if not _expect(
			(
				outcome.is_empty()
				if mode == "one"
				else outcome.get("kind") == ("defeat" if mode == "priority" else "victory")
			),
			(
				"Conjunction retirement mode "
				+ mode
				+ " follows original priority despite other live enemies"
			)
		):
			return false
	return true


func _settlement(opened: Dictionary, context: Dictionary) -> bool:
	var battle: RefCounted = opened["battle"]
	var content: Dictionary = opened["content"]
	var dialogues: Array = []
	for step: Dictionary in content["story"]["sequences"]["victory"]:
		if step["kind"] == "dialogue":
			dialogues.append([int(step["text"]["sourceTextIndex"]), int(step["text"]["speakerId"])])
		if not _expect(step["kind"] != "routeChoice", "m9 retains route without a new choice"):
			return false
	if not _expect(
		dialogues == [[569, 7], [570 if context["step"] == 5 else 571, 0]],
		"Victory selects step5 versus late dialogue"
	):
		return false
	var before: Dictionary = battle.snapshot()
	if not _expect(battle.win_with_assistance()["ok"], "Controlled victory uses real settlement"):
		return false
	var settled: Dictionary = battle.complete_victory(context["route"])
	if not _expect(settled["ok"], "m9 settlement succeeds"):
		return false
	var world: Dictionary = settled["progress"]
	var ids: Array[int] = []
	for actor: Dictionary in world["party"]:
		ids.append(int(actor["id"]))
	var again: Dictionary = battle.complete_victory(context["route"])
	if not _expect(
		(
			ids == context["party"]
			and world["gold"] == before["gold"] + 1000
			and world["route"] == context["route"]
			and world["worldStep"] == context["step"] + 1
			and world["worldNode"] == 9
			and again.get("alreadyComplete", false)
			and again["progress"] == world
		),
		"No recruit, unchanged route and exactly one1000 reward"
	):
		return false
	var store: RefCounted = Store.new(content, _owned.path_join("world.json"))
	if not _expect(
		store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
		"Write owned m9 world records"
	):
		return false
	return _expect(
		store.read()["progress"] == world and store.read_slot(1)["progress"] == world,
		"Continue and named world records cold-read the same settlement"
	)


func _ints(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _roll(limit: int) -> int:
	_draws.append(limit)
	return 0


func _cleanup() -> void:
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)


func _expect(value: bool, message: String) -> bool:
	if not value:
		_fail(message)
	return value


func _fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
