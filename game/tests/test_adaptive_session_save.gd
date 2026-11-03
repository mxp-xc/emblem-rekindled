extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _directory: String = ""
var _draws: int = 0


func _initialize() -> void:
	var candidate: String = "user://adaptive_session_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(candidate) or DirAccess.make_dir_absolute(candidate) != OK:
		fail("Cannot claim a fresh fixture directory")
		return
	_directory = candidate
	var chapter: Dictionary = _json(CHAPTER)
	var definition: Dictionary = _json(chapter["battles"]["m0"])
	var records: Array = _json(definition["deployments"])
	var library: Dictionary = _json(chapter["library"])
	var rules: Dictionary = _json(chapter["rules"])
	for record: Dictionary in records:
		if record["kind"] != 1 or record["faction"] == 0 or int(record["classId"]) % 4 != 0:
			continue
		var source: int = int(record["sourceId"])
		var faction: int = int(record["faction"])
		var base: int = int(record["classId"])
		var old_key: String = "source_%d_job_%d_faction_%d" % [source, base, faction]
		var new_key: String = "source_%d_job_%d_faction_%d" % [source, base + 1, faction]
		var profile: Dictionary = library["profiles"][definition["profiles"][old_key]].duplicate(
			true
		)
		profile["unit"]["classId"] = base + 1
		for job: Dictionary in rules["jobTemplates"]:
			if job["id"] == base + 1:
				profile["unit"]["classGroup"] = job["classGroup"]
				profile["unit"]["equipMask"] = job["equipMask"]
				break
		library["profiles"][new_key] = profile
		definition["profiles"][new_key] = new_key
	chapter["library"] = _directory.path_join("library.json")
	chapter["battles"]["m0"] = _directory.path_join("battle.json")
	for row: Array in [
		[chapter["library"], library],
		[chapter["battles"]["m0"], definition],
		[_directory.path_join("chapter.json"), chapter]
	]:
		var file := FileAccess.open(row[0], FileAccess.WRITE)
		if file == null:
			fail("Cannot write an owned synthetic profile fixture")
			return
		file.store_string(JSON.stringify(row[1]))
	var context: Dictionary = {
		"attributes": {"strength": 0, "skill": 0, "speed": 0, "defense": 0, "magic": 0, "luck": 0},
		"maxHp": 0,
		"maxInternalLevel": 9,
		"averageInternalLevel": 9,
		"maxProficiency": 0
	}
	var opened: Dictionary = Session.new().open(
		_directory.path_join("chapter.json"), "m0", {"new": true}, _zero, context
	)
	if not opened["ok"]:
		fail("Open selected classes through Session: " + str(opened))
		return
	for pair: Array in [[10, 9], [67, 13], [66, 5], [65, 9]]:
		var unit: Dictionary = opened["battle"].unit(pair[0])
		if unit["level"] != 10 or unit["classId"] != pair[1]:
			fail(
				"Selected class and level must match the original same-process probe: " + str(pair)
			)
			return
	var store: RefCounted = Store.new(opened["content"], _directory.path_join("record.json"))
	var encoded: Dictionary = store.encode(opened["battle"])
	if not encoded["ok"]:
		fail("Encode selected classes through Store: " + str(encoded))
		return
	_draws = 0
	var record: Dictionary = JSON.parse_string(JSON.stringify(encoded["record"]))
	var restored: Dictionary = store.decode(record, _zero)
	if (
		not restored["ok"]
		or _draws != 0
		or restored["battle"].snapshot() != opened["battle"].snapshot()
	):
		fail(
			(
				"Cold JSON restore must preserve selected classes without random draws: "
				+ str(restored)
			)
		)
		return
	for actor: Dictionary in record["state"]["units"]:
		if actor["id"] == 67:
			actor["classId"] = 14
			break
	if store.decode(record, _zero)["ok"]:
		fail("Saved class outside the declared base/tier pair must be rejected")
		return
	_cleanup()
	print("PASS adaptive Session/Store: m0 selected levels, trusted profiles and cold restore")
	quit(0)


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _zero(_limit: int) -> int:
	_draws += 1
	return 0


func _cleanup() -> void:
	if not _directory.is_empty() and DirAccess.dir_exists_absolute(_directory):
		for name: String in DirAccess.get_files_at(_directory):
			DirAccess.remove_absolute(_directory.path_join(name))
		DirAccess.remove_absolute(_directory)


func fail(message: String) -> void:
	_cleanup()
	push_error(message)
	quit(1)
