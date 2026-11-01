extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var library: Script = load("res://app/battle_clip_library.gd")
	var directory: String = content["entry"]["resourceDirectory"]
	var cases: Array[Dictionary] = []
	var broken: Dictionary = content["battleArt"].duplicate(true)
	broken["terrainBackgrounds"].erase("0")
	cases.append(broken)
	broken = content["battleArt"].duplicate(true)
	broken["appearances"]["0:9"]["frames"][0]["texture"] = "missing.png"
	cases.append(broken)
	broken = content["battleArt"].duplicate(true)
	broken["appearances"]["0:9"]["frames"][0].erase("offsetX")
	cases.append(broken)
	broken = content["battleArt"].duplicate(true)
	broken["appearances"]["0:9"]["nativeSide"] = -1
	cases.append(broken)
	broken = content["battleArt"].duplicate(true)
	var background: String = broken["terrainBackgrounds"]["0"]
	broken["backgrounds"][background]["frames"].resize(2)
	cases.append(broken)
	for index: int in range(cases.size()):
		if library.validate_art(cases[index], directory, content["map"]["terrain"]):
			fail("Invalid battle art must be rejected before combat settlement, case " + str(index))
			return
	broken = content["battleArt"].duplicate(true)
	broken["appearances"]["0:9"]["frames"].resize(1)
	if library.validate_catalog(
		content["battleClips"], content["entry"]["resourceDirectory"], broken
	):
		fail("Clip geometry must not reference frames removed from a participant appearance")
		return
	print(
		"PASS battle content: terrain references, actor/background textures, offsets and native sides"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
