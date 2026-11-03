extends "res://tests/test_m12_flow_combat.gd"


func _initialize() -> void:
	_owned = "user://m12_magic_%d" % Time.get_ticks_usec()
	if not _expect(DirAccess.make_dir_absolute(_owned) == OK, "Claim owned magic records"):
		return
	var context: Dictionary = Matrix.CONTEXTS[1]
	var prepared: Dictionary = Matrix.prepare(context, Flow._zero)
	if not _expect(prepared["ok"], "Prepare real route3 with two empty-slot troops"):
		return
	for round_number: int in [2, 3]:
		var opened: Dictionary = Flow.prepare_boundary(
			context, round_number, "magic", prepared["source"]
		)
		if not _expect(opened["ok"], "Prepare actual round%d magic boundary" % round_number):
			return
		var battle: RefCounted = opened["battle"]
		while battle.phase != 2:
			while battle.automatic_actor() >= 0:
				if not _expect(
					battle.wait_unit(battle.automatic_actor())["ok"],
					"Other automatic allies wait under explicit control"
				):
					return
			if not _expect(battle.end_phase()["ok"], "Advance actual phases to enemy"):
				return
		while battle.automatic_actor() >= 0 and battle.automatic_actor() != 89:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"], "Other enemies wait before boss"
			):
				return
		if not _expect(battle.automatic_actor() == 89, "Actual AI queue reaches original boss89"):
			return
		var before: Array = battle.unit(89)["inventory"].duplicate(true)
		var begun: Dictionary = battle.begin_automatic_action(89)
		if not _expect(begun["ok"], "Original boss plans actual automatic action"):
			return
		var plan: Dictionary = begun["plan"]
		if round_number == 2:
			if not _expect(
				(
					plan["actionMode"] != "map_attack"
					and plan["attackTarget"] == -1
					and battle.unit(89)["inventory"] == before
					and battle.wait_unit(89)["ok"]
				),
				"Round2 does not cast46 or consume its durability"
			):
				return
		else:
			if not _expect(
				(
					plan["actionMode"] == "map_attack"
					and plan["mapItem"] == before[0]["id"]
					and before[0]["templateId"] == 46
					and plan["mapPrimary"] == -1
				),
				"Round3 original inventory/policy4 AI selects full-map46"
			):
				return
			var cast: Dictionary = battle.cast_map_attack(89, plan["mapItem"], plan["mapPrimary"])
			if not _expect(
				(
					cast["ok"]
					and cast["targetIds"] == [9, 0, 3, 7, 6, 1, 95, 96, 11, 13, 10, 12, 15, 16]
					and cast["storyBefore"].is_empty()
					and cast["storyAfter"].is_empty()
					and battle.unit(89)["inventory"][0]["durability"] == 4
				),
				"46 hits all14 non-enemies in native traversal order and excludes593/594"
			):
				return
			for index: int in range(1, before.size()):
				if not _expect(
					battle.unit(89)["inventory"][index] == before[index],
					"46 leaves51/65/57 unchanged"
				):
					return
		for actor: Dictionary in battle.snapshot()["units"]:
			if (
				actor["faction"] != 2
				and not _expect(
					(
						actor["hp"] == 60
						if round_number == 2
						else actor["hp"] < 60 and actor["hp"] > 0
					),
					"Non-enemy HP changes only on due round3"
				)
			):
				return
		if not _expect(
			(
				not battle.event_completed("boss_first_combat")
				and not battle.event_completed("boss_death")
				and (int(battle.unit(89)["flags"]) & 4) == 0
			),
			"Map spell does not consume ordinary boss hooks/native first flag"
		):
			return
		while battle.automatic_actor() >= 0:
			if not _expect(
				battle.wait_unit(battle.automatic_actor())["ok"], "Remaining automatic enemies wait"
			):
				return
		if not _expect(
			battle.end_phase()["ok"] and battle.phase == 0,
			"Complete enemy phase to stable player boundary"
		):
			return
		var store := Store.new(opened["content"], _owned.path_join("round%d.json" % round_number))
		if not _expect(store.write(battle)["ok"], "Write real completed round state"):
			return
		var read: Dictionary = store.read()
		if not _expect(
			read["ok"] and read["battle"].snapshot() == battle.snapshot(),
			"Cold read preserves full-map damage and actual held durability"
		):
			return
	_cleanup()
	print(
		"PASS m12 actual89 AI round2 no46,round3 all14 hostile targets,cold state,no ordinary hooks"
	)
	quit(0)
