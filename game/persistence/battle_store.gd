extends RefCounted

const Inventory = preload("res://gameplay/unit_inventory.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const Session = preload("res://app/chapter_session.gd")
const Deployment = preload("res://app/chapter_deployment.gd")
const Statistics = preload("res://gameplay/chapter_statistics.gd")
const SLOT_COUNT: int = 4
var path: String
var _content: Dictionary


func _init(content: Dictionary, save_path: String = "user://battle_save.json") -> void:
	_content = content
	path = save_path


func has_save() -> bool:
	return FileAccess.file_exists(path)


func has_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT and FileAccess.file_exists(_slot_path(slot))


func read_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT:
		return {"ok": false, "error": "INVALID_SAVE_SLOT"}
	var result: Dictionary = _read_record(_slot_path(slot))
	if result["ok"] and not result.has("progress"):
		return {"ok": false, "error": "INVALID_WORLD_SAVE"}
	return result


func write_slot(slot: int, progress: Dictionary) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT:
		return {"ok": false, "error": "INVALID_SAVE_SLOT"}
	var encoded: Dictionary = encode_progress(progress)
	if not encoded["ok"]:
		return encoded
	return _write_record(encoded["record"], _slot_path(slot))


func _slot_path(slot: int) -> String:
	var extension: String = path.get_extension()
	return path.get_basename() + "_slot_%d" % (slot + 1) + ("." + extension if extension else "")


func write(battle: RefCounted, elapsed_minutes: int = -1) -> Dictionary:
	var encoded: Dictionary = encode(battle, elapsed_minutes)
	if not encoded["ok"]:
		return encoded
	return _write_record(encoded["record"], path)


func write_progress(progress: Dictionary) -> Dictionary:
	var encoded: Dictionary = encode_progress(progress)
	if not encoded["ok"]:
		return encoded
	return _write_record(encoded["record"], path)


func _write_record(record: Dictionary, save_path: String) -> Dictionary:
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入临时战局: " + error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(record))
	file.flush()
	var written: Error = file.get_error()
	file.close()
	if written != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": "战局写入失败: " + error_string(written)}
	var replaced: Error = DirAccess.rename_absolute(temporary, save_path)
	if replaced != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": "无法替换战局，原记录保留: " + error_string(replaced)}
	return {"ok": true}


func read() -> Dictionary:
	return _read_record(path)


func _read_record(save_path: String) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {"ok": false, "missing": true, "error": "NO_SAVE"}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "战局读取失败: " + error_string(FileAccess.get_open_error())}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "战局文件损坏"}
	return decode(parser.data)


func encode(battle: RefCounted, elapsed_minutes: int = -1) -> Dictionary:
	if not battle.can_save():
		return {"ok": false, "error": "BATTLE_NOT_STABLE"}
	if elapsed_minutes < -1 or elapsed_minutes > 2147483647:
		return {"ok": false, "error": "INVALID_SAVE_TIME"}
	var record: Dictionary = {
		"version": 1,
		"chapterId": _content["entry"]["id"],
		"battleId": battle.battle_id,
		"state": battle.snapshot()
	}
	if elapsed_minutes >= 0:
		record["elapsedMinutes"] = elapsed_minutes
	var validated: Dictionary = decode(record)
	if not validated["ok"]:
		return validated
	return {"ok": true, "record": record}


func decode(record: Dictionary, random_source: Callable = Callable()) -> Dictionary:
	var version: Variant = record.get("version")
	if (
		not (version is int or version is float)
		or not is_finite(float(version))
		or float(version) != 1.0
	):
		return {"ok": false, "error": "UNSUPPORTED_SAVE_VERSION"}
	if (
		not record.get("chapterId") is String
		or not record.get("battleId") is String
		or record["chapterId"] != _content["entry"]["id"]
	):
		return {"ok": false, "error": "SAVE_CONTENT_MISMATCH"}
	if record.has("progress"):
		if (
			record.has("state")
			or record.has("elapsedMinutes")
			or not record["progress"] is Dictionary
			or record["progress"].get("completedBattle") != record["battleId"]
		):
			return {"ok": false, "error": "INVALID_SAVE_PROGRESS"}
		return _decode_progress(record["progress"])
	if not record.get("state") is Dictionary:
		return {"ok": false, "error": "INVALID_SAVE_STATE"}
	if record.has("elapsedMinutes") and not _minutes_valid(record["elapsedMinutes"]):
		return {"ok": false, "error": "INVALID_SAVE_TIME"}
	var result: Dictionary = Session.new().open(
		_content["entry"]["chapterPath"],
		record["battleId"],
		{"snapshot": record["state"]},
		random_source
	)
	if not result["ok"]:
		return result
	if record.has("elapsedMinutes"):
		result["elapsedMinutes"] = int(record["elapsedMinutes"])
	return result


func encode_progress(progress: Dictionary) -> Dictionary:
	var decoded: Dictionary = _decode_progress(progress)
	if not decoded["ok"]:
		return decoded
	return {
		"ok": true,
		"record":
		{
			"version": 1,
			"chapterId": _content["entry"]["id"],
			"battleId": decoded["progress"]["completedBattle"],
			"progress": decoded["progress"]
		}
	}


func _decode_progress(value: Dictionary) -> Dictionary:
	if not value.get("completedBattle") is String:
		return {"ok": false, "error": "SAVE_PROGRESS_CONTENT_MISMATCH"}
	var resolved: Dictionary = Session.new().completed_content(
		_content["entry"]["chapterPath"], value
	)
	if not resolved["ok"]:
		return resolved
	var content: Dictionary = resolved["content"]
	if value.has("elapsedMinutes") and not _minutes_valid(value["elapsedMinutes"]):
		return {"ok": false, "error": "INVALID_SAVE_TIME"}
	if value.has("levelTutorialSeen") and not value["levelTutorialSeen"] is bool:
		return {"ok": false, "error": "INVALID_SAVE_TUTORIAL_STATE"}
	if (
		value.get("chapterId") != _content["entry"]["id"]
		or not _integer(value.get("worldNode"))
		or value["worldNode"] != content["story"].get("worldNode", 0)
	):
		return {"ok": false, "error": "SAVE_PROGRESS_CONTENT_MISMATCH"}
	if (
		not _integer(value.get("gold"))
		or value["gold"] < 0
		or value["gold"] > Battle.MAX_GOLD
		or not _integer(value.get("route"))
		or not _integer(value.get("commander"))
		or not _integer(value.get("commandPolicy"))
		or int(value["commandPolicy"]) not in [0, 1, 4, 5]
	):
		return {"ok": false, "error": "INVALID_SAVE_PROGRESS"}
	var chapter_completed: bool = value.get("chapterCompleted", false)
	var route_valid: bool = chapter_completed
	if not chapter_completed:
		for choice: Dictionary in content["story"]["routeChoices"]:
			if choice["routeIndex"] == value["route"]:
				route_valid = true
	if (
		not route_valid
		or not value.get("party") is Array
		or not value.get("warehouse") is Array
		or value["warehouse"].size() > Inventory.WAREHOUSE_CAPACITY
	):
		return {"ok": false, "error": "INVALID_SAVE_PROGRESS"}
	var world_step: Variant = value.get(
		"worldStep", 1 if value["completedBattle"] == _content["entry"]["firstBattle"] else null
	)
	var routes: Array = content["story"]["world"]["routes"]
	if not _integer(world_step) or world_step < 1 or value["route"] >= routes.size():
		return {"ok": false, "error": "INVALID_SAVE_WORLD_STEP"}
	var route: Array = routes[int(value["route"])]
	if (
		world_step > route.size()
		or (not chapter_completed and world_step == route.size())
		or route[int(world_step) - 1] != value["worldNode"]
	):
		return {"ok": false, "error": "INVALID_SAVE_WORLD_STEP"}
	if value.has("worldLocation"):
		if not _integer(value["worldLocation"]):
			return {"ok": false, "error": "INVALID_SAVE_WORLD_LOCATION"}
		var visited: Array = route.slice(0, int(world_step))
		if not visited.any(func(id: Variant) -> bool: return id == value["worldLocation"]):
			return {"ok": false, "error": "INVALID_SAVE_WORLD_LOCATION"}
	var expected: Dictionary = {}
	for unit: Dictionary in content["units"]:
		if unit["formal"]:
			expected[int(unit["id"])] = true
	var no_commander: bool = (
		content["story"].get("commanderMode", "selection") == "none"
		and int(value["commander"]) == -1
	)
	if (
		value["party"].size() != expected.size()
		or (not no_commander and not expected.has(int(value["commander"])))
	):
		return {"ok": false, "error": "INVALID_SAVE_PARTY"}
	var combat: RefCounted = load("res://gameplay/combat_rules.gd").new(
		content["rules"], content["map"]["terrain"]
	)
	var decoder: RefCounted = load("res://gameplay/unit_record.gd").new(content, combat)
	var held_ids: Dictionary = {}
	var party_by_id: Dictionary = {}
	for raw: Variant in value["party"]:
		if not raw is Dictionary:
			return {"ok": false, "error": "INVALID_SAVE_PARTY"}
		var decoded: Dictionary = decoder.decode(raw, held_ids)
		if not decoded["ok"]:
			return decoded
		var unit: Dictionary = decoded["unit"]
		if (
			not expected.has(unit["id"])
			or not unit["formal"]
			or not unit["visible"]
			or unit["hp"] != unit["maxHp"]
			or unit["flags"] != 0
			or unit["action"] != 0
		):
			return {"ok": false, "error": "INVALID_SAVE_PARTY"}
		expected.erase(unit["id"])
		party_by_id[int(unit["id"])] = unit
	var warehouse: Array = value["warehouse"].duplicate(true)
	if not decoder.validate_inventory(warehouse, held_ids):
		return {"ok": false, "error": "INVALID_SAVE_WAREHOUSE"}
	var party: Array[Dictionary] = []
	for id: int in Deployment.recruit_order(
		route, content["entry"]["recruitByNode"], int(world_step), content["entry"]["initialParty"]
	):
		if not party_by_id.has(id):
			return {"ok": false, "error": "INVALID_SAVE_PARTY"}
		party.append(party_by_id[id])
	if value.has("chapterStats") and value["chapterStats"] == null:
		return {"ok": false, "error": "INVALID_CHAPTER_STATS"}
	var statistics: Dictionary = Statistics.decode(value.get("chapterStats"))
	if not statistics["ok"]:
		return statistics
	if value.has("chapterResult") != chapter_completed:
		return {"ok": false, "error": "INVALID_CHAPTER_RESULT"}
	if (
		value.has("chapterResultHistorical")
		and (not value["chapterResultHistorical"] is bool or not chapter_completed)
	):
		return {"ok": false, "error": "INVALID_CHAPTER_RESULT"}
	var result: Dictionary = {}
	if value.has("chapterResult"):
		result = Statistics.validate_result(
			value["chapterResult"],
			party,
			statistics["stats"],
			value.get("chapterResultHistorical", false)
		)
		if not result["ok"]:
			return result
	var progress: Dictionary = {
		"chapterId": _content["entry"]["id"],
		"completedBattle": value["completedBattle"],
		"worldNode": int(value["worldNode"]),
		"worldStep": int(world_step),
		"route": int(value["route"]),
		"gold": int(value["gold"]),
		"commander": int(value["commander"]),
		"commandPolicy": int(value["commandPolicy"]),
		"party": party,
		"warehouse": warehouse,
		"chapterStats": statistics["stats"]
	}
	if value.has("chapterCompleted"):
		progress["chapterCompleted"] = chapter_completed
	if value.has("chapterResult"):
		progress["chapterResult"] = result["result"]
	if value.get("chapterResultHistorical", false):
		progress["chapterResultHistorical"] = true
	if value.has("elapsedMinutes"):
		progress["elapsedMinutes"] = int(value["elapsedMinutes"])
	if value.has("worldLocation"):
		progress["worldLocation"] = int(value["worldLocation"])
	if value.has("levelTutorialSeen"):
		progress["levelTutorialSeen"] = value["levelTutorialSeen"]
	return {"ok": true, "progress": progress, "content": content}


func _minutes_valid(value: Variant) -> bool:
	return _integer(value) and value >= 0 and value <= 2147483647


func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
	)
