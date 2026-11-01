extends SceneTree

const Overrides = preload("res://app/chapter_texture_overrides.gd")
const Content = preload("res://app/chapter_content.gd")
const Session = preload("res://app/chapter_session.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
const ROOT: String = "res://tests/fixtures/texture_overrides/"
const SOURCE: String = ROOT + "base/source.png"
const TARGET: String = ROOT + "authored/replacement.png"
const MISMATCH: String = ROOT + "authored/mismatch.png"
const TABLE: String = ROOT + "authored/texture_overrides.json"
const ROLE_TABLE: String = ROOT + "authored/role_overrides.json"

var _directory: String = ""
var _files: Array[String] = []


class Documents:
	extends RefCounted
	var values: Dictionary = {}

	func read(path: String) -> Variant:
		if values.has(path):
			var value: Variant = values[path]
			return value.duplicate(true) if value is Dictionary or value is Array else value
		return (
			JSON.parse_string(FileAccess.get_file_as_string(path))
			if FileAccess.file_exists(path)
			else null
		)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var reader := Documents.new()
	reader.values = {
		"fixture://m0": {"battleId": "m0", "mapTexture": TARGET, "story": "fixture://story0"},
		"fixture://m2": {"battleId": "m2", "mapTexture": SOURCE, "story": "fixture://story2"},
		"fixture://story0": {},
		"fixture://story2": {}
	}
	var chapter: Dictionary = {
		"textureOverrides": TABLE, "battles": {"m0": "fixture://m0", "m2": "fixture://m2"}
	}
	var plan: Dictionary = Overrides.read_plan(chapter, {}, reader.read)
	if not _expect(
		plan["ok"] and plan["overrides"].get(SOURCE) == TARGET,
		"A source referenced only by another registered map must be valid chapter-wide"
	):
		return
	reader.values[TABLE] = {}
	if not _expect(
		(
			Overrides.read_plan({}, {}, reader.read)["overrides"].is_empty()
			and Overrides.read_plan(chapter, {}, reader.read)["overrides"].is_empty()
		),
		"Missing override configuration and an empty authored table must preserve normal loading"
	):
		return
	reader.values.erase(TABLE)
	var view: Dictionary = {
		"entry": {"mapTexture": SOURCE},
		"units": [{"sprite": SOURCE, "hp": 30}],
		"mapAnimations": {"frames": [{"texture": SOURCE}]},
		"battleArt": {"frames": [{"texture": SOURCE}]},
		"battleClips":
		{"textures": {"effect": {"texture": SOURCE}}, "clips": {"key": "res://unchanged.json"}},
		"story": {"images": {"portrait": {"texture": SOURCE}}, "text": SOURCE},
		"interface": {"textures": {"portrait": {"texture": SOURCE}}},
		"mapEffects": {"fire": {"sprite": {"frames": [{"texture": SOURCE}]}}},
		"source": SOURCE
	}
	var order: Array[int] = [9, 0]
	view["unitOrder"] = order
	var changed: Dictionary = Overrides.apply(view, plan["overrides"])
	for field: String in [
		"entry",
		"units",
		"mapAnimations",
		"battleArt",
		"battleClips",
		"story",
		"interface",
		"mapEffects"
	]:
		if not _expect(
			_has_resource(changed[field], TARGET),
			"The same PNG must be replaced in every render channel: " + field
		):
			return
	if not _expect(
		(
			view["units"][0]["sprite"] == SOURCE
			and changed["units"][0]["hp"] == 30
			and changed["source"] == SOURCE
			and changed["story"]["text"] == SOURCE
			and changed["battleClips"]["clips"]["key"] == "res://unchanged.json"
			and changed["unitOrder"].is_typed()
			and changed["unitOrder"].get_typed_builtin() == TYPE_INT
		),
		"Replacing PNG references must not mutate base data, labels, gameplay fields or clip paths"
	):
		return
	for defect: String in [
		"inline",
		"missing_table",
		"unknown",
		"source_non_png",
		"non_png",
		"outside",
		"traversal",
		"missing_source",
		"missing_target",
		"size"
	]:
		var candidate: Dictionary = chapter.duplicate(true)
		reader.values.erase(TABLE)
		reader.values["fixture://m2"]["mapTexture"] = SOURCE
		match defect:
			"inline":
				candidate["textureOverrides"] = {SOURCE: TARGET}
			"missing_table":
				candidate["textureOverrides"] = ROOT + "authored/missing.json"
			"unknown":
				reader.values[TABLE] = {MISMATCH: TARGET}
			"source_non_png":
				reader.values[TABLE] = {TABLE: TARGET}
			"non_png":
				reader.values[TABLE] = {SOURCE: ROOT + "authored/not_a_png.json"}
			"outside":
				reader.values[TABLE] = {SOURCE: SOURCE}
			"traversal":
				reader.values[TABLE] = {SOURCE: ROOT + "authored/../base/source.png"}
			"missing_source":
				var missing: String = ROOT + "base/missing.png"
				reader.values[TABLE] = {missing: TARGET}
				reader.values["fixture://m2"]["mapTexture"] = missing
			"missing_target":
				reader.values[TABLE] = {SOURCE: ROOT + "authored/missing.png"}
			"size":
				reader.values[TABLE] = {SOURCE: MISMATCH}
		if not _expect(
			not Overrides.read_plan(candidate, {}, reader.read)["ok"],
			"Invalid texture replacement must reject: " + defect
		):
			return
	reader.values.erase(TABLE)
	reader.values["fixture://m2"]["mapTexture"] = TARGET
	if not _expect(
		not Overrides.read_plan(chapter, {"source": SOURCE}, reader.read)["ok"],
		"Source labels do not count as image references"
	):
		return
	if not _expect(
		Overrides.read_plan(chapter, {"texture": SOURCE}, reader.read)["ok"],
		"Unselected library images remain chapter references"
	):
		return
	if not _expect(
		_actual_content(),
		"The actual content boundary must preserve base data and reapply PNG replacements"
	):
		return
	if not _cleanup():
		quit(1)
		return
	print(
		"PASS texture overrides: full chapter refs, every render channel, real PNG sizes and reproject"
	)
	quit(0)


func _actual_content() -> bool:
	var reader := Documents.new()
	var chapter: Dictionary = reader.read(CHAPTER)
	var role_table: Dictionary = reader.read(ROLE_TABLE)
	var role_source: String = role_table.keys()[0]
	var baseline: Dictionary = Content.new().load_chapter(CHAPTER)
	if not _expect(baseline["ok"], "The original chapter must still load"):
		return false
	var candidate: String = (
		"user://texture_override_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	if DirAccess.dir_exists_absolute(candidate) or FileAccess.file_exists(candidate):
		return false
	if DirAccess.make_dir_absolute(candidate) != OK:
		return false
	_directory = candidate
	var chapter_path: String = _directory.path_join("chapter.json")
	_files.append(chapter_path)
	chapter["textureOverrides"] = ROLE_TABLE
	if not _write(chapter_path, chapter):
		return false
	var opened: Dictionary = Session.new().open(
		chapter_path, "", {"new": true}, func(_limit: int) -> int: return 0
	)
	if not _expect(
		opened["ok"],
		"A real Session must open with the authored PNG table: " + str(opened.get("error", ""))
	):
		return false
	var content: Dictionary = opened["content"]
	var actor: Dictionary = opened["battle"].unit(0)
	if not _expect(
		(
			actor["sprite"] == TARGET
			and _has_resource(content["mapAnimations"]["units"]["0"], TARGET.trim_prefix("res://"))
		),
		"Absolute unit sprites and relative map frames must both use the authored replacement"
	):
		return false
	var again: Dictionary = Content.new().reproject(content, opened["battle"].snapshot()["units"])
	if not _expect(
		(
			again["ok"]
			and (
				again["units"].filter(func(unit: Dictionary) -> bool: return unit["id"] == 0)[0]["sprite"]
				== TARGET
			)
			and (
				again["_library"]["profiles"]["source_0_job_0_faction_0"]["unit"]["sprite"]
				== role_source
			)
			and again["_baseEntry"]["mapTexture"] == baseline["entry"]["mapTexture"]
		),
		"Reprojection must start from unmodified chapter sources and apply the same table once"
	):
		return false
	var original: Dictionary = Content.new().load_chapter(CHAPTER)
	if not _expect(
		(
			original["ok"]
			and (
				original["units"].filter(func(unit: Dictionary) -> bool: return unit["id"] == 0)[0]["sprite"]
				== role_source
			)
		),
		"An override must not leak into the original chapter's independent views"
	):
		return false
	var other: Dictionary = reader.read(chapter["battles"]["m2"])
	other["mapTexture"] = SOURCE
	var other_path: String = _directory.path_join("other_battle.json")
	_files.append(other_path)
	chapter["battles"]["m2"] = other_path
	chapter["textureOverrides"] = TABLE
	if not _write(other_path, other) or not _write(chapter_path, chapter):
		return false
	var first_map: Dictionary = Content.new().load_chapter(chapter_path)
	return (
		first_map["ok"]
		and first_map["entry"]["mapTexture"] == baseline["entry"]["mapTexture"]
		and first_map["_textureOverrides"].get(SOURCE) == TARGET
	)


func _has_resource(value: Variant, path: String) -> bool:
	if value is Dictionary:
		for key: Variant in value:
			if (
				key in ["texture", "sprite", "mapTexture"]
				and value[key] is String
				and value[key] == path
			):
				return true
			if _has_resource(value[key], path):
				return true
	elif value is Array:
		for item: Variant in value:
			if _has_resource(item, path):
				return true
	return false


func _write(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	var written: Error = file.get_error()
	file.close()
	return written == OK


func _cleanup() -> bool:
	var success: bool = true
	for path: String in _files:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
			success = false
	if not _directory.is_empty():
		if DirAccess.remove_absolute(_directory) != OK:
			success = false
		_directory = ""
	return success


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		_cleanup()
		quit(1)
	return condition
