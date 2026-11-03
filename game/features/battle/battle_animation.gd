extends RefCounted

const Hp = preload("res://features/battle/native_battle_hp.gd")
const NativeEffects = preload("res://features/battle/native_basic_effects.gd")
const NativeDefender = preload("res://features/battle/native_defender_motion.gd")
const NativeTerrain = preload("res://features/battle/native_terrain_placement.gd")
const NativeScene = preload("res://features/battle/native_scene_clock.gd")
const NativeRandom = preload("res://features/battle/native_random.gd")
var finished: bool = false
var global_tick: int = -1
var current_index: int = 0
var frame: Dictionary = {}
var hp: Dictionary = {}
var _data: Dictionary
var _current_hp: RefCounted
var _carry: Array[Dictionary] = []
var _deaths: Array[Dictionary] = []
var _birth: Dictionary = {}
var _next_birth: int = 2
var _visual_random: RefCounted


func _init(prepared: Dictionary) -> void:
	_data = prepared
	var seed: int
	if prepared.has("visualSeed"):
		seed = int(prepared["visualSeed"])
	else:
		var entropy := RandomNumberGenerator.new()
		entropy.randomize()
		seed = int(entropy.randi()) | ((int(entropy.randi()) & 0xffff) << 32)
	_visual_random = NativeRandom.new(seed)
	for index: int in range(prepared["participants"].size()):
		var actor: Dictionary = prepared["participants"][index]
		hp[int(actor["id"])] = int(actor["hp"])
		_birth["unit:" + str(int(actor["id"]))] = index
	finished = prepared["timelines"].is_empty()
	if not finished:
		_start_action()


func advance() -> void:
	if finished:
		return
	global_tick += 1
	var active_carry: Array[Dictionary] = []
	for previous: Dictionary in _carry:
		previous["tick"] += 1
		var carried: Dictionary = _data["timelines"][previous["index"]]
		if carried.has("nativeEffects"):
			carried["nativeEffects"].advance(carried["nativeMotion"])
		if _has_tail(carried, previous["tick"]):
			active_carry.append(previous)
	_carry = active_carry
	for death: Dictionary in _deaths:
		death["tick"] += 1
	_current_hp.advance()
	var current: Dictionary = _data["timelines"][current_index]
	if current.has("nativeDefender"):
		current["nativeDefender"].advance(_current_hp.motion, int(current["sourceSlot"]))
	if current.has("nativeEffects"):
		current["nativeEffects"].advance(_current_hp.motion)
	if current.has("nativeScene"):
		current["nativeScene"].advance(_current_hp.motion, global_tick, current["nativeDefender"])
		if _current_hp.defender_hp > 0:
			current["nativeDefender"].draw_jitter(current["nativeScene"])
	_update_hp()
	if _current_hp.died_this_tick:
		var timeline: Dictionary = _data["timelines"][current_index]
		_deaths.append(
			{
				"unit": int(timeline["strike"]["defender"]),
				"group": timeline["defenseGroup"],
				"tick": 0
			}
		)
	if _current_hp.finished:
		if current_index + 1 < _data["timelines"].size():
			# The next result starts in this same original update, without an extra display tick.
			if _has_tail(current, _current_hp.tick):
				_carry.append({"index": current_index, "tick": _current_hp.tick})
			current_index += 1
			_start_action()
			_current_hp.advance()
			current = _data["timelines"][current_index]
			if current.has("nativeDefender"):
				current["nativeDefender"].advance(_current_hp.motion, int(current["sourceSlot"]))
			if current.has("nativeEffects"):
				current["nativeEffects"].advance(_current_hp.motion)
			if current.has("nativeScene"):
				current["nativeScene"].advance(
					_current_hp.motion, global_tick, current["nativeDefender"]
				)
				if _current_hp.defender_hp > 0:
					current["nativeDefender"].draw_jitter(current["nativeScene"])
			_update_hp()
		else:
			finished = true
	_compose()


func _start_action() -> void:
	var timeline: Dictionary = _data["timelines"][current_index]
	var strike: Dictionary = timeline["strike"]
	var outcome: String = (
		"miss" if not strike["hit"] else ("critical" if strike["critical"] else "hit")
	)
	var source_slot: int = (
		0 if int(strike["attacker"]) == int(_data["participants"][0]["id"]) else 1
	)
	_current_hp = Hp.new(
		_data["actionGroups"][timeline["actionGroup"]],
		_data["defenseGroups"][timeline["defenseGroup"]],
		outcome,
		source_slot,
		hp[int(strike["attacker"])],
		hp[int(strike["defender"])],
		int(strike["damage"]),
		int(strike["heal"])
	)
	var action: Dictionary = _data["actionGroups"][timeline["actionGroup"]]
	var defender: Dictionary = _data["defenseGroups"][timeline["defenseGroup"]]
	var placement: Dictionary = {}
	for actor: Dictionary in _data["participants"]:
		var role: String = "attacker" if int(actor["id"]) == int(strike["attacker"]) else "defender"
		var terrain: int = int(_data["mapTerrain"][int(actor["y"])][int(actor["x"])])
		var art: Dictionary = _data["battleArt"]
		var background: Dictionary = art["backgrounds"][art["terrainBackgrounds"][str(terrain)]]
		placement[role] = NativeTerrain.calculate(
			action if role == "attacker" else defender, background, _data["stageGeometry"]
		)
	timeline["nativeTerrain"] = placement
	if outcome == "miss" or timeline["generated"]:
		timeline["nativeDefender"] = NativeDefender.new(defender)
	if timeline["generated"]:
		timeline["nativeScene"] = NativeScene.new(action, _visual_random, source_slot, outcome)
		timeline["nativeRandom"] = _visual_random
	if (
		NativeEffects.supports(action, outcome)
		and (
			timeline["generated"]
			or (outcome != "critical" and int(action["effectKind"]) not in [5, 6, 11, 12])
		)
	):
		timeline["nativeMotion"] = _current_hp.motion
		timeline["nativeEffects"] = NativeEffects.new(
			action,
			defender,
			outcome,
			_data["battleEffects"],
			timeline["projectile"],
			timeline.get("nativeRandom")
		)


func _update_hp() -> void:
	var strike: Dictionary = _data["timelines"][current_index]["strike"]
	hp[int(strike["attacker"])] = _current_hp.attacker_hp
	hp[int(strike["defender"])] = _current_hp.defender_hp


func _compose() -> void:
	var timeline: Dictionary = _data["timelines"][current_index]
	var clip: Dictionary = timeline["clip"]
	var pose: Dictionary
	if timeline["generated"]:
		var offset: Vector2i = timeline["nativeScene"].offset
		pose = {
			"layers":
			[
				{"actor": "defender", "visible": true, "foreground": false},
				{"actor": "attacker", "visible": true, "foreground": true}
			],
			"sky": {},
			"backgroundOffset": [offset.x, offset.y],
			"flash": timeline["nativeScene"].flash
		}
	else:
		pose = clip["ticks"][mini(_current_hp.tick, clip["ticks"].size() - 1)]
	var layers: Array[Dictionary] = []
	for source: Dictionary in pose["layers"]:
		if not source.has("actor"):
			continue
		var id: int = int(timeline["strike"][source["actor"]])
		if hp[id] <= 0 or not source["visible"]:
			continue
		var actor: Dictionary = source.duplicate()
		if source["actor"] == "attacker":
			var motion: RefCounted = _current_hp.motion
			actor["frame"] = motion.frame
			actor["x"] = motion.position.x
			actor["y"] = motion.position.y
		elif timeline.has("nativeDefender"):
			var defense: RefCounted = timeline["nativeDefender"]
			actor["frame"] = defense.frame
			actor["x"] = defense.position.x
			actor["y"] = defense.position.y
		actor["unit"] = id
		actor["appearance"] = _data["appearances"][str(id)]
		actor["order"] = _birth["unit:" + str(id)]
		layers.append(actor)
	for previous: Dictionary in _carry:
		var previous_timeline: Dictionary = _data["timelines"][previous["index"]]
		_add_effects(
			layers,
			_effects(previous_timeline, previous["tick"]),
			"action:" + str(previous["index"])
		)
	var slot: int = int(timeline["sourceSlot"])
	# Slot1 updates the defending unit's HP/death before the attacking unit creates effects.
	if slot == 1:
		_add_deaths(layers)
	_add_effects(layers, _effects(timeline, _current_hp.tick), "action:" + str(current_index))
	if slot == 0:
		_add_deaths(layers)
	layers.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["foreground"] != b["foreground"]:
				return not a["foreground"]
			return a["order"] < b["order"]
	)
	frame = {
		"sky": pose["sky"],
		"backgroundOffset": pose["backgroundOffset"],
		"terrainPlacement": timeline["nativeTerrain"],
		"roles":
		{
			"attacker": int(timeline["strike"]["attacker"]),
			"defender": int(timeline["strike"]["defender"])
		},
		"layers": layers,
		"flash": pose["flash"],
		"hp": hp.duplicate(),
		"actionTick": _current_hp.tick
	}
	var kind: int = int(_data["actionGroups"][timeline["actionGroup"]]["effectKind"])
	if (
		timeline["generated"]
		or (
			current_index == 0
			and not timeline["strike"]["critical"]
			and kind in [0, 1, 3, 4, 5, 6, 8]
		)
	):
		var cloud: Dictionary = _data["battleEffects"]["cloud"]
		frame["nativeSky"] = {
			"cloud": cloud,
			"scroll": (global_tick + 1) % (int(cloud["virtualWidth"]) - 1),
			"stage": _data["stageGeometry"]["stage"],
			"color": timeline["nativeScene"].sky_color if timeline.has("nativeScene") else null,
			"criticalRemaining":
			timeline["nativeScene"].critical_sky_remaining if timeline.has("nativeScene") else 0
		}


func _has_tail(timeline: Dictionary, tick: int) -> bool:
	if timeline.has("nativeEffects"):
		return timeline["nativeEffects"].has_live_effects()
	var clip: Dictionary = timeline["clip"]
	return tick < clip["ticks"].size() + clip["effectTailTicks"].size()


func _effects(timeline: Dictionary, tick: int) -> Array:
	if timeline.has("nativeEffects"):
		var generated: Array[Dictionary] = []
		for effect: Dictionary in timeline["nativeEffects"].layers:
			var layer := {
				"x": effect["position"].x,
				"y": effect["position"].y,
				"instance": effect["instance"],
				"foreground": effect["foreground"]
			}
			if effect.has("beam"):
				layer["beam"] = effect["beam"]
			elif effect.has("particles"):
				layer["particles"] = effect["particles"]
			else:
				layer["textureSource"] = effect["texture"]
			generated.append(layer)
		return generated
	var clip: Dictionary = timeline["clip"]
	if tick < clip["ticks"].size():
		return clip["ticks"][tick]["layers"].filter(
			func(layer: Dictionary) -> bool: return not layer.has("actor")
		)
	var tail_index: int = tick - clip["ticks"].size()
	return (
		clip["effectTailTicks"][tail_index] if tail_index < clip["effectTailTicks"].size() else []
	)


func _add_deaths(layers: Array[Dictionary]) -> void:
	for death: Dictionary in _deaths:
		var ticks: Array = _data["deaths"][death["group"]]["ticks"]
		if death["tick"] < ticks.size():
			_add_effects(layers, ticks[death["tick"]], "death:" + str(death["unit"]))


func _add_effects(layers: Array[Dictionary], effects: Array, namespace_id: String) -> void:
	for source: Dictionary in effects:
		var id: String = namespace_id + ":" + str(int(source["instance"]))
		if not _birth.has(id):
			_birth[id] = _next_birth
			_next_birth += 1
		var effect: Dictionary = source.duplicate()
		effect["instanceId"] = id
		effect["order"] = _birth[id]
		layers.append(effect)
