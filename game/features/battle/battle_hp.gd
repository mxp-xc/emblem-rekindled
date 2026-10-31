extends RefCounted

var tick: int = -1
var attacker_hp: int
var defender_hp: int
var attacker_state: int = 1
var attacker_step: int = 0
var last_action_units: int = 0
var damage_active: bool = false
var recovery_active: bool = false
var died_this_tick: bool = false
var finished: bool = false
var _clip: Dictionary
var _slot: int
var _impact: int
var _settle: int
var _wait: int
var _target_hp: int
var _recovered_hp: int
var _logic_tick_units: int


func _init(
	clip: Dictionary,
	initial_attacker_hp: int,
	initial_defender_hp: int,
	damage: int,
	recovery: int,
	logic_tick_units: int
) -> void:
	_clip = clip
	_slot = int(clip["sourceSlot"])
	_impact = int(clip["impactTick"])
	_settle = int(clip["settleTick"])
	_wait = int(clip["completionWaitUnits"])
	_logic_tick_units = logic_tick_units
	attacker_hp = initial_attacker_hp
	defender_hp = initial_defender_hp
	_target_hp = maxi(0, defender_hp - damage)
	_recovered_hp = attacker_hp + recovery


func advance() -> void:
	if finished:
		return
	tick += 1
	died_this_tick = false
	var now: int = tick * _logic_tick_units
	if _slot == 1:
		_damage(now)
	if recovery_active:
		attacker_hp = mini(_recovered_hp, attacker_hp + 4)
		recovery_active = attacker_hp < _recovered_hp
		last_action_units = now
	var source: Dictionary = _clip["ticks"][mini(tick, _clip["ticks"].size() - 1)]
	attacker_step = int(source["attackerStep"])
	if tick == _impact:
		damage_active = true
		recovery_active = attacker_hp < _recovered_hp
	if tick < _settle:
		attacker_state = int(source["attackerState"])
	elif tick == _settle:
		attacker_state = 5
		last_action_units = now
	else:
		finished = now - last_action_units >= _wait
		attacker_state = 0 if finished else 5
	if _slot == 0:
		_damage(now)


func _damage(now: int) -> void:
	if damage_active and defender_hp > _target_hp:
		defender_hp = maxi(_target_hp, defender_hp - 4)
		damage_active = defender_hp > _target_hp
		last_action_units = now
		died_this_tick = defender_hp == 0
