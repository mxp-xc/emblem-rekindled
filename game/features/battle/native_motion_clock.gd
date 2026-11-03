extends RefCounted

const BOB_OFFSETS: Array[int] = [
	0,
	0,
	0,
	1,
	1,
	1,
	1,
	1,
	1,
	2,
	1,
	1,
	1,
	1,
	1,
	0,
	0,
	0,
	0,
	-1,
	-1,
	-2,
	-2,
	-2,
	-2,
	-2,
	-2,
	-2,
	-2,
	-2,
	-2,
	-2,
	-2,
	-1,
	-1,
	-1
]

# Incremental reconstruction of the original fighter's state, frame and position.
# Effects and battle playback integration are not yet implemented.
var state: int = 1
var step: int = 0
var frame: int = 0
var position: Vector2i
var position_supported: bool = false
var dodge_started: bool = false
var dodge_ended: bool = false
var impact_started: bool = false
var critical_magic_impact: bool = false
var critical_magic_prehit: bool = false
var critical_magic_jitter: int = 0
var wind_hit_started: bool = false
var wind_critical: bool = false
var special_magic_jitter: int = 0
var critical_preimpact: bool = false
var settled: bool = false
var source_state: int = 1
var source_step: int = 0
var _elapsed: int = -50
var _sequence_elapsed: int = 0
var _sequence_duration: int = 0
var _magic: bool = false
var _effect_kind: int
var _effect_active: bool = false
var _effect_cycles: int = 0
var _effect_elapsed: int = 0
var _bob_enabled: bool = false
var _bob_phase: int = 0
var _sequences: Array
var _sprite_period: int
var _sprite_sequence: int = 0
var _sprite_index: int = 0
var _sprite_elapsed: int = 0
var _sprite_playing: bool = false
var _sprite_cycles: int = 1
var _class: int
var _side: int
var _critical: bool
var _thrown: bool
var _lance: bool
var _miss: bool
var _origin: Vector2i
var _distance: int = 0
var _critical_distance: int = 0


static func supports(action: Dictionary) -> bool:
	var kind: int = int(action.get("effectKind", -1))
	return (
		kind in [3, 4, 5, 6, 7, 8, 11, 12]
		or (
			kind in [0, 1]
			and int(action.get("R", -1)) in [0, 2, 4, 5, 6, 7, 8]
			and (not action.get("thrown", false) or int(action.get("R", -1)) in [0, 2, 4])
		)
	)


func _init(action: Dictionary, outcome: String = "hit", defender: Dictionary = {}) -> void:
	assert(supports(action))
	_effect_kind = int(action["effectKind"])
	_magic = _effect_kind in [3, 4, 5, 6, 7, 8, 11, 12]
	_class = int(action["R"])
	_bob_enabled = bool(action.get("aT", false))
	_side = int(action["I"])
	_critical = outcome == "critical"
	_miss = outcome == "miss"
	_thrown = bool(action["thrown"])
	_lance = bool(action["lance"])
	_sequences = action["sequences"]
	_sprite_period = int(action["aF"])
	frame = int(_sequences[0][0])
	position_supported = _magic or _class == 5 or _thrown or not defender.is_empty()
	if position_supported:
		_origin = Vector2i(int(action["o"]), int(action["p"]) - int(action["au"]))
		position = _origin
	if not _magic and _class in [0, 2, 4, 6, 7, 8] and not defender.is_empty():
		var attacker_edge: int = int(action["o"]) + int(action["frames"][3][0])
		var defender_edge: int = (
			int(defender["o"]) + int(defender["at"]) - int(defender["frames"][0][0]) + 5
		)
		if int(action["I"]) == 1:
			attacker_edge = int(action["o"]) + int(action["at"]) - int(action["frames"][3][0])
			defender_edge = int(defender["o"]) + int(defender["frames"][0][0]) - 5
		_distance = defender_edge - attacker_edge
		_critical_distance = _distance
		if _class == 0:
			if int(action["I"]) == 1:
				attacker_edge = int(action["o"]) + int(action["at"]) - int(action["frames"][8][0])
				defender_edge = int(defender["o"]) + (int(defender["frames"][0][0]) >> 1)
			else:
				attacker_edge = int(action["o"]) + int(action["frames"][8][0])
				defender_edge = (
					int(defender["o"]) + int(defender["at"]) - (int(defender["frames"][0][0]) >> 1)
				)
			_critical_distance = defender_edge - attacker_edge
	if not _magic:
		_sequence_duration = int(action["aF"]) * action["sequences"][4 if _thrown else 1].size()
		if _class == 8:
			_sequence_duration *= 3


func advance() -> void:
	var previous_state: int = state
	var previous_step: int = step
	source_state = previous_state
	source_step = previous_step
	dodge_started = false
	dodge_ended = false
	impact_started = false
	critical_preimpact = (
		_critical
		and not _magic
		and not _thrown
		and previous_state == 3
		and ((_class == 0 and previous_step == 2) or (_class == 4 and previous_step == 6))
	)
	critical_magic_prehit = (
		_critical
		and previous_state == 3
		and (
			(_effect_kind == 4 and previous_step == 22)
			or (_effect_kind in [7, 8] and previous_step == 2)
		)
	)
	critical_magic_jitter = 16 if _effect_kind == 8 else (10 if _effect_kind == 7 else 8)
	wind_hit_started = (
		not _miss
		and _effect_kind in [5, 6]
		and previous_state == 3
		and previous_step == (2 if _effect_kind == 5 else 3)
	)
	wind_critical = _critical and _effect_kind in [5, 6]
	special_magic_jitter = 0
	if not _miss and _effect_kind == 11 and previous_state == 3 and previous_step == 1:
		special_magic_jitter = 8
	elif not _miss and _effect_kind == 12 and previous_state == 3 and previous_step == 14:
		special_magic_jitter = 4
	settled = false
	if _effect_active:
		_effect_elapsed += 50
		# fire.sp, wind.sp and light.sp each have two frames; the original
		# effect sprite advances a frame every 100 logical units.
		if _effect_elapsed >= 200:
			_effect_elapsed = 0
			if _effect_cycles > 0:
				_effect_cycles -= 1
				if _effect_cycles == 0:
					_effect_active = false
	if _sprite_playing:
		_sprite_elapsed += 50
		if _sprite_elapsed >= _sprite_period:
			_sprite_elapsed = 0
			_sprite_index += 1
			if _sprite_index >= _sequences[_sprite_sequence].size():
				_sprite_cycles -= 1
				if _sprite_cycles > 0:
					_sprite_index = 0
				else:
					_sprite_index = _sequences[_sprite_sequence].size() - 1
					_sprite_playing = false
			frame = int(_sequences[_sprite_sequence][_sprite_index])
	if not _magic and _class == 8 and state == 2 and _sequence_elapsed >= 50:
		if position_supported:
			position.x += 1 if _side == 1 else -1
	match state:
		1:
			_elapsed += 50
			if _elapsed >= (100 if _magic else 200):
				if not _magic and not _thrown and _class in [2, 6, 7]:
					state = 7
				else:
					state = 2
					_sequence_elapsed = 0
					_select_sequence(4 if _thrown else 1)
					if not _magic and _class == 8:
						_sprite_cycles = 3
		2:
			_sequence_elapsed += 50
			if _sequence_elapsed >= (500 if _magic else _sequence_duration):
				state = 3
				if _magic:
					_select_sequence(2)
		3:
			if _magic:
				if _effect_kind in [11, 12]:
					if step == 20:
						state = 5
						step = 0
						_elapsed = 0
						_select_sequence(0)
					step += 1
				else:
					_advance_magic_effect()
			elif _thrown:
				if step == 7:
					_select_sequence(6 if _lance else 5)
				if step == 16:
					state = 4
					step = 0
				step += 1
			elif (
				step
				>= (22 if _critical and _class == 0 else (24 if _critical and _class == 4 else 10))
			):
				step = 0
				state = 10 if _class in [2, 6, 7] else 4
				_select_sequence(3)
			else:
				if _critical and _class == 0:
					if step == 0:
						_select_sequence(7)
						if position_supported:
							position = _origin + Vector2i(_critical_distance >> 1, -20)
					elif step == 2:
						_select_sequence(8)
						if position_supported:
							position = _origin + Vector2i(_critical_distance, 0)
					elif step == 10:
						_select_sequence(6)
					elif step == 14:
						_select_sequence(2)
				elif _critical and _class == 4:
					if step == 6:
						_select_sequence(2)
						if position_supported:
							position.x = _origin.x + _distance
					elif step == 14:
						_select_sequence(3)
					elif step == 16:
						_select_sequence(7)
				elif step == 0:
					_select_sequence(2)
					if position_supported and _class == 0:
						position.x = _origin.x + int(float(_distance) / 2.0)
					elif position_supported and _class == 4:
						position.x = _origin.x + _distance
					elif position_supported and _class in [2, 6]:
						position.x = _origin.x + int(float(_distance * 2) / 3.0)
					elif position_supported and _class == 7:
						position = _origin + Vector2i(_distance, 0)
					elif position_supported and _class == 8:
						position.x = _origin.x + _distance
				step += 1
		4:
			state = 5
			_elapsed = 0
			_select_sequence(0)
			if position_supported:
				position = _origin
		5:
			_elapsed += 50
			if _elapsed >= (500 if _magic else 150):
				state = 0
		7, 9:
			if step == 0:
				_select_sequence(6 if _critical and state == 7 and _class != 7 else 1)
				if position_supported:
					if _class == 7:
						position = _origin
					elif state == 9 or not _critical:
						position.x = _origin.x + int(float(_distance) / 3.0)
			step += 1
			var duration: int = 10 if _critical and state == 7 and _class != 7 else 4
			if step == duration:
				step = 0
				state = 8 if state == 7 else 4
		8, 10:
			if step == 0:
				_select_sequence(3)
				if position_supported:
					if _class == 7:
						position = Vector2i(_origin.x + (_distance >> 1), position.y - 16)
					elif state == 10 or not _critical:
						position.x = _origin.x + int(float(_distance * 2) / 3.0)
			step += 1
			if step == (2 if _class == 7 else 4):
				step = 0
				state = 3 if state == 8 else 9
	if _bob_enabled and state != 3 and position_supported:
		position.y = _origin.y + BOB_OFFSETS[_bob_phase]
		_bob_phase = (_bob_phase + 1) % BOB_OFFSETS.size()
	settled = previous_state != 5 and state == 5
	if not _miss and previous_state == 3:
		if _magic:
			impact_started = previous_step == 14 if _effect_kind in [11, 12] else settled
		elif _thrown:
			impact_started = previous_step == 1
		elif _critical and _class == 0:
			impact_started = previous_step == 14
		elif _critical and _class == 4:
			impact_started = previous_step == 16
		else:
			impact_started = previous_step == 0
	if _miss:
		if previous_state == 3:
			var dodge_step: int = 0
			if _magic:
				dodge_step = (
					14
					if _effect_kind == 12
					else (2 if _effect_kind == 5 else (3 if _effect_kind == 6 else 1))
				)
			elif _thrown:
				dodge_step = 1
			dodge_started = previous_step == dodge_step
		dodge_ended = (
			(_magic and previous_state == 5 and state == 0)
			or (not _magic and previous_state == 4)
			or (not _magic and previous_state == 10 and previous_step == 0)
		)
	critical_magic_impact = _critical and _magic and _effect_kind == 3 and impact_started


func _select_sequence(index: int) -> void:
	_sprite_sequence = index
	_sprite_index = 0
	_sprite_elapsed = 0
	_sprite_cycles = 1
	_sprite_playing = true
	frame = int(_sequences[index][0])


func sync_wait_elapsed(elapsed_before_tick: int) -> void:
	if state == 5:
		_elapsed = elapsed_before_tick


func _advance_magic_effect() -> void:
	if step == 1:
		_effect_active = true
		_effect_elapsed = 0
		_effect_cycles = -1 if _effect_kind in [5, 6] or (_effect_kind == 3 and _critical) else 3
	if _critical and _effect_kind in [4, 8] and step == 2:
		_effect_cycles = 6
	if _critical and _effect_kind == 7 and step == 2:
		_effect_cycles = 4
	if _critical and _effect_kind in [3, 7] and step == 5:
		_effect_cycles = 2
	if _effect_kind in [5, 6] and step == (2 if _effect_kind == 5 else 3):
		_effect_cycles = 6 if _critical else 3
	if step > 1 and not _effect_active:
		step = 0
		state = 5
		_elapsed = 0
		_select_sequence(0)
		return
	step += 1
