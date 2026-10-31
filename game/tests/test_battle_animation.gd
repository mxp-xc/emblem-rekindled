extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	if not content["ok"]:
		fail(str(content))
		return
	var library: RefCounted = load("res://app/battle_clip_library.gd").new(content)
	# Controlled presentation inputs: a fire hit, an axe counter, then a fatal fire critical.
	var participants: Array = []
	for id: int in [54, 0]:
		for unit: Dictionary in content["units"]:
			if unit["id"] == id:
				participants.append(unit.duplicate(true))
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
	var animation: RefCounted = load("res://features/battle/battle_animation.gd").new(prepared)
	var changed: Array[int] = []
	var carried_effect: bool = false
	var died: bool = false
	var previous_index: int = 0
	for iteration: int in range(500):
		animation.advance()
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
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_battle_hp.json")
	)
	# Source actor53/fire and legal actor54/fire share the proven geometry.
	if changed[0] != oracle["cases"]["53:40|hit|slot0|damage7|recovery0"]["endTick"]:
		fail("The counter must not add an extra display interval after the first completion")
		return
	print(
		"PASS battle animation: counter/follow-up timing, HP identity, residual FX, death, stable layers"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
