extends SceneTree
const Session = preload("res://app/chapter_session.gd")
const Content = preload("res://app/chapter_content.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var draws: Array[int] = []


func _initialize() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
	content["map"]["locations"] = [
		{
			"id": "chest_0",
			"sourceIndex": 0,
			"kind": "chest",
			"position": [actor["x"], actor["y"]],
			"tileId": 79,
			"weightedChoices": [{"templateId": 2, "weight": 100}],
			"openedVariant": "opened_chest"
		}
	]
	var costs: Dictionary = {}
	for group: int in range(11):
		costs[str(group)] = 1
	content["map"]["tileVariants"] = {
		"opened_chest":
		{
			"tileId": 88,
			"terrain": 1,
			"texture": content["entry"]["mapTexture"],
			"movementCosts": costs
		}
	}
	var battle: RefCounted = Battle.new(content, _roll)
	draws.clear()
	if "open_chest" not in battle.actions_for(0):
		fail("A ready blue unit on an unopened chest must offer the explicit action")
		return
	var before: int = battle.unit(0)["inventory"].size()
	var result: Dictionary = battle.open_chest(0)
	if (
		not result["ok"]
		or not result["claimed"]
		or battle.unit(0)["inventory"].size() != before + 1
	):
		fail("A successful action must claim one held item")
		return
	if (
		draws != [100]
		or battle.unit(0)["action"] != 2
		or not battle.event_completed("location:chest_0")
	):
		fail("Claim commits once, draws once and ends the action")
		return
	if battle.open_chest(0)["ok"] or draws != [100]:
		fail("Repeated input cannot claim or draw again")
		return
	var opened_state: Dictionary = battle.snapshot()
	var current_map: Dictionary = battle.map_state()["map"]
	var x: int = int(actor["x"])
	var y: int = int(actor["y"])
	if current_map["tiles"][y][x] != 88 or current_map["terrain"][y][x] != 1:
		fail("Opened projection updates tile and terrain")
		return
	var closed_battle: RefCounted = Battle.new(content, _roll)
	var closed: Dictionary = closed_battle.snapshot()
	draws.clear()
	if (
		not battle.restore_snapshot(closed)["ok"]
		or not battle.map_state()["overlays"].is_empty()
		or battle.map_state()["map"]["tiles"] != content["map"]["tiles"]
	):
		fail("Restoring unopened record must reset the private map")
		return
	if (
		not battle.restore_snapshot(opened_state)["ok"]
		or battle.map_state()["map"]["tiles"][y][x] != 88
		or not draws.is_empty()
	):
		fail("Restoring claimed record projects opened terrain without any random draws")
		return
	var invalid: Dictionary = opened_state.duplicate(true)
	invalid["events"]["location:unknown"] = true
	var before_invalid: Dictionary = battle.snapshot()
	if battle.restore_snapshot(invalid)["ok"] or battle.snapshot() != before_invalid:
		fail("Unknown location rejects atomically")
		return
	var entry: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/chapter.json")
	)
	var definition_path: String = entry["battles"]["m0"]
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(definition_path))
	var documents: Dictionary = {"user://chest-chapter.json": entry, definition_path: definition}
	for path: String in [entry["library"], definition["deployments"], definition["story"]]:
		documents[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	var valid_map: Dictionary = content["map"].duplicate(true)
	valid_map["locations"][0]["tileId"] = valid_map["tiles"][y][x]
	valid_map["terrain"][y][x] = 7
	# This isolated chest also adds a terrain absent from m0's scene catalog.
	var scene: Dictionary = documents[entry["library"]]["scenes"][definition["scene"]]
	scene["terrainBackgrounds"]["7"] = scene["terrainBackgrounds"].values()[0]
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var icon: String = "user://chest-tile.tres"
	if ResourceSaver.save(ImageTexture.create_from_image(image), icon) != OK:
		fail("Isolated 24px fixture texture must save")
		return
	valid_map["tileVariants"]["opened_chest"]["texture"] = icon
	for group: int in range(11):
		if not valid_map["movementCosts"].has(str(group)):
			valid_map["movementCosts"][str(group)] = (
				valid_map["movementCosts"].values()[0].duplicate(true)
			)
	definition["map"] = "user://chest-map.json"
	var file := FileAccess.open(definition["map"], FileAccess.WRITE)
	file.store_string(JSON.stringify(valid_map))
	file.close()
	var loaded: Dictionary = Content.new().load_chapter(
		"user://chest-chapter.json", "m0", {}, documents
	)
	if not loaded["ok"]:
		fail("Valid chest content must load through the public boundary: " + str(loaded))
		return
	for invalid_kind: String in [
		"weight", "large_weight", "coordinate", "template", "position", "variant", "texture", "unit"
	]:
		var bad_map: Dictionary = valid_map.duplicate(true)
		var bad_documents: Dictionary = documents.duplicate(true)
		match invalid_kind:
			"weight":
				bad_map["locations"][0]["weightedChoices"][0]["weight"] = 0
			"large_weight":
				bad_map["locations"][0]["weightedChoices"][0]["weight"] = 1e100
			"coordinate":
				bad_map["locations"][0]["position"] = [4294967296, 0]
				bad_map["locations"][0]["tileId"] = bad_map["tiles"][0][0]
			"template":
				bad_map["locations"][0]["weightedChoices"][0]["templateId"] = 999
			"position":
				var duplicate_location: Dictionary = bad_map["locations"][0].duplicate(true)
				duplicate_location["id"] = "chest_1"
				bad_map["locations"].append(duplicate_location)
			"variant":
				bad_map["locations"][0]["openedVariant"] = "missing"
			"texture":
				bad_map["tileVariants"]["opened_chest"]["texture"] = "res://missing-chest.png"
			"unit":
				bad_documents[definition["story"]]["locationEvents"] = [
					{"locationId": "chest_0", "unitIds": [999]}
				]
		file = FileAccess.open(definition["map"], FileAccess.WRITE)
		file.store_string(JSON.stringify(bad_map))
		file.close()
		if Content.new().load_chapter("user://chest-chapter.json", "m0", {}, bad_documents)["ok"]:
			fail("Invalid chest declaration must reject before opening input: " + invalid_kind)
			return
	print(
		"PASS chest save: reversible private projection, zero draw restore, atomic invalid key rejection"
	)
	quit(0)


func _roll(limit: int) -> int:
	draws.append(limit)
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
