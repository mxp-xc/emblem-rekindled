extends RefCounted

const Clock = preload("res://features/battle/native_motion_clock.gd")

# The render-time hit jitter consumes the same random stream as screen shake.
var frame: int
var position: Vector2i
var wind_settle_displaced: bool = false
var _origin: Vector2i
var _defender: Dictionary
var _dodging: bool = false
var _bob_phase: int = 0
var _bob_offset: int = 0
var _jitter_ticks: int = 0
var _wind_offset: int = 0


func _init(defender: Dictionary) -> void:
	_defender = defender
	_origin = Vector2i(int(defender["o"]), int(defender["p"]) - int(defender["au"]))
	position = _origin
	frame = int(defender["sequences"][0][0])


func advance(clock: RefCounted, source_slot: int = 0) -> void:
	var previous_bob: int = _bob_offset
	if _jitter_ticks > 0:
		_jitter_ticks -= 1
	if _defender.get("aT", false):
		_bob_offset = Clock.BOB_OFFSETS[_bob_phase]
		_bob_phase = (_bob_phase + 1) % Clock.BOB_OFFSETS.size()
	if clock.dodge_started:
		_dodging = true
		var sequence: int = 1 if int(_defender["R"]) == 7 else 3
		frame = int(_defender["sequences"][sequence][0])
	if clock.dodge_ended:
		_dodging = false
		frame = int(_defender["sequences"][0][0])
	if clock.special_magic_jitter > 0:
		_jitter_ticks = clock.special_magic_jitter
	elif clock.wind_hit_started:
		_jitter_ticks = 20 if clock.wind_critical else 8
	elif clock.impact_started and not int(clock._effect_kind) in [5, 6, 11, 12]:
		_jitter_ticks = 4 if clock.critical_magic_impact else 2
	elif clock.critical_preimpact:
		_jitter_ticks = 4
	elif clock.critical_magic_prehit:
		_jitter_ticks = clock.critical_magic_jitter
	position = _origin + Vector2i(0, _bob_offset)
	wind_settle_displaced = _bob_offset != 0
	if (
		clock.wind_critical
		and int(clock._effect_kind) == 5
		and clock.source_state == 3
		and clock.source_step > 1
	):
		var floating: bool = _defender.get("aT", false)
		var offset: int = (
			(previous_bob if source_slot == 0 else _bob_offset) if floating else _wind_offset
		)
		var age: int = clock.source_step - 1
		if age > 1 and offset > -12:
			offset -= age - 1
		if clock.settled:
			wind_settle_displaced = offset != 0
			offset = _bob_offset if floating and source_slot == 0 else 0
		elif floating and source_slot == 0:
			offset = _bob_offset
		_wind_offset = offset
		position.y = _origin.y + offset
	elif (
		source_slot == 1 and clock.settled and not clock._miss and int(clock._effect_kind) in [5, 6]
	):
		position.y -= _bob_offset
	if _dodging:
		position += Vector2i(4 if int(_defender["I"]) == 1 else -4, -6)


func draw_jitter(scene: RefCounted) -> void:
	if _jitter_ticks > 0:
		position += scene.draw_jitter()
