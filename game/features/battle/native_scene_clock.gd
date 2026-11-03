extends RefCounted

const NativeRandom = preload("res://features/battle/native_random.gd")
const Effects = preload("res://features/battle/native_basic_effects.gd")

# Reconstructs native scene effects for the currently supported action programs.
# Other outcomes still require shared RNG ordering.
var offset: Vector2i = Vector2i.ZERO
var sky_color: Variant = null
var critical_sky_remaining: int = 0
var flash: Variant = null
var _random: RefCounted
var _action: Dictionary
var _active: bool = false
var _vertical: bool = false
var _started: int = 0
var _duration: int = 0
var _source_slot: int
var _sky_flash_remaining: int = 0
var _critical: bool = false
var _critical_intro_started: bool = false
var _flash_remaining: int = 0


static func supports(action: Dictionary, outcome: String) -> bool:
	return Effects.supports(action, outcome)


func _init(
	action: Dictionary, random: RefCounted, source_slot: int = 0, outcome: String = "hit"
) -> void:
	_action = action
	_random = random
	_source_slot = source_slot
	_critical = outcome == "critical"


func advance(motion: RefCounted, tick: int, defender: RefCounted = null) -> void:
	var now: int = tick * 50
	if _active and now - _started >= _duration:
		_active = false
	var kind: int = int(_action["effectKind"])
	var class_id: int = int(_action["R"])
	critical_sky_remaining = maxi(0, critical_sky_remaining - 2)
	_flash_remaining = maxi(0, _flash_remaining - 1)
	var intro_time: bool = (
		motion.source_state == 7
		or (motion.source_state == 2 and (kind not in [0, 1] or class_id != 4 or _action["thrown"]))
		or (
			motion.source_state == 3
			and motion.source_step == 0
			and kind in [0, 1]
			and class_id == 4
			and not _action["thrown"]
		)
	)
	if _critical and intro_time and not _critical_intro_started:
		_critical_intro_started = true
		critical_sky_remaining = 12 - (1 if _source_slot == 0 else 0)
	if _critical and motion.impact_started and kind in [0, 1, 3]:
		_flash_remaining = 3
	flash = 0 if _flash_remaining > 0 and _flash_remaining % 2 == 0 else null
	_sky_flash_remaining = maxi(0, _sky_flash_remaining - 2)
	if _critical and kind in [4, 8] and motion.source_state == 3 and motion.source_step == 2:
		_sky_flash_remaining = 34 - (1 if _source_slot == 0 else 0)
	if _critical and kind == 7 and motion.source_state == 3 and motion.source_step == 2:
		_sky_flash_remaining = 22 - (1 if _source_slot == 0 else 0)
	if _critical and kind == 6 and motion.source_state == 3 and motion.source_step == 21:
		_sky_flash_remaining = 9 - (1 if _source_slot == 0 else 0)
	if (
		_critical
		and kind == 11
		and motion.source_state == 3
		and motion.source_step == 1
		and not motion.dodge_started
	):
		_sky_flash_remaining = 18 - (1 if _source_slot == 0 else 0)
	if _critical and kind == 12 and motion.source_state == 3 and motion.source_step == 5:
		_sky_flash_remaining = 18 - (1 if _source_slot == 0 else 0)
	if (
		not _critical
		and kind == 7
		and motion.source_state == 3
		and motion.source_step == 1
		and not motion.dodge_started
	):
		_sky_flash_remaining = 18 - (1 if _source_slot == 0 else 0)
	sky_color = null
	if _sky_flash_remaining > 0:
		sky_color = 0 if ((tick + 1) % 80) % 2 == 0 else 0xffffff
	if kind in [0, 1]:
		if class_id == 0 and motion.source_state == 2 and motion.state == 3:
			_start(now, 200, false)
		elif (
			class_id in [2, 6]
			and not _action["thrown"]
			and motion.source_state in [7, 8, 9, 10]
			and motion.source_step == 0
			and (not _critical or motion.source_state in [9, 10])
		):
			_start(now, 100, true)
	if motion.impact_started and kind == 12:
		_start(now, 200, false)
	elif motion.impact_started and kind not in [5, 6, 11, 12]:
		_start(now, 200 if _critical and kind in [0, 1, 3] else 100, false)
	elif (
		motion.impact_started
		and kind in [5, 6]
		and defender != null
		and defender.wind_settle_displaced
	):
		_start(now, 200, false)
	elif _critical and kind in [5, 6] and motion.wind_hit_started:
		_start(now, 300, false)
	elif motion.critical_preimpact:
		_start(now, 200, false)
	elif _critical and kind == 4 and motion.source_state == 3 and motion.source_step == 22:
		_start(now, 500, false)
	elif _critical and kind == 8 and motion.source_state == 3 and motion.source_step == 2:
		_start(now, 900, false)
	elif _critical and kind == 7 and motion.source_state == 3 and motion.source_step == 2:
		_start(now, 600, false)
	elif (
		kind == 11
		and motion.source_state == 3
		and motion.source_step == 1
		and not motion.dodge_started
	):
		_start(now, 500, false)
	elif kind == 12 and motion.source_state == 3 and motion.source_step in [5, 7, 10]:
		_start(now, 100, true)
	offset = Vector2i.ZERO
	if _active:
		var x: int = _random.next_int() % 10
		var y: int = _random.next_int() % 3
		offset = Vector2i(0 if _vertical else x, y)


func draw_jitter() -> Vector2i:
	return Vector2i(_random.native_range(-4, 5), _random.native_range(-1, 2))


func _start(now: int, duration: int, vertical: bool) -> void:
	_active = true
	_started = now
	_duration = duration
	_vertical = vertical
