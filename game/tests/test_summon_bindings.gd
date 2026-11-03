extends SceneTree

const M4 = preload("res://tests/test_m4_content.gd")
const M5 = preload("res://tests/test_m5_content.gd")
const Rounds = preload("res://tests/test_m4_events.gd")
const Matrix = preload("res://tests/test_m8_content.gd")
const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Store = preload("res://persistence/battle_store.gd")
var _draws: int = 0
var _birth_draws: int = 0
var _owned: String


func _initialize() -> void:
	_owned = "user://summon_bindings_%d" % Time.get_ticks_usec()
	if DirAccess.make_dir_absolute(_owned) != OK:
		_fail("Summon bindings require a fresh owned record directory")
		return
	if not _cold_restore():
		_cleanup()
		return
	_cleanup()
	print(
		"PASS summon Session/Store: trusted family, m4 mixed, m5 static70, cold RNG and world exclusion"
	)
	quit(0)


func _cold_restore() -> bool:
	var prepared: Dictionary = Matrix.prepare(Matrix.CONTEXTS[5], _roll)
	if not _expect(prepared["ok"], "Prepare legal route6 m8 source"):
		return false
	var opened: Dictionary = Session.new().open(Matrix.CHAPTER, "m8", prepared["source"], _roll)
	if not _expect(opened["ok"], "Open m8 through Session"):
		return false
	var battle: RefCounted = opened["battle"]
	var staff: String = ""
	for held: Dictionary in battle.unit(1)["inventory"]:
		if int(held["templateId"]) == 59:
			staff = held["id"]
	var result: Dictionary = battle.summon_unit(1, staff)
	if not _expect(result["ok"] and result["births"].size() == 1, "Real command births one ally"):
		return false
	var identity: int = int(result["births"][0]["unit"])
	var state: Dictionary = battle.snapshot()
	var projected: Dictionary = Content.new().reproject(
		opened["content"], state["units"], state.get("cloneState", {}), state["summonState"]
	)
	if not _expect(projected["ok"], "Current summon reprojects through its catalog family"):
		return false
	battle.adopt_content(projected)
	var store: RefCounted = Store.new(projected, _owned.path_join("continue.json"))
	if not _expect(store.write(battle)["ok"], "Write summon only to owned record"):
		return false
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	var before: Dictionary = record.duplicate(true)
	_draws = 0
	var restored: Dictionary = store.decode(record, _roll)
	if not _expect(
		(
			restored["ok"]
			and _draws == 0
			and record == before
			and restored["battle"].snapshot() == state
		),
		"Cold JSON restore preserves summon state and items without initialization RNG"
	):
		return false
	var forged: Dictionary = JSON.parse_string(JSON.stringify(state))
	for actor: Dictionary in forged["units"]:
		if int(actor["id"]) == identity:
			actor["sprite"] = "res://untrusted.png"
			actor["name"] = "untrusted"
	_draws = 0
	var trusted: Dictionary = Session.new().open(Matrix.CHAPTER, "m8", {"snapshot": forged}, _roll)
	if not _expect(
		(
			trusted["ok"]
			and _draws == 0
			and trusted["battle"].unit(identity)["sprite"] == battle.unit(identity)["sprite"]
			and trusted["battle"].unit(identity)["name"] == battle.unit(identity)["name"]
		),
		"Saved name and sprite never override the declared summon family"
	):
		return false
	for field: String in ["classId", "faction", "generation", "unitId", "afterCloneGeneration"]:
		var invalid: Dictionary = state.duplicate(true)
		invalid["summonState"]["bindings"][0][field] = -1
		_draws = 0
		var rejected: Dictionary = Session.new().open(
			Matrix.CHAPTER, "m8", {"snapshot": invalid}, _roll
		)
		if not _expect(not rejected["ok"] and _draws == 0, "Reject forged summon binding " + field):
			return false
	var reversed: Dictionary = state.duplicate(true)
	reversed["units"].reverse()
	reversed["summonState"]["bindings"].reverse()
	var canonical: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m8", {"snapshot": reversed}, _roll
	)
	if not _expect(
		canonical["ok"] and canonical["battle"].snapshot() == state,
		"Summon-only JSON order preserves canonical birth order"
	):
		return false
	var future: Dictionary = state.duplicate(true)
	future["summonState"]["bindings"][0]["afterCloneGeneration"] = 1
	if not _expect(
		not Session.new().open(Matrix.CHAPTER, "m8", {"snapshot": future}, _roll)["ok"],
		"Map without clones rejects a positive clone anchor"
	):
		return false
	if not _recycled_family(state):
		return false
	if not _mixed():
		return false
	var real_staff: Dictionary = {}
	for held: Dictionary in battle.unit(1)["inventory"]:
		if int(held["templateId"]) == 59:
			real_staff = held
	if not _expect(
		not real_staff.is_empty(), "Static replacement fixture requires the real m8 staff"
	):
		return false
	if not _static_replacement(real_staff):
		return false
	var undeclared: Dictionary = state.duplicate(true)
	undeclared.erase("summonState")
	if not _expect(
		not Session.new().open(Matrix.CHAPTER, "m8", {"snapshot": undeclared}, _roll)["ok"],
		"Unbound extra actor cannot become a static deployment"
	):
		return false
	if not _expect(
		battle.win_with_assistance()["ok"], "Controlled victory reaches actual settlement"
	):
		return false
	var completed: Dictionary = battle.complete_victory(6)
	if not _expect(completed["ok"], "Settle route6 with a summoned ally still alive"):
		return false
	for member: Dictionary in completed["progress"]["party"]:
		if not _expect(
			int(member["id"]) != identity and member["formal"], "World keeps only formal party"
		):
			return false
	return _expect(
		completed["progress"]["party"].size() == 4,
		"Summon is excluded while new formal1 and inherited0/9/5 remain"
	)


func _mixed() -> bool:
	var prepared: Dictionary = M4.prepare(M4.CONTEXTS[0], _roll)
	if not _expect(prepared["ok"], "Prepare real m4 mixed-birth context"):
		return false
	var opened: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m4", {"progress": prepared["progress"]}, _roll
	)
	if not _expect(opened["ok"], "Open real m4 with its existing periodic clone policy"):
		return false
	var state: Dictionary = opened["battle"].snapshot()
	var fresh: Dictionary = Session.new().open(Matrix.CHAPTER, "m4", {"snapshot": state}, _roll)
	if not _expect(fresh["ok"], "Restore actual m4 mixed boundary"):
		return false
	var battle: RefCounted = fresh["battle"]
	var first: Dictionary = _enemy_summon(battle)
	if not _expect(
		first.get("ok", false) and int(first["births"][0]["unit"]) == 70,
		"Enemy staff allocates free70 before any clone wave"
	):
		return false
	var finished: Dictionary = Rounds.advance(battle)
	if not _expect(finished["ok"] and battle.round_number == 2, "Finish first summon phase"):
		return false
	while battle.round_number < 4:
		var advanced: Dictionary = Rounds.advance(battle)
		if not _expect(advanced["ok"], "Advance real phases through round3 clone wave"):
			return false
	var projected: Dictionary = Content.new().reproject(
		fresh["content"],
		battle.snapshot()["units"],
		battle.snapshot()["cloneState"],
		battle.snapshot()["summonState"]
	)
	if not _expect(projected["ok"], "Bind real m4 first summon and first clone wave"):
		return false
	battle.adopt_content(projected)
	var second: Dictionary = _enemy_summon(battle)
	if not _expect(
		second.get("ok", false) and int(second["births"][0]["unit"]) == 71,
		"Second enemy summon follows the first clone wave"
	):
		return false
	finished = Rounds.advance(battle)
	if not _expect(
		finished["ok"] and battle.round_number == 5, "Finish second summon and round4 clone wave"
	):
		return false
	state = JSON.parse_string(JSON.stringify(battle.snapshot()))
	_draws = 0
	var restored: Dictionary = Session.new().open(Matrix.CHAPTER, "m4", {"snapshot": state}, _roll)
	if not _expect(restored["ok"], "Cold restore real mixed m4: " + str(restored.get("error"))):
		return false
	var expected: Array[int] = [70, 105, 106, 116, 71, 117, 118, 119]
	if not _expect(
		restored["content"]["unitOrder"].slice(-8) == expected and _draws == 0,
		"Real two-wave anchor order is summon, three clones, summon, three clones"
	):
		return false
	var current70: Dictionary = restored["battle"].unit(70)
	if not _expect(
		(
			current70["sourceId"] == 70
			and current70["classId"] == 28
			and not current70.has("deploymentIndex")
			and current70["inventory"] == battle.unit(70)["inventory"]
		),
		"Cold restore retains the summoned70 family and held items"
	):
		return false
	state["units"].reverse()
	state["summonState"]["bindings"].reverse()
	state["cloneState"]["bindings"].reverse()
	var again: Dictionary = Session.new().open(Matrix.CHAPTER, "m4", {"snapshot": state}, _roll)
	if not _expect(
		again["ok"] and again["battle"].snapshot() == restored["battle"].snapshot(),
		"Mixed array reversal preserves canonical clone/summon order"
	):
		return false
	for anchor: int in [-1, 7]:
		var invalid: Dictionary = state.duplicate(true)
		invalid["summonState"]["bindings"][0]["afterCloneGeneration"] = anchor
		if not _expect(
			not Session.new().open(Matrix.CHAPTER, "m4", {"snapshot": invalid}, _roll)["ok"],
			"Reject negative or future real-wave anchor"
		):
			return false
	# m4 has no static70: removing its summons leaves a genuine clone-only state.
	var clone_only: Dictionary = state.duplicate(true)
	clone_only.erase("summonState")
	clone_only["units"] = clone_only["units"].filter(
		func(actor: Dictionary) -> bool: return int(actor["id"]) not in [70, 71]
	)
	var clone_first: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m4", {"snapshot": clone_only}, _roll
	)
	clone_only["units"].reverse()
	clone_only["cloneState"]["bindings"].reverse()
	var clone_again: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m4", {"snapshot": clone_only}, _roll
	)
	return _expect(
		(
			clone_first["ok"]
			and clone_again["ok"]
			and clone_first["battle"].snapshot() == clone_again["battle"].snapshot()
		),
		"Real clone-only generations remain canonical after array reversal"
	)


func _enemy_summon(battle: RefCounted, caster: int = 30) -> Dictionary:
	var remaining: int = battle.snapshot()["units"].size() * 3
	while battle.automatic_actor() != caster and remaining > 0:
		var actor: int = battle.automatic_actor()
		var progressed: Dictionary = battle.end_phase() if actor < 0 else battle.wait_unit(actor)
		if not progressed["ok"]:
			return progressed
		remaining -= 1
	if battle.automatic_actor() != caster:
		return {"ok": false, "error": "CASTER_NOT_QUEUED"}
	var staff: String = ""
	for held: Dictionary in battle.unit(caster)["inventory"]:
		if int(held["templateId"]) == 59:
			staff = held["id"]
	return battle.summon_unit(caster, staff)


func _static_replacement(staff: Dictionary) -> bool:
	var prepared: Dictionary = M5.prepare(M5.CONTEXTS[0], _roll)
	if not _expect(prepared["ok"], "Prepare actual m5 static-pool context"):
		return false
	var opened: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m5", {"progress": prepared["progress"]}, _roll
	)
	if not _expect(opened["ok"], "Open actual m5 deployments"):
		return false
	var old: Dictionary = opened["battle"].unit(70)
	if not _expect(
		old.get("sourceId") == 46 and old.get("classId") == 24,
		"Only m5 has normalized static70/source46/class24"
	):
		return false
	var state: Dictionary = opened["battle"].snapshot()
	for actor: Dictionary in state["units"]:
		if int(actor["id"]) == 70:
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 1
		elif int(actor["id"]) == 42:
			# Controlled inventory grant from the real m8 staff. The real m5
			# class13 enemy has staff capability, but does not naturally carry59.
			actor["inventory"] = [staff.duplicate(true)]
			actor["equippedInstanceId"] = ""
	var fresh: Dictionary = Session.new().open(Matrix.CHAPTER, "m5", {"snapshot": state}, _roll)
	if not _expect(fresh["ok"], "Restore explicit m5 dead70/staff42 boundary"):
		return false
	var battle: RefCounted = fresh["battle"]
	var result: Dictionary = _enemy_summon(battle, 42)
	if not _expect(result["ok"] and result["births"][0]["unit"] == 70, "Reclaim m5 static70"):
		return false
	var advanced: Dictionary = Rounds.advance(battle)
	if not _expect(advanced["ok"] and battle.phase == 0, "Return m5 summon to stable player phase"):
		return false
	state = JSON.parse_string(JSON.stringify(battle.snapshot()))
	_draws = 0
	var restored: Dictionary = Session.new().open(Matrix.CHAPTER, "m5", {"snapshot": state}, _roll)
	if not _expect(restored["ok"], "Cold restore m5 replacement: " + str(restored.get("error"))):
		return false
	var current: Dictionary = restored["battle"].unit(70)
	return _expect(
		(
			_draws == 0
			and current["sourceId"] == 70
			and current["classId"] == 28
			and not current.has("deploymentIndex")
			and current["inventory"] == battle.unit(70)["inventory"]
			and restored["battle"].snapshot() == battle.snapshot()
		),
		"m5 restores the new summon family/items without rebuilding former46/class24"
	)


func _recycled_family(original: Dictionary) -> bool:
	var state: Dictionary = original.duplicate(true)
	var previous_item: Dictionary = {}
	for actor: Dictionary in state["units"]:
		if int(actor["id"]) == 1:
			actor["action"] = 0
			actor["level"] = 20
			actor["experience"] = 0
		elif int(actor["id"]) == 20:
			previous_item = actor["inventory"][0].duplicate(true)
			actor["inventory"] = []
			actor["equippedInstanceId"] = ""
			actor["hp"] = 0
			actor["visible"] = false
			actor["flags"] |= 1
	state["warehouse"].append(previous_item)
	var reopened: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m8", {"snapshot": state}, _birth_roll
	)
	if not _expect(
		reopened["ok"], "Restore declared corpse with its old held item now in warehouse"
	):
		return false
	var old_profile: String = reopened["content"]["profiles"][20]
	var battle: RefCounted = reopened["battle"]
	var staff: String = ""
	for held: Dictionary in battle.unit(1)["inventory"]:
		if int(held["templateId"]) == 59:
			staff = held["id"]
	_birth_draws = 0
	var result: Dictionary = battle.summon_unit(1, staff)
	if not _expect(
		(
			result["ok"]
			and int(result["births"][0]["unit"]) == 20
			and battle.unit(20)["classId"] == 37
			and battle.unit(20)["level"] == 22
		),
		"Public command recycles20 into another family and trusted level22"
	):
		return false
	var after: Dictionary = battle.snapshot()
	var projected: Dictionary = Content.new().reproject(
		reopened["content"], after["units"], after.get("cloneState", {}), after["summonState"]
	)
	if not _expect(
		projected["ok"] and projected["profiles"][20] != old_profile,
		"Runtime projection selects the new summon family"
	):
		return false
	var new_item: String = battle.unit(20)["inventory"][0]["id"]
	if not _expect(
		new_item != previous_item["id"] and after["warehouse"].has(previous_item),
		"New generation keeps opaque identity distinct from the preserved warehouse item"
	):
		return false
	_birth_draws = 0
	var cold: Dictionary = Session.new().open(
		Matrix.CHAPTER, "m8", {"snapshot": JSON.parse_string(JSON.stringify(after))}, _birth_roll
	)
	if not _expect(
		(
			cold["ok"]
			and _birth_draws == 0
			and cold["battle"].unit(20)["level"] == 22
			and cold["content"]["profiles"][20] == projected["profiles"][20]
			and cold["battle"].unit(20)["inventory"][0]["id"] == new_item
		),
		"Cold restore keeps trusted level22/new family/new held identity without RNG"
	):
		return false
	var forged: Dictionary = original.duplicate(true)
	for actor: Dictionary in forged["units"]:
		if int(actor["id"]) == 0:
			actor["level"] = 22
			actor["summoned"] = true
	return _expect(
		not Session.new().open(Matrix.CHAPTER, "m8", {"snapshot": forged}, _birth_roll)["ok"],
		"Saved summoned flag cannot grant formal actor the trusted level22 exception"
	)


func _birth_roll(_limit: int) -> int:
	_birth_draws += 1
	if _birth_draws == 1:
		return 4
	if _birth_draws == 2:
		return 8
	return 0


func _roll(_limit: int) -> int:
	_draws += 1
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
	quit(1)
