extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Store = preload("res://persistence/battle_store.gd")
const M9 = preload("res://tests/test_m9_content.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _draws: int = 0


func _initialize() -> void:
	var entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHAPTER))
	var definition: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(entry["battles"][entry["firstBattle"]])
	)
	var supplied_path: String = "user://already-read-chapter.json"
	var documents: Dictionary = {
		supplied_path: entry, entry["battles"][entry["firstBattle"]]: definition
	}
	for path: String in [entry["library"], definition["deployments"], definition["story"]]:
		documents[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	var originals: Dictionary = documents.duplicate(true)
	var supplied: Dictionary = Content.new().load_chapter(supplied_path, "", {}, documents)
	if not _expect(
		supplied["ok"] and documents == originals,
		"Already-read definitions must load without reopening their entry or mutating source documents"
	):
		return
	var session := Session.new()
	var first: Dictionary = session.open(CHAPTER, "", {"new": true}, _roll)
	if not _expect(first["ok"], "New game must open the chapter's configured first battle"):
		return
	var original: Dictionary = first["battle"].snapshot()
	if not _expect(_draws > 0, "New game must draw initial results through the supplied source"):
		return
	_draws = 0
	var restored: Dictionary = session.open(CHAPTER, "m0", {"snapshot": original}, _roll)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == original,
		"Snapshot opening must restore all existing results without initial random draws"
	):
		return
	var first_battle: RefCounted = first["battle"]
	first_battle.win_with_assistance()
	var progress: Dictionary = first_battle.complete_victory(0)["progress"]
	progress["party"].reverse()
	var preserved: Dictionary = progress.duplicate(true)
	var second: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _roll)
	if not _expect(second["ok"] and progress == preserved, "World entry must preserve its input"):
		return
	if not _expect(
		(
			second["battle"].unit(0)["x"] == 1
			and second["battle"].unit(0)["y"] == 15
			and second["battle"].unit(9)["x"] == 0
			and second["battle"].unit(9)["y"] == 15
		),
		"Recruit order, rather than the party array order, must determine m1's deployment slots"
	):
		return
	var saved: Dictionary = Store.new(first["content"]).encode(second["battle"])
	if not _expect(saved["ok"], "The chapter store must encode the actual second-battle identity"):
		return
	_draws = 0
	var reopened: Dictionary = Store.new(first["content"]).decode(saved["record"], _roll)
	if not _expect(
		(
			reopened["ok"]
			and _draws == 0
			and reopened["battle"].snapshot() == second["battle"].snapshot()
		),
		"Continue decoding must bind the actual roster and avoid initializing a replacement battle"
	):
		return
	var old_battle: Dictionary = saved["record"].duplicate(true)
	old_battle["state"].erase("chapterStats")
	var old_read: Dictionary = Store.new(first["content"]).decode(
		JSON.parse_string(JSON.stringify(old_battle)), _roll
	)
	if not _expect(
		(
			old_read["ok"]
			and (
				old_read["battle"].snapshot()["chapterStats"]
				== {"rounds": null, "playerRetirements": null, "allyRetirements": null}
			)
		),
		"Legacy battle snapshots preserve unknown cumulative history through Store and Session"
	):
		return
	var completed: Dictionary = session.completed_content(CHAPTER, progress)
	if not _expect(
		(
			completed["ok"]
			and completed["content"]["entry"]["battleId"] == "m0"
			and completed["content"]["story"]["battleNumber"] == 1
			and second["content"]["story"]["battleNumber"] == 2
		),
		"A completed world record and its next battle must use different world-step contexts"
	):
		return
	var legacy: Dictionary = progress.duplicate(true)
	legacy.erase("chapterStats")
	var legacy_encoded: Dictionary = Store.new(first["content"]).encode_progress(legacy)
	if not _expect(legacy_encoded["ok"], "Legacy world progress must remain readable"):
		return
	var legacy_read: Dictionary = Store.new(first["content"]).decode(
		JSON.parse_string(JSON.stringify(legacy_encoded["record"]))
	)
	if not _expect(
		(
			legacy_read["ok"]
			and (
				legacy_read["progress"].get("chapterStats")
				== {"rounds": null, "playerRetirements": null, "allyRetirements": null}
			)
		),
		"Legacy world records must retain unknown cumulative statistics through real JSON"
	):
		return
	for invalid_stats: Variant in [
		null,
		{},
		{"rounds": 1},
		{"rounds": 0, "playerRetirements": 0, "allyRetirements": 0},
		{"rounds": 1, "playerRetirements": -1, "allyRetirements": 0}
	]:
		var invalid: Dictionary = progress.duplicate(true)
		invalid["chapterStats"] = invalid_stats
		if not _expect(
			not Store.new(first["content"]).encode_progress(invalid)["ok"],
			"Present chapter statistics must be complete and valid rather than becoming legacy unknown"
		):
			return
	var malformed: Dictionary = progress.duplicate(true)
	malformed["gold"] = -1
	var before: Dictionary = malformed.duplicate(true)
	if not _expect(
		not session.open(CHAPTER, "m1", {"progress": malformed})["ok"] and malformed == before,
		"Invalid inherited business state must fail without publishing or mutating its source"
	):
		return
	for source: Dictionary in [{}, {"new": true, "progress": progress}, {"new": false}]:
		if not _expect(
			not session.open(CHAPTER, "", source)["ok"], "Opening sources are exclusive"
		):
			return
	print(
		"PASS chapter session: new/world/snapshot entry, roster order, zero-draw restore and isolation"
	)
	quit(0)


# The earlier route is an explicit m9 fixture; both settlements use the real rules.
# This does not claim naturally playing all preceding battles.
static func prepare_terminal(route: int, roll: Callable) -> Dictionary:
	if route not in [4, 7]:
		return {"ok": false, "error": "UNSUPPORTED_TERMINAL_ROUTE"}
	var context: Dictionary = M9.CONTEXTS[0 if route == 4 else 3]
	var prepared: Dictionary = M9.prepare(context, roll)
	if not prepared["ok"]:
		return prepared
	var prior: Dictionary = Session.new().open(CHAPTER, "m9", prepared["source"], roll)
	if not prior["ok"]:
		return prior
	var won: Dictionary = prior["battle"].win_with_assistance()
	if not won["ok"]:
		return won
	var completed: Dictionary = prior["battle"].complete_victory(route)
	if not completed["ok"]:
		return completed
	var progress: Dictionary = completed["progress"]
	progress["commandPolicy"] = 5
	var opened: Dictionary = Session.new().open(CHAPTER, "m13", {"progress": progress}, roll)
	if opened["ok"]:
		opened["previousContent"] = prior["content"]
		opened["sourceProgress"] = progress
	return opened


func _terminal_routes(indices: Array) -> bool:
	for index: int in indices:
		var route: int = 4 if index == 0 else 7
		var opened: Dictionary = prepare_terminal(route, _roll)
		if not _expect(
			opened["ok"], "Actual m9 settlement enters m13: " + str(opened.get("error"))
		):
			return false
		var battle: RefCounted = opened["battle"]
		var save_path: String = "user://m13_session_%d_%d.json" % [Time.get_ticks_usec(), index]
		var store: RefCounted = Store.new(opened["content"], save_path)
		if not _expect(
			battle.snapshot()["commander"] == -1 and battle.snapshot()["commandPolicy"] == 5,
			"None commander mode clears selection while retaining the valid command policy"
		):
			return false
		var encoded: Dictionary = store.encode(battle)
		if not _expect(encoded["ok"], "None commander battle can be encoded"):
			return false
		_draws = 0
		var cold: Dictionary = Store.new(opened["previousContent"]).decode(
			JSON.parse_string(JSON.stringify(encoded["record"])), _roll
		)
		if not _expect(
			cold["ok"] and _draws == 0 and cold["battle"].snapshot() == battle.snapshot(),
			"Fresh Store and Session restore all m13 state from JSON without rerolling"
		):
			return false
		battle.win_with_assistance()
		var completed: Dictionary = battle.complete_victory(route)
		if not _expect(completed["ok"], "m13 produces a committed completion candidate"):
			return false
		var finished: Dictionary = completed["progress"]
		var saved: Dictionary = store.encode_progress(finished)
		if not _expect(saved["ok"], "Terminal progress and result can be encoded"):
			return false
		cold = Store.new(opened["previousContent"]).decode(
			JSON.parse_string(JSON.stringify(saved["record"]))
		)
		if not _expect(
			(
				cold["ok"]
				and cold["progress"] == finished
				and finished["chapterCompleted"]
				and finished["worldStep"] == 10
				and finished["commander"] == -1
			),
			"Both terminal routes retain exact completion/result/statistics through cold JSON"
		):
			return false
		if not _expect(
			(
				Session.new().open(CHAPTER, "m13", {"progress": cold["progress"]}).get("error")
				== "CHAPTER_ALREADY_COMPLETED"
			),
			"Completed progress rejects another battle entry without indexing beyond the route"
		):
			return false
		for field: String in ["chapterCompleted", "chapterResult"]:
			var invalid: Dictionary = finished.duplicate(true)
			invalid.erase(field)
			if not _expect(
				not store.encode_progress(invalid)["ok"],
				"Terminal records require completion and result together"
			):
				return false
		for step: int in [9, 11]:
			var invalid: Dictionary = finished.duplicate(true)
			invalid["worldStep"] = step
			if not _expect(
				not store.encode_progress(invalid)["ok"], "Completion must exactly match route size"
			):
				return false
		for invalid_result: Variant in [null, {}, finished["chapterResult"].duplicate(true)]:
			if invalid_result is Dictionary and invalid_result.has("totalPower"):
				invalid_result["totalPower"] += 1
			var invalid: Dictionary = finished.duplicate(true)
			invalid["chapterResult"] = invalid_result
			if not _expect(
				not store.encode_progress(invalid)["ok"],
				"Malformed or inconsistent completion snapshots cannot be silently dropped"
			):
				return false
		if not _expect(
			store.write_progress(finished)["ok"], "Continue writes terminal world state"
		):
			return false
		var continue_bytes: String = FileAccess.get_file_as_string(save_path)
		for slot: int in range(4):
			var variant: Dictionary = finished.duplicate(true)
			variant["gold"] += slot
			variant["elapsedMinutes"] = 120 + slot
			if not _expect(
				store.write_slot(slot, variant)["ok"], "All four named slots accept completion"
			):
				return false
		for slot: int in range(4):
			var read: Dictionary = Store.new(opened["previousContent"], save_path).read_slot(slot)
			if not _expect(
				(
					read["ok"]
					and read["progress"]["chapterCompleted"]
					and read["progress"]["gold"] == finished["gold"] + slot
					and read["progress"]["elapsedMinutes"] == 120 + slot
					and read["progress"]["chapterResult"] == finished["chapterResult"]
				),
				"Cold named slots isolate current funds/time while retaining the original completion result"
			):
				return false
			DirAccess.remove_absolute(save_path.get_basename() + "_slot_%d.json" % (slot + 1))
		if not _expect(
			FileAccess.get_file_as_string(save_path) == continue_bytes,
			"Four completion slots preserve the continue record byte-for-byte"
		):
			return false
		DirAccess.remove_absolute(save_path)
	return true


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
