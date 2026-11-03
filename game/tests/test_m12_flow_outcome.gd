extends "res://tests/test_m12_flow_combat.gd"

const Events = preload("res://gameplay/battle_events.gd")


func _contexts() -> Array[Dictionary]:
	return [Matrix.CONTEXTS[0]]


func _initialize() -> void:
	_owned = "user://m12_outcome_%d" % Time.get_ticks_usec()
	if not _expect(DirAccess.make_dir_absolute(_owned) == OK, "Claim owned outcome records"):
		return
	for context: Dictionary in _contexts():
		var prepared: Dictionary = Matrix.prepare(context, Flow._zero)
		if not _expect(prepared["ok"], "Prepare real m8 settlement for outcome"):
			return
		var opened: Dictionary = Flow.prepare_boundary(context, 1, "victory", prepared["source"])
		if not _expect(opened["ok"], "Prepare actual last visible enemy boundary"):
			return
		var content: Dictionary = opened["content"]
		var battle: RefCounted = opened["battle"]
		var initial: Dictionary = battle.snapshot()
		var priority: Array = initial["units"].duplicate(true)
		for actor: Dictionary in priority:
			if actor["faction"] == 2 or actor["id"] == 0:
				actor["hp"] = 0
				actor["visible"] = false
		if not _expect(
			(
				Events.new(content).outcome(priority).get("kind") == "defeat"
				and Events.new(content).outcome(priority).get("unit") == 0
			),
			"Required0 defeat takes priority when every enemy also retired"
		):
			return
		var won: Dictionary = battle.attack_unit(0, 89)
		var hidden: int = 0
		for actor: Dictionary in battle.snapshot()["units"]:
			if actor["faction"] == 2 and not actor["visible"] and actor["hp"] > 0:
				hidden += 1
		if not _expect(
			(
				won["ok"]
				and battle.outcome.get("kind") == "victory"
				and hidden == 16
				and not battle.event_completed("location:chest_0")
			),
			"Last visible enemy retirement wins with all sixteen hidden ambushers alive and chests untouched"
		):
			return
		var dialogues: Array = []
		for step: Dictionary in content["story"]["sequences"]["victory"]:
			if step["kind"] == "dialogue":
				dialogues.append(
					[int(step["text"]["sourceTextIndex"]), int(step["text"]["speakerId"])]
				)
		if not _expect(
			dialogues == [[595, 1], [596 if context["step"] == 5 else 597, 0]],
			"Step5 uses596;step8 uses597 after595, with no route change"
		):
			return
		var settled: Dictionary = battle.complete_victory(context["route"])
		if not _expect(settled["ok"], "Real visible-enemy victory settles"):
			return
		var world: Dictionary = settled["progress"]
		var ids: Array[int] = []
		for actor: Dictionary in world["party"]:
			ids.append(int(actor["id"]))
		var repeated: Dictionary = battle.complete_victory(context["route"])
		if not _expect(
			(
				world["route"] == context["route"]
				and world["worldNode"] == 12
				and world["worldStep"] == context["step"] + 1
				and world["completedBattle"] == "m12"
				and world["gold"] == initial["gold"] + 1000
				and ids == context["party"]
				and repeated.get("alreadyComplete", false)
				and repeated["progress"] == world
			),
			"Settlement keeps formal party, excludes allies/temporary troops, awards1000 once"
		):
			return
		var store := Store.new(content, _owned.path_join("world.json"))
		if not _expect(
			store.write_progress(world)["ok"] and store.write_slot(1, world)["ok"],
			"Write actual world and named slot"
		):
			return
		var continued: Dictionary = store.read()
		var slotted: Dictionary = store.read_slot(1)
		if not _expect(
			(
				continued["ok"]
				and slotted["ok"]
				and continued["progress"] == world
				and slotted["progress"] == world
			),
			"Both actual world records cold-read exact settlement and57 loot"
		):
			return
		var required: Dictionary = Flow.prepare_boundary(context, 1, "required", prepared["source"])
		if not _expect(required["ok"], "Prepare required0 ordinary counter boundary"):
			return
		var lost: Dictionary = required["battle"].attack_unit(0, 41)
		if not _expect(
			(
				lost["ok"]
				and required["battle"].unit(0)["hp"] == 0
				and required["battle"].outcome.get("kind") == "defeat"
				and required["battle"].outcome.get("unit") == 0
			),
			"Real ordinary counter retirement of required0 loses m12"
		):
			return
	_cleanup()
	print("PASS m12 visible-enemy victory,required0 priority,step5/8 fixed settlement,cold world")
	quit(0)
