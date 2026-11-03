extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var library: RefCounted = load("res://app/battle_clip_library.gd").new(content)
	var appearances: Dictionary = content["battleClips"]["appearances"]
	var representatives: Dictionary = {}
	for key: String in appearances:
		var definition: Dictionary = appearances[key]
		var signature: String = (
			str(definition.get("actionGroup")) + "/" + definition["defenseGroup"]
		)
		if not representatives.has(signature):
			representatives[signature] = key
	for attacker: String in representatives.values():
		for defender: String in representatives.values():
			if (
				content["battleArt"]["appearances"][attacker]["nativeSide"]
				== content["battleArt"]["appearances"][defender]["nativeSide"]
			):
				continue
			var pair: Array = [_actor(content, attacker), _actor(content, defender)]
			var forecasts: Dictionary = {}
			for index: int in range(2):
				forecasts[str(int(pair[index]["id"]))] = {
					"canAttack": appearances[[attacker, defender][index]]["canAttack"]
				}
			var loaded: Dictionary = library.preload_pair(
				{"participants": pair, "forecasts": forecasts}
			)
			if not loaded["ok"]:
				fail(str(loaded))
				return
	# The original chooses thrown geometry from the post-resolution weapon, but keeps
	# the initial participant appearance, even if an enemy auto-equips a backup.
	var prepared: Dictionary = library.prepare(
		{
			"participants": [_actor(content, "97:17"), _actor(content, "59:13")],
			"resolvedWeapons": {"97": 13, "59": 13},
			"strikes":
			[
				{
					"attacker": 97,
					"defender": 59,
					"hit": true,
					"critical": false,
					"damage": 7,
					"heal": 0
				}
			]
		}
	)
	if not prepared["ok"] or prepared["appearances"]["97"] != "97:17":
		fail("Weapon depletion must retain the initial composed participant appearance")
		return
	if prepared["timelines"][0]["actionGroup"] != appearances["97:13"]["actionGroup"]:
		fail("A depleted thrown weapon must use ordinary geometry after auto-equipping a backup")
		return
	var action: String = appearances["0:9"]["actionGroup"]
	var defense: String = appearances["54:40"]["defenseGroup"]
	var missing: Dictionary = content["battleClips"].duplicate(false)
	missing["clips"] = content["battleClips"]["clips"].duplicate()
	missing["clips"].erase("%s/%s/1/miss" % [action, defense])
	if not library.validate_catalog(
		missing, content["entry"]["resourceDirectory"], content["battleArt"]
	):
		fail("A generated miss must not require a sampled clip mapping")
		return
	missing["clips"].erase("%s/%s/1/hit" % [action, defense])
	if not library.validate_catalog(
		missing, content["entry"]["resourceDirectory"], content["battleArt"]
	):
		fail("A generated hit must not require a sampled clip mapping")
		return
	missing["clips"].erase("%s/%s/1/critical" % [action, defense])
	if not library.validate_catalog(
		missing, content["entry"]["resourceDirectory"], content["battleArt"]
	):
		fail("A generated critical must not require a sampled clip mapping")
		return
	var sampled_action: String = appearances["53:48"]["actionGroup"]
	var sampled_defense: String = appearances["0:9"]["defenseGroup"]
	missing["clips"].erase("%s/%s/1/critical" % [sampled_action, sampled_defense])
	if not library.validate_catalog(
		missing, content["entry"]["resourceDirectory"], content["battleArt"]
	):
		fail("A generated special-magic critical must not require a sampled clip mapping")
		return
	missing["clips"] = {}
	if not library.validate_catalog(
		missing, content["entry"]["resourceDirectory"], content["battleArt"]
	):
		fail("A fully generated catalog must allow an empty clip mapping")
		return
	print(
		"PASS battle clips: all native-side action/defense pairs, hit/miss/critical, depleted throws"
	)
	quit(0)


func _actor(content: Dictionary, appearance: String) -> Dictionary:
	var id: int = appearance.get_slice(":", 0).to_int()
	var weapon: int = appearance.get_slice(":", 1).to_int()
	for unit: Dictionary in content["units"]:
		if int(unit["id"]) == id:
			var actor: Dictionary = unit.duplicate(true)
			actor["inventory"] = (
				[] if weapon == 0 else [{"id": "held", "templateId": weapon, "durability": 3}]
			)
			actor["equippedInstanceId"] = "held" if weapon > 0 else ""
			return actor
	return {}


func fail(message: String) -> void:
	push_error(message)
	quit(1)
