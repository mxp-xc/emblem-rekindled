extends SceneTree


func _initialize() -> void:
	var script: Script = load("res://gameplay/chapter_statistics.gd")
	if script == null:
		fail("Chapter statistics must expose the shared save and result contract")
		return
	var stats: Dictionary = script.fresh()
	if stats != {"rounds": 1, "playerRetirements": 0, "allyRetirements": 0}:
		fail("A new chapter starts at one round without retirements")
		return
	for value: Variant in [
		false, {}, {"rounds": 1}, {"rounds": 1.5, "playerRetirements": 0, "allyRetirements": 0}
	]:
		if script.decode(value)["ok"]:
			fail("Malformed statistics cannot become known zero history")
			return
	var legacy: Dictionary = script.decode(null)["stats"]
	script.increment(legacy, "rounds")
	if (
		legacy != script.unknown()
		or script.rating(legacy, 4000) != ""
		or script.rating(legacy, 4001) != "SSS"
	):
		fail("Unknown history persists, with only the exact high-power SSS shortcut")
		return
	for sample: Array in [
		[0, 3, 200, 0, "SSS"],
		[0, 4, 200, 0, "S"],
		[0, 3, 201, 0, "S"],
		[2, 7, 220, 0, "S"],
		[3, 7, 220, 0, "A"],
		[2, 8, 220, 0, "A"],
		[2, 7, 221, 0, "A"],
		[5, 11, 240, 0, "A"],
		[6, 11, 240, 0, "B"],
		[5, 12, 240, 0, "B"],
		[5, 11, 241, 0, "B"],
		[8, 15, 300, 0, "B"],
		[9, 15, 300, 0, "C"],
		[8, 16, 300, 0, "C"],
		[8, 15, 301, 0, "C"],
		[9, 16, 301, 3000, "C"],
		[9, 16, 301, 3001, "S"],
		[9, 16, 301, 4000, "S"],
		[9, 16, 301, 4001, "SSS"]
	]:
		stats = {"playerRetirements": sample[0], "allyRetirements": sample[1], "rounds": sample[2]}
		if script.rating(stats, sample[3]) != sample[4]:
			fail("Rating must preserve threshold equality and priority")
			return
	stats = script.fresh()
	var result: Dictionary = {
		"party": [{"id": 0, "level": 1, "power": 84}, {"id": 9, "level": 2, "power": 100}],
		"gold": 6000,
		"totalPower": 184,
		"chapterStats": stats.duplicate()
	}
	var party: Array = [{"id": 9, "level": 2}, {"id": 0, "level": 1}]
	if not script.validate_result(result, party, stats)["ok"]:
		fail("The four-field result snapshot validates independently of recruit order")
		return
	for key: String in ["party", "gold", "totalPower", "chapterStats"]:
		var missing: Dictionary = result.duplicate(true)
		missing.erase(key)
		if script.validate_result(missing, party, stats)["ok"]:
			fail("Every result field is required")
			return
	var invalid: Dictionary = result.duplicate(true)
	invalid["party"].reverse()
	if script.validate_result(invalid, party, stats)["ok"]:
		fail("Result members are displayed in ascending original identity order")
		return
	invalid = result.duplicate(true)
	invalid["totalPower"] = 185
	if script.validate_result(invalid, party, stats)["ok"]:
		fail("The result total must equal the saved member powers")
		return
	var later_party: Array = [{"id": 9, "level": 3}, {"id": 0, "level": 1}]
	var later_stats: Dictionary = {"rounds": 2, "playerRetirements": 0, "allyRetirements": 0}
	if (
		script.validate_result(result, later_party, later_stats)["ok"]
		or not script.validate_result(result, later_party, later_stats, true)["ok"]
		or script.validate_result(invalid, later_party, later_stats, true)["ok"]
	):
		fail(
			"A historical chapter result keeps its original levels and counters but must remain valid"
		)
		return
	stats = {"rounds": 2147483647, "playerRetirements": null, "allyRetirements": 66}
	script.increment(stats, "rounds")
	if stats["rounds"] != 2147483647 or script.command_ability(stats) != 0:
		fail("Modern statistics saturate and command ability cannot become negative")
		return
	print("PASS chapter statistics: history validation, unknowns, rating thresholds, saturation")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
