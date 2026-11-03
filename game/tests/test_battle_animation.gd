extends SceneTree

const BattleAnimation = preload("res://features/battle/battle_animation.gd")
const BattleClipLibrary = preload("res://app/battle_clip_library.gd")


func _initialize() -> void:
	var opened: Dictionary = load("res://app/chapter_session.gd").new().open(
		"res://content/chapter_1/chapter.json",
		"",
		{"new": true},
		func(_limit: int) -> int: return 0
	)
	if not opened["ok"]:
		fail(str(opened))
		return
	var content: Dictionary = opened["content"]
	var library: RefCounted = BattleClipLibrary.new(content)
	# Controlled presentation inputs: a wind hit, an axe counter, then a fatal wind critical.
	var participants: Array = []
	for id: int in [54, 0]:
		participants.append(opened["battle"].unit(id))
	participants[0]["hp"] = 20
	participants[1]["hp"] = 40
	var result: Dictionary = {
		"participants": participants,
		"resolvedWeapons": {"54": 40, "0": 9},
		"strikes":
		[
			{"attacker": 54, "defender": 0, "hit": true, "critical": false, "damage": 7, "heal": 0},
			{"attacker": 0, "defender": 54, "hit": true, "critical": false, "damage": 5, "heal": 0},
			{"attacker": 54, "defender": 0, "hit": true, "critical": true, "damage": 33, "heal": 0}
		]
	}
	var before: Dictionary = result.duplicate(true)
	var prepared: Dictionary = library.prepare(result)
	if not prepared["ok"]:
		fail(str(prepared))
		return
	prepared["visualSeed"] = 0
	var animation: RefCounted = BattleAnimation.new(prepared)
	var changed: Array[int] = []
	var carried_effect: bool = false
	var died: bool = false
	var previous_index: int = 0
	for iteration: int in range(500):
		animation.advance()
		var sampled_clip: Dictionary = prepared["timelines"][animation.current_index]["clip"]
		if not sampled_clip.is_empty():
			var expected_terrain: Dictionary = sampled_clip["terrainPlacement"]
			for role: String in ["attacker", "defender"]:
				for field: String in animation.frame["terrainPlacement"][role]:
					if (
						animation.frame["terrainPlacement"][role][field]
						!= expected_terrain[role][field]
					):
						fail("Generated terrain differs for %s field %s" % [role, field])
						return
		if animation.current_index != previous_index:
			changed.append(animation.global_tick)
			if animation.frame["actionTick"] != 0:
				fail("Counter and follow-up must start at tick0 in the same completion update")
				return
			previous_index = animation.current_index
		if animation.current_index == 1 and animation.frame["actionTick"] == 0:
			for layer: Dictionary in animation.frame["layers"]:
				if str(layer.get("instanceId", "")).begins_with("action:0:"):
					carried_effect = true
		var previous_layer: Dictionary = {}
		for layer: Dictionary in animation.frame["layers"]:
			if not previous_layer.is_empty():
				if previous_layer["foreground"] and not layer["foreground"]:
					fail("Effect/body composition must preserve foreground buckets")
					return
				if (
					previous_layer["foreground"] == layer["foreground"]
					and previous_layer["order"] > layer["order"]
				):
					fail("Effects must retain their original creation order")
					return
			previous_layer = layer
			if animation.hp[0] == 0 and layer.get("unit", -1) == 0:
				fail("A dead defender body must be removed at the HP death tick")
				return
			if str(layer.get("instanceId", "")).begins_with("death:0:"):
				died = true
		if animation.finished:
			break
	if not animation.finished or animation.hp != {54: 15, 0: 0} or changed.size() != 2:
		fail("A complete attack/counter/follow-up must retain each participant's display HP")
		return
	if not carried_effect or not died or result != before:
		fail("Residual FX, death effects and immutable committed combat input must be preserved")
		return
	if (
		not prepared["timelines"][0].has("nativeEffects")
		or not prepared["timelines"][1].has("nativeEffects")
		or not prepared["timelines"][2].has("nativeEffects")
	):
		fail(
			(
				"Unexpected native-effect selection: %s"
				% [
					prepared["timelines"].map(
						func(t: Dictionary) -> bool: return t.has("nativeEffects")
					)
				]
			)
		)
		return
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_battle_hp.json")
	)
	# Source actor53/fire and legal actor54/fire share the proven geometry.
	if changed[0] != oracle["cases"]["53:40|hit|slot0|damage7|recovery0"]["endTick"]:
		fail("The counter must not add an extra display interval after the first completion")
		return
	var miss_result: Dictionary = result.duplicate(true)
	miss_result["strikes"] = [
		{"attacker": 0, "defender": 54, "hit": false, "critical": false, "damage": 0, "heal": 0}
	]
	var miss_prepared: Dictionary = library.prepare(miss_result)
	if not miss_prepared["ok"]:
		fail(str(miss_prepared))
		return
	miss_prepared["visualSeed"] = 0
	var miss_animation: RefCounted = BattleAnimation.new(miss_prepared)
	var miss_timeline: Dictionary = miss_prepared["timelines"][0]
	if not miss_timeline["generated"] or not miss_timeline["clip"].is_empty():
		fail("Supported misses must not load a sampled clip")
		return
	var miss_key: String = (
		"%s/%s/%d/miss"
		% [miss_timeline["actionGroup"], miss_timeline["defenseGroup"], miss_timeline["sourceSlot"]]
	)
	var without_sample: Dictionary = content.duplicate(false)
	without_sample["battleClips"] = content["battleClips"].duplicate(false)
	without_sample["battleClips"]["clips"] = content["battleClips"]["clips"].duplicate()
	without_sample["battleClips"]["clips"].erase(miss_key)
	var generated_library: RefCounted = BattleClipLibrary.new(without_sample)
	if not generated_library.prepare(miss_result)["ok"]:
		fail("Generated misses must work without the sampled clip mapping")
		return
	var miss_oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_battle_miss.json")
	)
	if miss_oracle["source"] != miss_key:
		fail("Miss oracle does not match selected action")
		return
	for index: int in range(miss_oracle["ticks"].size()):
		miss_animation.advance()
		var actual: Dictionary = {}
		var expected: Array = miss_oracle["ticks"][index]
		for layer: Dictionary in miss_animation.frame["layers"]:
			if layer.get("actor") == "defender":
				actual = layer
		if (
			actual.is_empty()
			or int(actual["frame"]) != int(expected[0])
			or int(actual["x"]) != int(expected[1])
			or int(actual["y"]) != int(expected[2])
		):
			fail("Generated defender dodge differs at tick %d" % index)
			return
		var actual_shake: Array = miss_animation.frame["backgroundOffset"]
		if (
			(
				Vector2i(int(actual_shake[0]), int(actual_shake[1]))
				!= Vector2i(int(expected[3]), int(expected[4]))
			)
			or miss_animation.frame["flash"] != null
		):
			fail("Generated scene differs at tick %d" % index)
			return
	if not miss_prepared["timelines"][0].has("nativeDefender"):
		fail("Misses must use generated defender motion")
		return
	print(
		"PASS battle animation: counter/follow-up timing, HP identity, residual FX, death, stable layers"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
