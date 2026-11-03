extends RefCounted

const Motion = preload("res://features/battle/native_motion_clock.gd")

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
var motion: RefCounted
var _slot: int
var _target_hp: int
var _recovered_hp: int
var _damage_step: int = 4


func _init(
	action: Dictionary,
	defender: Dictionary,
	outcome: String,
	source_slot: int,
	initial_attacker_hp: int,
	initial_defender_hp: int,
	damage: int,
	recovery: int
) -> void:
	assert(source_slot in [0, 1])
	motion = Motion.new(action, outcome, defender)
	_slot = source_slot
	attacker_hp = initial_attacker_hp
	defender_hp = initial_defender_hp
	_target_hp = maxi(0, defender_hp - damage)
	_recovered_hp = attacker_hp + recovery
	_damage_step = 99 if int(action.get("effectKind", -1)) == 11 else 4


func advance() -> void:
	if finished:
		return
	tick += 1
	died_this_tick = false
	var now: int = tick * 50
	if _slot == 1:
		_damage(now)
	if recovery_active:
		attacker_hp = mini(_recovered_hp, attacker_hp + 4)
		recovery_active = attacker_hp < _recovered_hp
		last_action_units = now
	motion.sync_wait_elapsed(now - 50 - last_action_units)
	motion.advance()
	attacker_state = motion.state
	attacker_step = motion.step
	if motion.impact_started:
		damage_active = true
		recovery_active = attacker_hp < _recovered_hp
	if motion.settled:
		last_action_units = now
	finished = motion.state == 0
	if _slot == 0:
		_damage(now)


func _damage(now: int) -> void:
	if damage_active and defender_hp > _target_hp:
		defender_hp = maxi(_target_hp, defender_hp - _damage_step)
		damage_active = defender_hp > _target_hp
		last_action_units = now
		died_this_tick = defender_hp == 0
