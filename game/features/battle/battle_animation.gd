extends RefCounted

const Hp = preload("res://features/battle/battle_hp.gd")
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


func _init(prepared: Dictionary) -> void:
	_data = prepared
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
	for previous: Dictionary in _carry:
		previous["tick"] += 1
	for death: Dictionary in _deaths:
		death["tick"] += 1
	_current_hp.advance()
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
			_carry.append({"index": current_index, "tick": _current_hp.tick})
			current_index += 1
			_start_action()
			_current_hp.advance()
			_update_hp()
		else:
			finished = true
	_compose()


func _start_action() -> void:
	var timeline: Dictionary = _data["timelines"][current_index]
	var strike: Dictionary = timeline["strike"]
	_current_hp = Hp.new(
		timeline["clip"],
		hp[int(strike["attacker"])],
		hp[int(strike["defender"])],
		int(strike["damage"]),
		int(strike["heal"]),
		int(_data["logicTickUnits"])
	)


func _update_hp() -> void:
	var strike: Dictionary = _data["timelines"][current_index]["strike"]
	hp[int(strike["attacker"])] = _current_hp.attacker_hp
	hp[int(strike["defender"])] = _current_hp.defender_hp


func _compose() -> void:
	var timeline: Dictionary = _data["timelines"][current_index]
	var clip: Dictionary = timeline["clip"]
	var pose: Dictionary = clip["ticks"][mini(_current_hp.tick, clip["ticks"].size() - 1)]
	var layers: Array[Dictionary] = []
	for source: Dictionary in pose["layers"]:
		if not source.has("actor"):
			continue
		var id: int = int(timeline["strike"][source["actor"]])
		if hp[id] <= 0 or not source["visible"]:
			continue
		var actor: Dictionary = source.duplicate()
		actor["unit"] = id
		actor["appearance"] = _data["appearances"][str(id)]
		actor["order"] = _birth["unit:" + str(id)]
		layers.append(actor)
	for previous: Dictionary in _carry:
		var previous_clip: Dictionary = _data["timelines"][previous["index"]]["clip"]
		_add_effects(
			layers, _effects(previous_clip, previous["tick"]), "action:" + str(previous["index"])
		)
	var slot: int = int(clip["sourceSlot"])
	# Slot1 updates the defending unit's HP/death before the attacking unit creates effects.
	if slot == 1:
		_add_deaths(layers)
	_add_effects(layers, _effects(clip, _current_hp.tick), "action:" + str(current_index))
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
		"terrainPlacement": clip["terrainPlacement"],
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


func _effects(clip: Dictionary, tick: int) -> Array:
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
